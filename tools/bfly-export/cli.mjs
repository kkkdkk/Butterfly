#!/usr/bin/env node
import * as fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { collectInputs, decodePng, destinationName, parseOptions, readSnapshot, selectJobs, serveWorker, withTimeout } from './lib.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const help = `bfly-export FILE.bfly [MORE.bfly | DIRECTORY] --output DIRECTORY [options]
  --all-pages              Export every page (default)
  --page NAME              Export named page; repeat for multiple pages
  --areas                  Export each named area, or whole page when none exists
  --scale NUMBER           Requested pixels per document unit (default 2)
  --max-dimension NUMBER   Maximum PNG width/height (default 4096, max 8192)
  --max-pixels NUMBER      Maximum pixels per PNG (default 16777216)
  --margin NUMBER          Whole-page border in document units (default 24)
  --browser NAME           auto, msedge, chrome, chromium (default auto)
  --font FILE              Local font for imported text (e.g. a CJK TTF/OTF/TTC)
  --web-dir DIRECTORY      Built export worker (default app/build/bfly-export)
  --timeout-ms NUMBER      Per-operation limit (default 120000)
Source files are read-only. Each source is exported into a hash-named subdirectory.
Existing output is never overwritten. Directory input is non-recursive.
Run tools/bfly-export/build.ps1 and npm ci in tools/bfly-export before first use.`;

async function main() {
  const options = parseOptions(process.argv.slice(2));
  if (options.help) { console.log(help); return; }
  const inputs = await collectInputs(options.inputs);
  const webDir = path.resolve(options['web-dir'] || path.join(repo, 'app/build/bfly-export'));
  try { await fs.access(path.join(webDir, 'index.html')); }
  catch { throw new Error(`Export worker not built: ${webDir}. Run tools/bfly-export/build.ps1 first.`); }
  let chromium;
  try { ({ chromium } = await import('playwright')); }
  catch { throw new Error('Playwright is missing. Run npm ci in tools/bfly-export.'); }
  await fs.mkdir(path.resolve(options.output), { recursive: true });
  const outputRoot = await fs.realpath(path.resolve(options.output));
  const server = await serveWorker(webDir);
  let browser;
  try {
    const channels = options.browser === 'auto' ? (process.platform === 'win32' ? ['msedge', 'chrome', 'chromium'] : ['chromium']) : [options.browser];
    let launchError;
    for (const channel of channels) {
      try { browser = await chromium.launch({ headless: true, ...(channel === 'chromium' ? {} : { channel }) }); break; }
      catch (error) { launchError = error; }
    }
    if (!browser) throw new Error(`Could not launch a browser. Install Edge/Chrome or run npx playwright install chromium in tools/bfly-export. ${launchError?.message}`);
    const context = await browser.newContext({ viewport: { width: 1024, height: 768 }, serviceWorkers: 'block' });
    const deniedRequests = [];
    await context.route('**/*', route => {
      const url = route.request().url();
      if (url.startsWith(server.origin + '/') || url.startsWith('data:') || url.startsWith('blob:')) return route.continue();
      deniedRequests.push(new URL(url).origin);
      return route.abort('blockedbyclient');
    });
    const font = options.font ? await readSnapshot(path.resolve(options.font)) : null;
    if (font) {
      // CanvasKit otherwise keeps matching the bundled Latin-only Roboto face
      // ahead of the dynamically registered local font with the same family.
      const manifest = JSON.parse(await fs.readFile(path.join(webDir, 'assets/FontManifest.json'), 'utf8'));
      await context.route(server.origin + '/assets/FontManifest.json', route => route.fulfill({ json: manifest.filter(entry => entry.family !== 'Roboto') }));
    }
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(server.origin, { waitUntil: 'load', timeout: options['timeout-ms'] });
    try {
      await page.waitForFunction(() => window.bflyExportReady === true || window.bflyExportError, null, { timeout: options['timeout-ms'] });
      const startupError = await page.evaluate(() => window.bflyExportError);
      if (startupError) throw new Error(startupError);
    }
    catch (error) { throw new Error(`Worker did not become ready: ${error.message}. ${errors.slice(-3).join('; ')}${deniedRequests.length ? ' Worker requested external assets; rebuild with --no-web-resources-cdn.' : ''}`); }
    const invoke = request => withTimeout(page.evaluate(request => window.bflyExport(request), request), options['timeout-ms'], request.op);
    if (font) {
      await invoke({ op: 'loadFont', base64: font.bytes.toString('base64'), family: 'Roboto' });
    }
    let failures = 0;
    for (const input of inputs) {
      let stage;
      try {
        const snapshot = await readSnapshot(input);
        const destination = path.join(outputRoot, destinationName(input, snapshot.hash));
        try { await fs.access(destination); throw new Error(`Output already exists; choose another --output directory: ${destination}`); }
        catch (error) { if (error.code !== 'ENOENT') throw error; }
        deniedRequests.length = 0;
        const document = await invoke({ op: 'load', base64: snapshot.bytes.toString('base64') });
        if (document.protocolVersion !== 1) throw new Error('Incompatible export worker; rebuild it.');
        const jobs = selectJobs(document.pages, options);
        stage = await fs.mkdtemp(path.join(outputRoot, '.bfly-export-'));
        const images = [];
        for (const job of jobs) {
          const result = await invoke({ op: 'render', pageName: job.pageName, ...(job.areaIndex === undefined ? {} : { areaIndex: job.areaIndex }), scale: options.scale, maxDimension: options['max-dimension'], maxPixels: options['max-pixels'], margin: options.margin });
          if (deniedRequests.length) throw new Error(`External resources blocked (${[...new Set(deniedRequests)].join(', ')}). Embed remote images and use --font for missing text glyphs; no external requests are permitted.`);
          const png = decodePng(result, options);
          await withTimeout(page.evaluate(async ({ base64, width, height }) => {
            const bytes = Uint8Array.from(atob(base64), character => character.charCodeAt(0));
            const bitmap = await createImageBitmap(new Blob([bytes], { type: 'image/png' }));
            try {
              if (bitmap.width !== width || bitmap.height !== height) throw new Error('Decoded PNG dimensions differ from renderer metadata.');
            } finally { bitmap.close(); }
          }, { base64: result.base64, width: result.width, height: result.height }), options['timeout-ms'], 'PNG validation');
          await fs.writeFile(path.join(stage, job.file), png, { flag: 'wx' });
          const { base64, ...metadata } = result;
          images.push({ ...metadata, file: job.file, pageIndex: job.pageIndex, displayName: job.displayName });
          console.error(`${path.basename(input)}: ${job.file} ${result.width}x${result.height}${result.limited ? ' (scaled to limit)' : ''}`);
        }
        const after = await readSnapshot(input);
        if (after.hash !== snapshot.hash) throw new Error('Source changed during export; output discarded. Retry after saving/syncing.');
        const manifest = {
          version: 1, generator: 'bfly-export/0.1.0', createdAt: new Date().toISOString(),
          source: { path: input, name: path.basename(input), sha256: snapshot.hash, bytes: snapshot.size },
          renderer: { name: 'Butterfly Flutter', protocolVersion: document.protocolVersion, ...(font ? { font: { name: path.basename(options.font), sha256: font.hash } } : {}) },
          images,
        };
        await fs.writeFile(path.join(stage, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n', { flag: 'wx' });
        await fs.rename(stage, destination);
        stage = undefined;
        console.log(JSON.stringify({ source: input, output: destination, images: images.length, manifest: path.join(destination, 'manifest.json') }));
      } catch (error) {
        failures++;
        console.error(`FAILED ${path.basename(input)}: ${error.message}`);
        if (error.message.includes('timed out')) throw new Error('Rendering timed out; batch stopped to avoid reusing an unfinished worker.');
      } finally {
        if (stage && path.dirname(stage) === outputRoot && path.basename(stage).startsWith('.bfly-export-')) await fs.rm(stage, { recursive: true, force: true });
      }
    }
    await invoke({ op: 'dispose' });
    if (failures) process.exitCode = 1;
  } finally {
    try { if (browser) await browser.close(); } finally { await server.close(); }
  }
}

main().catch(error => { console.error(`bfly-export: ${error.message}`); process.exitCode = 1; });
