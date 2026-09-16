import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { createReadStream } from 'node:fs';
import * as fs from 'node:fs/promises';
import path from 'node:path';
import { parseArgs } from 'node:util';

export function parseOptions(args) {
  const { values, positionals } = parseArgs({
    args, allowPositionals: true, options: {
      help: { type: 'boolean', short: 'h' },
      output: { type: 'string', short: 'o' },
      'all-pages': { type: 'boolean' },
      page: { type: 'string', multiple: true },
      areas: { type: 'boolean' },
      scale: { type: 'string', default: '2' },
      'max-dimension': { type: 'string', default: '4096' },
      'max-pixels': { type: 'string', default: '16777216' },
      margin: { type: 'string', default: '24' },
      'web-dir': { type: 'string' },
      browser: { type: 'string', default: 'auto' },
      font: { type: 'string' },
      'timeout-ms': { type: 'string', default: '120000' },
    },
  });
  if (values.help) return { help: true };
  if (!positionals.length || !values.output) throw new Error('Input .bfly file(s)/directory and --output are required.');
  if (values['all-pages'] && values.page) throw new Error('--all-pages and --page cannot be combined.');
  if (!['auto', 'msedge', 'chrome', 'chromium'].includes(values.browser)) throw new Error('Invalid --browser.');
  const ranges = {
    scale: [0.01, 8], 'max-dimension': [64, 8192],
    'max-pixels': [4096, 33554432], margin: [0, 1000], 'timeout-ms': [1000, 600000],
  };
  for (const [key, [min, max]] of Object.entries(ranges)) {
    values[key] = Number(values[key]);
    if (!Number.isFinite(values[key]) || values[key] < min || values[key] > max) throw new Error(`--${key} must be between ${min} and ${max}.`);
    if (['max-dimension', 'max-pixels', 'timeout-ms'].includes(key) && !Number.isInteger(values[key])) throw new Error(`--${key} must be an integer.`);
  }
  return { ...values, inputs: positionals };
}

export async function collectInputs(inputs) {
  const files = new Set();
  for (const value of inputs) {
    const full = await fs.realpath(path.resolve(value));
    const stat = await fs.stat(full);
    if (stat.isDirectory()) {
      for (const entry of (await fs.readdir(full, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name))) {
        if (entry.isFile() && entry.name.toLowerCase().endsWith('.bfly')) files.add(await fs.realpath(path.join(full, entry.name)));
      }
    } else if (stat.isFile() && full.toLowerCase().endsWith('.bfly')) files.add(full);
    else throw new Error(`Not a .bfly file or directory: ${value}`);
  }
  if (!files.size) throw new Error('No .bfly files found (directory scan is not recursive).');
  return [...files];
}

export async function readSnapshot(file) {
  const before = await fs.stat(file);
  if (!before.isFile() || before.size > 256 * 1024 * 1024) throw new Error('Input must be a file no larger than 256 MiB.');
  const bytes = await fs.readFile(file);
  const after = await fs.stat(file);
  if (before.size !== after.size || before.mtimeMs !== after.mtimeMs || bytes.length !== after.size) throw new Error('Source changed during snapshot; wait for synchronization to finish.');
  return { bytes, hash: createHash('sha256').update(bytes).digest('hex'), size: bytes.length };
}

export function destinationName(file, hash) {
  const stem = path.basename(file, path.extname(file)).replace(/[^\p{L}\p{N}_-]/gu, '_').slice(0, 64) || 'note';
  return `note-${stem}-${hash.slice(0, 16)}`;
}

export function selectJobs(pages, options) {
  if (!Array.isArray(pages) || pages.length > 500 || !pages.length) throw new Error('Document must contain 1–500 pages.');
  const requested = new Set(options.page || []);
  const selectedNames = new Set();
  for (const name of requested) {
    const exact = pages.filter(p => p.name === name);
    const matches = exact.length ? exact : pages.filter(p => p.displayName === name);
    if (!matches.length) throw new Error(`Page not found: ${name}`);
    if (matches.length !== 1) throw new Error(`Page name is ambiguous: ${name}. Use its internal page key.`);
    selectedNames.add(matches[0].name);
  }
  const jobs = [];
  pages.forEach((page, pageIndex) => {
    if (requested.size && !selectedNames.has(page.name)) return;
    const areas = options.areas && page.areas?.length ? page.areas : [null];
    areas.forEach((area, areaIndex) => {
      jobs.push({
        pageName: page.name, displayName: page.displayName ?? page.name, pageIndex, ...(area ? { areaIndex, areaName: area.name } : {}),
        file: `page-${String(pageIndex + 1).padStart(4, '0')}${area ? `-area-${String(areaIndex + 1).padStart(4, '0')}` : ''}.png`,
      });
    });
  });
  if (jobs.length > 1000) throw new Error('More than 1000 images requested; select fewer pages.');
  return jobs;
}

