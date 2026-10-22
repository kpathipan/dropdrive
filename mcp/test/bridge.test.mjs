import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { Bridge, id, uuid, readPrivate, verifyOutput } from '../bridge.mjs';

async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'dd-mcp-test-'));
  await fs.chmod(root, 0o700);
  for (const name of ['requests', 'replies', 'jobs']) await fs.mkdir(path.join(root, name), { mode: 0o700 });
  t.after(() => fs.rm(root, { recursive: true }));
  return root;
}
test('UUID paths reject traversal', () => {
  assert.throws(() => uuid('../bad')); assert.equal(uuid(id().toLowerCase()).length, 36);
});
test('private IPC rejects symlink and public file', async t => {
  const root = await fixture(t), file = path.join(root, 'private.json');
  await fs.writeFile(file, '{}', { mode: 0o600 });
  await fs.symlink(file, path.join(root, 'link'));
  await assert.rejects(readPrivate(path.join(root, 'link')));
  await fs.chmod(file, 0o644); await assert.rejects(readPrivate(file));
});
test('IPC round trip correlates IDs and removes only its own response', async t => {
  const root = await fixture(t), requestID = id();
  const bridge = new Bridge(root, { autoLaunch: false, timeout: 2000 });
  const work = bridge.request({ id: requestID, action: 'ping' });
  const requestFile = path.join(root, 'requests', requestID + '.json');
  for (let i = 0; i < 100; i++) {
    try { await readPrivate(requestFile); break; } catch { await new Promise(r => setTimeout(r, 10)); }
  }
  const command = await readPrivate(requestFile);
  assert.equal(command.id, requestID);
  assert.equal(command.protocolVersion, 1);
  await fs.writeFile(path.join(root, 'replies', requestID + '.json'), JSON.stringify({ id: requestID, ok: true }), { mode: 0o600 });
  assert.equal((await work).ok, true);
  assert.equal((await fs.readdir(path.join(root, 'replies'))).length, 0);
});
test('timeout preserves idempotency ID; does not claim failure/cancellation of download', async t => {
  const root = await fixture(t), requestID = id();
  const reply = await new Bridge(root, { autoLaunch: false, timeout: 20 }).request({ id: requestID, action: 'download' });
  assert.equal(reply.requestID, requestID); assert.equal(reply.error.code, 'app_unavailable');
  assert.equal((await readPrivate(path.join(root, 'requests', requestID + '.json'))).id, requestID);
});
test('bounded status wait stops when the user must restore or has cancelled', async () => {
  const bridge = new Bridge('/unused', { autoLaunch: false });
  for (const state of ['awaiting_restore', 'paused', 'cancelled']) {
    let calls = 0;
    bridge.status = async () => { calls++; return { ok: true, job: { state } }; };
    assert.equal((await bridge.wait(id(), 40)).job.state, state);
    assert.equal(calls, 1);
  }
});
test('verification counts real files and rejects partial, missing, external and non-completed outputs', async t => {
  const root = await fixture(t), output = path.join(root, 'ทดสอบ'); await fs.mkdir(output);
  await fs.writeFile(path.join(output, 'a.txt'), 'a'); await fs.writeFile(path.join(output, 'b.txt'), 'bb');
  const job = { state: 'completed', command: { destination: root }, outputPath: output, fileCount: 2 };
  assert.deepEqual((await verifyOutput(job)).files, 2); assert.equal((await verifyOutput(job)).verified, true);
  await fs.writeFile(path.join(output, 'c.dddownload'), 'partial'); assert.equal((await verifyOutput(job)).verified, false);
  await fs.unlink(path.join(output, 'c.dddownload'));
  assert.equal((await verifyOutput({ ...job, fileCount: 3 })).verified, false);
  assert.equal((await verifyOutput({ ...job, state: 'downloading' })).verified, false);
  assert.equal((await verifyOutput({ ...job, outputPath: path.join(root, 'missing') })).reason, 'output_missing');
  assert.equal((await verifyOutput({ ...job, outputPath: root })).verified, false);
  await fs.symlink('/tmp', path.join(output, 'outside')); assert.equal((await verifyOutput(job)).verified, false);
});
