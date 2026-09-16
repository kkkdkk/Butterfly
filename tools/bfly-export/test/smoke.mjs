// Run only with synthetic files produced by app/tool/bfly_export_fixture.dart.
// node test/smoke.mjs fixture.bfly empty.bfly [output-root] [--browser auto]
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import * as fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { chromium } from 'playwright';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const cli = path.join(repo, 'tools/bfly-export/cli.mjs');
const sha = bytes => createHash('sha256').update(bytes).digest('hex');

async function main() {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: { browser: { type: 'string', default: 'auto' } },
  });
  assert.ok(positionals.length >= 2 && positionals.length <= 3,
    'Usage: node test/smoke.mjs fixture.bfly empty.bfly [output-root] [--browser auto|msedge|chrome|chromium]');
  assert.ok(['auto', 'msedge', 'chrome', 'chromium'].includes(values.browser));
  const fixture = await fs.realpath(positionals[0]), empty = await fs.realpath(positionals[1]);
  const outputRoot = path.resolve(positionals[2] || path.join(repo, '.magicpie-output/bfly-export'));
  await fs.mkdir(outputRoot, { recursive: true });
  const runRoot = await fs.mkdtemp(path.join(outputRoot, 'smoke-'));
  console.log(`Synthetic smoke artifacts (retained): ${runRoot}`);
  const sourceHashes = new Map();
  for (const file of [fixture, empty]) sourceHashes.set(file, sha(await fs.readFile(file)));

  async function checkSources() {
    for (const [file, hash] of sourceHashes) {
      assert.equal(sha(await fs.readFile(file)), hash, `Source was modified: ${file}`);
    }
  }

  async function run(name, inputs, flags = [], { failure = false, output = path.join(runRoot, name) } = {}) {
    const args = [cli, ...inputs, '--output', output, '--browser', values.browser, ...flags];
    const result = await new Promise(resolve => {
      execFile(process.execPath, args, { cwd: repo, windowsHide: true, timeout: 240000, maxBuffer: 8 * 1024 * 1024 },
        (error, stdout, stderr) => resolve({ error, stdout, stderr }));
    });
    await fs.writeFile(path.join(runRoot, `${name}.log`), result.stdout + result.stderr, { flag: 'wx' });
    await checkSources();
    const records = result.stdout.trim() ? result.stdout.trim().split(/\r?\n/).map(line => JSON.parse(line)) : [];
    if (failure) {
      assert.ok(result.error && !result.error.killed, `${name} must fail normally, not succeed or time out`);
      assert.equal(records.length, 0, `${name} must not publish a document`);
    } else {
      assert.equal(result.error, null, `${name} failed:\n${result.stderr}`);
      assert.equal(records.length, inputs.length === 1 && inputs[0] !== fixture && inputs[0] !== empty ? 2 : inputs.length);
      for (const record of records) {
        assert.equal(path.dirname(record.output), output);
        assert.equal(record.manifest, path.join(record.output, 'manifest.json'));
        record.data = JSON.parse(await fs.readFile(record.manifest, 'utf8'));
        assert.equal(record.images, record.data.images.length);
        assert.equal(record.data.source.sha256, sha(await fs.readFile(record.source)));
        for (const image of record.data.images) {
          assert.match(image.file, /^page-\d{4}(?:-area-\d{4})?\.png$/);
          const bytes = await fs.readFile(path.join(record.output, image.file));
          assert.equal(bytes.readUInt32BE(16), image.width);
          assert.equal(bytes.readUInt32BE(20), image.height);
        }
      }
    }
    console.log(`PASS ${name}`);
    return { records, output, stderr: result.stderr };
  }

  const all = await run('all-pages', [fixture, empty], ['--all-pages']);
  assert.deepEqual(all.records.map(record => record.images), [2, 1]);
  const firstPage = all.records[0].data.images[0];
  assert.equal(firstPage.displayName, 'Pressure and assets');
  assert.ok(all.records[0].data.images[1].bounds.x < 0, 'Negative coordinates must be preserved');

  const areas = await run('areas', [fixture], ['--areas']);
  assert.equal(areas.records[0].images, 2);
  const board = areas.records[0].data.images[0];
  assert.equal(board.areaName, 'Acceptance board');
  assert.deepEqual(board.bounds, { x: 0, y: 0, width: 760, height: 620 });
  for (const [name, page] of [['display-page', firstPage.displayName], ['internal-page', firstPage.pageName]]) {
    const selected = await run(name, [fixture], ['--page', page]);
    assert.equal(selected.records[0].images, 1);
    assert.equal(selected.records[0].data.images[0].pageName, firstPage.pageName);
  }

  const manifestHash = sha(await fs.readFile(all.records[0].manifest));
  const existing = await run('existing-output', [fixture], [], { failure: true, output: all.output });
  assert.match(existing.stderr, /Output already exists/);
  assert.equal(sha(await fs.readFile(all.records[0].manifest)), manifestHash);

  const missing = await run('missing-page', [fixture], ['--page', 'No such synthetic page'], { failure: true });
  assert.match(missing.stderr, /Page not found/);
  assert.deepEqual(await fs.readdir(missing.output), []);
  const bad = path.join(runRoot, 'corrupt-synthetic.bfly');
  await fs.writeFile(bad, (await fs.readFile(fixture)).subarray(0, 24), { flag: 'wx' });
  const corrupt = await run('corrupt-file', [bad], [], { failure: true });
  assert.deepEqual(await fs.readdir(corrupt.output), []);

  const limited = await run('pixel-limits', [fixture], ['--scale', '8', '--max-dimension', '512', '--max-pixels', '65536']);
  for (const image of limited.records[0].data.images) {
    assert.ok(image.width <= 512 && image.height <= 512);
    assert.ok(image.width * image.height <= 65536);
    assert.equal(image.limited, true);
  }
  assert.equal(Math.max(limited.records[0].data.images[1].width, limited.records[0].data.images[1].height), 512);

  const directory = path.join(runRoot, 'synthetic-inputs');
  await fs.mkdir(path.join(directory, 'nested'), { recursive: true });
  const fixtureCopy = path.join(directory, 'fixture.bfly'), emptyCopy = path.join(directory, 'empty.bfly');
  await fs.copyFile(fixture, fixtureCopy, fs.constants.COPYFILE_EXCL);
  await fs.copyFile(empty, emptyCopy, fs.constants.COPYFILE_EXCL);
  await fs.copyFile(bad, path.join(directory, 'nested', 'must-not-scan.bfly'), fs.constants.COPYFILE_EXCL);
  sourceHashes.set(fixtureCopy, sourceHashes.get(fixture));
  sourceHashes.set(emptyCopy, sourceHashes.get(empty));
  const batch = await run('directory-batch', [directory]);
  assert.deepEqual(batch.records.map(record => record.images).sort(), [1, 2]);

  const channels = values.browser === 'auto'
    ? (process.platform === 'win32' ? ['msedge', 'chrome', 'chromium'] : ['chromium']) : [values.browser];
  let browser, launchError;
  for (const channel of channels) {
    try { browser = await chromium.launch({ headless: true, ...(channel === 'chromium' ? {} : { channel }) }); break; }
    catch (error) { launchError = error; }
  }
  if (!browser) throw launchError;
  let pixels;
  try {
    const page = await browser.newPage();
    await page.route('**/*', route => route.abort());
    const png = await fs.readFile(path.join(areas.records[0].output, board.file));
    pixels = await page.evaluate(async ({ base64, bounds, scale }) => {
      const bytes = Uint8Array.from(atob(base64), character => character.charCodeAt(0));
      const bitmap = await createImageBitmap(new Blob([bytes], { type: 'image/png' }));
      const canvas = document.createElement('canvas');
      canvas.width = bitmap.width; canvas.height = bitmap.height;
      const context = canvas.getContext('2d', { willReadFrequently: true });
      context.drawImage(bitmap, 0, 0); bitmap.close();
      const data = context.getImageData(0, 0, canvas.width, canvas.height).data;
      const pixel = (x, y) => {
        const px = Math.floor((x - bounds.x) * scale), py = Math.floor((y - bounds.y) * scale);
        return Array.from(data.subarray((py * canvas.width + px) * 4, (py * canvas.width + px) * 4 + 4));
      };
      const black = rgba => rgba.length === 4 && rgba[3] > 240 && rgba.slice(0, 3).every(value => value < 64);
      const white = rgba => rgba.length === 4 && rgba[3] > 240 && rgba.slice(0, 3).every(value => value > 240);
      const thickness = (x, y) => {
        let count = 0;
        for (let step = -Math.ceil(30 * scale); step <= Math.ceil(30 * scale); step++) {
          if (black(pixel(x, y + step / scale))) count++;
        }
        return count;
      };
      const checkerboard = [];
      for (let row = 0; row < 6; row++) {
        for (let column = 0; column < 6; column++) {
          const rgba = pixel(50 + 20 * column, 350 + 20 * row);
          checkerboard.push((row + column) % 2 === 0 ? black(rgba) : white(rgba));
        }
      }
      return { thickness: [thickness(100, 155), thickness(600, 155), thickness(100, 270), thickness(600, 270)], checkerboard };
    }, { base64: png.toString('base64'), bounds: board.bounds, scale: board.actualScale });
  } finally { await browser.close(); }
  const [upThin, upThick, downThick, downThin] = pixels.thickness;
  assert.ok(upThin > 0 && downThin > 0 && upThick > upThin * 2 && downThick > downThin * 2,
    `Pressure must change thickness in both directions: ${JSON.stringify(pixels.thickness)}`);
  assert.equal(pixels.checkerboard.length, 36);
  assert.ok(pixels.checkerboard.every(Boolean), 'All 36 embedded checkerboard cells must match');
  await checkSources();
  console.log(`PASS pixels: pressure thickness ${pixels.thickness.join('/')} px; checkerboard 36/36`);
  const summary = { passed: true, runRoot, pressureThickness: pixels.thickness, checkerboardCells: 36, sourceHashes: Object.fromEntries(sourceHashes) };
  await fs.writeFile(path.join(runRoot, 'smoke-result.json'), JSON.stringify(summary, null, 2) + '\n', { flag: 'wx' });
  console.log(JSON.stringify(summary));
}

main().catch(error => { console.error(error); process.exitCode = 1; });