export function decodePng(result, options) {
  if (typeof result.base64 !== 'string') throw new Error('Renderer returned no PNG.');
  const bytes = Buffer.from(result.base64, 'base64');
  if (bytes.length < 33 || bytes.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a' || bytes.toString('ascii', 12, 16) !== 'IHDR') throw new Error('Renderer returned invalid PNG.');
  const width = bytes.readUInt32BE(16), height = bytes.readUInt32BE(20);
  if (width !== result.width || height !== result.height || !width || !height || width > options['max-dimension'] || height > options['max-dimension'] || width * height > options['max-pixels']) throw new Error('PNG dimensions do not match requested limits or renderer metadata.');
  const crcTable = new Uint32Array(256);
  for (let value = 0; value < crcTable.length; value++) {
    let crc = value;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    crcTable[value] = crc;
  }
  let hasData = false, hasEnd = false;
  for (let offset = 8; offset < bytes.length;) {
    if (bytes.length - offset < 12) throw new Error('Renderer returned a truncated PNG chunk.');
    const length = bytes.readUInt32BE(offset), next = offset + length + 12;
    if (next > bytes.length) throw new Error('Renderer returned a truncated PNG chunk.');
    const type = bytes.toString('ascii', offset + 4, offset + 8);
    if (!/^[A-Za-z]{4}$/.test(type) || (type === 'IHDR' && (offset !== 8 || length !== 13))) throw new Error('Renderer returned invalid PNG chunks.');
    let crc = 0xffffffff;
    for (let index = offset + 4; index < next - 4; index++) crc = crcTable[(crc ^ bytes[index]) & 255] ^ (crc >>> 8);
    if (((crc ^ 0xffffffff) >>> 0) !== bytes.readUInt32BE(next - 4)) throw new Error(`Renderer returned a PNG ${type} checksum mismatch.`);
    if (type === 'IDAT' && length > 0) hasData = true;
    if (type === 'IEND') {
      if (length !== 0 || next !== bytes.length) throw new Error('Renderer returned an invalid PNG end chunk.');
      hasEnd = true;
    }
    offset = next;
  }
  if (!hasData || !hasEnd) throw new Error('Renderer returned an incomplete PNG (missing image data or end chunk).');
  return bytes;
}

export function withTimeout(promise, milliseconds, label) {
  let timer;
  return Promise.race([promise, new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timed out after ${milliseconds} ms.`)), milliseconds);
  })]).finally(() => clearTimeout(timer));
}

export async function serveWorker(directory) {
  const root = await fs.realpath(directory);
  await fs.access(path.join(root, 'index.html'));
  const mime = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.ttf': 'font/ttf', '.otf': 'font/otf', '.png': 'image/png', '.svg': 'image/svg+xml' };
  const server = createServer(async (request, response) => {
    try {
      if (!['GET', 'HEAD'].includes(request.method)) { response.writeHead(405).end(); return; }
      const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
      let target = path.resolve(root, `.${pathname === '/' ? '/index.html' : pathname}`);
      if (!target.startsWith(root + path.sep)) { response.writeHead(403).end(); return; }
      target = await fs.realpath(target);
      if (!target.startsWith(root + path.sep)) { response.writeHead(403).end(); return; }
      if (!(await fs.stat(target)).isFile()) { response.writeHead(404).end(); return; }
      response.writeHead(200, { 'Content-Type': mime[path.extname(target)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
      if (request.method === 'HEAD') response.end();
      else createReadStream(target).on('error', () => response.destroy()).pipe(response);
    } catch { if (!response.headersSent) response.writeHead(404); response.end(); }
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  return {
    origin: `http://127.0.0.1:${server.address().port}`,
    close: () => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }),
  };
}
