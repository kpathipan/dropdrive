import { connect } from './client.mjs';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

// Durable test IDs: rerunning this script reuses the same cloud jobs, rather
// than scattering more folders/files after an interrupted integration test.
const repository = fileURLToPath(new URL('../', import.meta.url));
const statePath = path.join(repository, 'dist/upload-live-test.json');
await fs.mkdir(path.dirname(statePath), { recursive: true });
let state;
try { state = JSON.parse(await fs.readFile(statePath, 'utf8')); }
catch (error) {
  if (error.code !== 'ENOENT') throw error;
  state = { folderID: randomUUID(), fileID: randomUUID(), conflictID: randomUUID(), largeID: randomUUID() };
  await fs.writeFile(statePath, JSON.stringify(state, null, 2), { flag: 'wx', mode: 0o600 });
}
const client = await connect();
async function call(name, args = {}) {
  const response = await client.callTool({ name, arguments: args }, undefined, { timeout: 60000 });
  const result = response.structuredContent ?? JSON.parse(response.content.find(item => item.type === 'text').text);
  console.log(JSON.stringify({ tool: name, ...result })); return result;
}
async function finish(jobID) {
  for (let i = 0; i < 20; i++) {
    const result = await call('dropdrive_status', { job_id: jobID, wait_seconds: 10 });
    assert.equal(result.ok, true);
    if (['completed', 'failed', 'cancelled', 'interrupted'].includes(result.job.state)) return result.job;
  }
  throw new Error('Test deadline reached; existing cloud files and original request IDs are preserved.');
}
try {
  const listed = await client.listTools(); assert.ok(listed.tools.some(tool => tool.name === 'dropdrive_upload'));
  assert.equal((await call('dropdrive_health')).ok, true);
  const destination = await call('dropdrive_upload_create_folder', { name: 'DropDrive Upload Test ' + state.folderID.slice(0, 8), request_id: state.folderID });
  assert.equal(destination.ok, true);
  const created = await finish(state.folderID); assert.equal(created.state, 'completed');
  const folder = created.upload.folder;
  const resolved = await call('dropdrive_upload_folders', { folder: 'https://drive.google.com/drive/folders/' + folder.id });
  assert.equal(resolved.folder.id, folder.id); assert.equal(resolved.folder.canUpload, true);
  const args = { source_path: path.join(repository, 'mcp/test-fixtures/upload-proof.txt'), destination_folder: folder.id,
    name: 'ทดสอบ MCP.txt', request_id: state.fileID };
  assert.equal((await call('dropdrive_upload', args)).ok, true);
  const completed = await finish(state.fileID); assert.equal(completed.state, 'completed'); assert.equal(completed.upload.verified, true);
  const verified = await call('dropdrive_upload_verify', { job_id: state.fileID });
  assert.equal(verified.ok, true); assert.equal(verified.job.upload.verified, true);
  const replay = await call('dropdrive_upload', args);
  assert.equal(replay.job.upload.remoteFileID, completed.upload.remoteFileID);
  assert.equal((await call('dropdrive_upload', { ...args, name: 'different.txt' })).error.code, 'id_conflict');
  const conflicting = await call('dropdrive_upload', { ...args, request_id: state.conflictID });
  assert.equal(conflicting.ok, true);
  let conflict = await finish(state.conflictID);
  // A rerun may already have completed the explicit rename test.
  if (conflict.state !== 'completed') {
    assert.equal(conflict.errorCode, 'name_conflict');
    assert.equal((await call('dropdrive_upload_retry', { job_id: state.conflictID, new_name: 'เปลี่ยนชื่อแล้ว.txt' })).ok, true);
    conflict = await finish(state.conflictID); assert.equal(conflict.state, 'completed');
  }
  console.log('PASS real upload, independent size/MD5/parent verification, replay identity, name conflict and explicit rename; files preserved at https://drive.google.com/drive/folders/' + folder.id);
  if (process.argv.includes('--large')) {
    const largePath = path.join(repository, 'dist/upload-multichunk-test.bin');
    try { await fs.access(largePath); }
    catch {
      const file = await fs.open(largePath, 'wx', 0o600);
      try { const block = Buffer.alloc(1048576, 0x57); for (let i = 0; i < 17; i++) await file.write(block); }
      finally { await file.close(); }
    }
    assert.equal((await call('dropdrive_upload', { source_path: largePath, destination_folder: folder.id, name: 'multichunk.bin', request_id: state.largeID })).ok, true);
    const large = await finish(state.largeID); assert.equal(large.state, 'completed'); assert.equal(large.upload.totalBytes, 17 * 1048576);
    assert.equal((await call('dropdrive_upload_verify', { job_id: state.largeID })).job.upload.verified, true);
    console.log('PASS real multi-chunk resumable upload (17 MiB), remote size/MD5 verified. Test source and remote file preserved.');
  }
} finally { await client.close(); }
