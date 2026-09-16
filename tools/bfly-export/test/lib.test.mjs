import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { collectInputs, decodePng, destinationName, parseOptions, readSnapshot, selectJobs, serveWorker, withTimeout } from '../lib.mjs';

test('CLI validates numeric limits and conflicting page selections', () => {
  const options = parseOptions(['note.bfly', '-o', 'out', '--all-pages']);
  assert.equal(options.scale, 2);
  assert.deepEqual(options.inputs, ['note.bfly']);
  for (const args of [[], ['x.bfly', '-o', 'out', '--scale', 'NaN'], ['x.bfly', '-o', 'out', '--max-dimension', '9000'], ['x.bfly', '-o', 'out', '--max-pixels', '1.5'], ['x.bfly', '-o', 'out', '--all-pages', '--page', 'one'], ['x.bfly', '-o', 'out', '--browser', 'bad']]) assert.throws(() => parseOptions(args));
  assert.deepEqual(parseOptions(['--help']), { help: true });
});

test('area selection uses indexes, safe numeric names and whole-page fallback', () => {
  const pages = [{ name: '../one', areas: [{ name: 'duplicate' }, { name: 'duplicate' }] }, { name: 'two', areas: [] }];
  const jobs = selectJobs(pages, { areas: true });
  assert.equal(jobs.length, 3);
  assert.equal(jobs[1].areaIndex, 1);
  assert.equal(jobs[1].file, 'page-0001-area-0002.png');
  assert.equal(jobs[2].file, 'page-0002.png');
  assert.equal(selectJobs(pages, { page: ['two'] }).length, 1);
  assert.throws(() => selectJobs(pages, { page: ['missing'] }), /Page not found/);
  assert.equal(selectJobs([{ name: 'internal', displayName: 'My page' }], { page: ['My page'] })[0].pageName, 'internal');
  assert.throws(() => selectJobs([{ name: 'a', displayName: 'Duplicate' }, { name: 'b', displayName: 'Duplicate' }], { page: ['Duplicate'] }), /ambiguous/);
  assert.equal(selectJobs([{ name: '0.foo', displayName: 'foo' }, { name: '1.0.foo', displayName: '0.foo' }], { page: ['0.foo'] })[0].pageName, '0.foo');
});

test('source path cannot escape output directory through destination names', () => {
  assert.equal(destinationName('CON.bfly', 'a'.repeat(64)), 'note-CON-aaaaaaaaaaaaaaaa');
  assert.equal(destinationName('a ? b.bfly', 'b'.repeat(64)), 'note-a___b-bbbbbbbbbbbbbbbb');
});

test('PNG signature, complete chunks, checksums and dimensions are validated', () => {
  // A real 1x1 grayscale+alpha PNG, including valid zlib data and chunk CRCs.
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64');
  const result = { base64: png.toString('base64'), width: 1, height: 1 };
  const limits = { 'max-dimension': 64, 'max-pixels': 4096 };
  assert.deepEqual(decodePng(result, limits), png);
  assert.throws(() => decodePng(result, { ...limits, 'max-dimension': 0 }));
  assert.throws(() => decodePng(result, { ...limits, 'max-pixels': 0 }));
  assert.throws(() => decodePng({ ...result, width: 2 }, limits));
  assert.throws(() => decodePng({ base64: 'bad' }, {}));

  const damagedData = Buffer.from(png);
  damagedData[45] ^= 1;
  const oversizedChunk = Buffer.from(png);
  oversizedChunk.writeUInt32BE(0xffffffff, 33);
  const invalidChunks = [
    png.subarray(0, 33), // Header only: no IDAT or IEND.
    png.subarray(0, 40), // Truncated IDAT header.
    png.subarray(0, png.length - 1), // Truncated IEND CRC.
    png.subarray(0, png.length - 12), // Missing IEND.
    Buffer.concat([png.subarray(0, 33), png.subarray(-12)]), // Missing IDAT.
    Buffer.concat([png.subarray(0, 33), png.subarray(8)]), // Duplicate IHDR.
    Buffer.concat([png, Buffer.from([0])]), // Trailing data after IEND.
    damagedData,
    oversizedChunk,
  ];
  for (const invalid of invalidChunks) {
    assert.throws(() => decodePng({ ...result, base64: invalid.toString('base64') }, limits), /PNG/);
  }
});

test('directory scan is nonrecursive, deduplicated, and snapshot preserves input', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'bfly-export-test-'));
  try {
    const file = path.join(dir, 'sample.bfly');
    await fs.writeFile(file, 'synthetic');
    await fs.mkdir(path.join(dir, 'nested'));
    await fs.writeFile(path.join(dir, 'nested', 'ignore.bfly'), 'other');
    await fs.writeFile(path.join(dir, 'not-a-note.txt'), 'ignore');
    assert.deepEqual(await collectInputs([dir, file]), [await fs.realpath(file)]);
    const snapshot = await readSnapshot(file);
    assert.equal(snapshot.bytes.toString(), 'synthetic');
    assert.equal(snapshot.hash.length, 64);
    assert.equal(await fs.readFile(file, 'utf8'), 'synthetic');
  } finally { await fs.rm(dir, { recursive: true }); }
});

test('local server serves worker only, rejects traversal and write methods', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'bfly-export-http-'));
  let server;
  try {
    await fs.writeFile(path.join(dir, 'index.html'), 'worker');
    server = await serveWorker(dir);
    assert.equal(await (await fetch(server.origin)).text(), 'worker');
    assert.equal((await fetch(server.origin + '/..%5coutside')).status, process.platform === 'win32' ? 403 : 404);
    assert.equal((await fetch(server.origin, { method: 'POST' })).status, 405);
    assert.equal((await fetch(server.origin + '/missing')).status, 404);
  } finally { if (server) await server.close(); await fs.rm(dir, { recursive: true }); }
});

test('timeout rejects bounded operation and preserves completed value', async () => {
  assert.equal(await withTimeout(Promise.resolve(2), 50, 'load'), 2);
  await assert.rejects(withTimeout(new Promise(() => {}), 5, 'render'), /render timed out/);
});
