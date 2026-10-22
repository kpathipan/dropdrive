import { connect } from './client.mjs';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
const source = 'https://drive.google.com/drive/folders/12zxlvJtuHFV6awc3AINaNHnfvRttPv0i';
const client = await connect();
async function call(name, args = {}) {
  const response = await client.callTool({ name, arguments: args }, undefined, { timeout: 60000 });
  const result = response.structuredContent ?? JSON.parse(response.content.find(item => item.type === 'text').text);
  console.log(JSON.stringify({ tool: name, ...result }));
  return result;
}
async function finish(jobID) {
  for (let i = 0; i < 6; i++) {
    const response = await call('dropdrive_status', { job_id: jobID, wait_seconds: 20 });
    assert.equal(response.ok, true);
    if (!['analyzing', 'downloading', 'queued', 'waiting'].includes(response.job.state)) return response;
  }
  throw new Error('Job did not finish within integration-test deadline; files and queue are left untouched.');
}
try {
  const listed = await client.listTools(); assert.equal(listed.tools.length, 5);
  assert.equal((await call('dropdrive_health')).ok, true);
  const analysis = await call('dropdrive_analyze', { url: source, request_id: randomUUID() });
  assert.equal(analysis.ok, true);
  const analyzed = await finish(analysis.job.command.id); assert.equal(analyzed.job.state, 'analyzed');
  assert.ok(analyzed.job.fileCount > 0 && analyzed.job.fileCount <= 10, 'Keep this live test small');
  if (analyzed.job.totalBytes != null) assert.ok(analyzed.job.totalBytes < 10_000_000);
  const requestID = randomUUID(), destination = path.join(os.homedir(), 'Downloads');
  const args = { url: source, destination, name: 'DropDrive MCP Test ' + requestID.slice(0, 8), request_id: requestID, allow_duplicate: true };
  const started = await call('dropdrive_download', args); assert.equal(started.ok, true);
  const downloaded = await finish(requestID); assert.equal(downloaded.job.state, 'completed');
  const verified = await call('dropdrive_verify', { job_id: requestID }); assert.equal(verified.verification.verified, true);
  const replay = await call('dropdrive_download', args);
  assert.equal(replay.job.state, 'completed'); assert.equal(replay.job.outputPath, downloaded.job.outputPath);
  const conflict = await call('dropdrive_download', { ...args, name: 'different-name' });
  assert.equal(conflict.ok, false); assert.equal(conflict.error.code, 'id_conflict');
  const duplicate = await call('dropdrive_download', { ...args, request_id: randomUUID(), allow_duplicate: false });
  const duplicateResult = await finish(duplicate.job.command.id); assert.equal(duplicateResult.job.state, 'duplicate');
  const unknown = await call('dropdrive_status', { job_id: randomUUID() }); assert.equal(unknown.error.code, 'unknown_job');
  const invalidFormat = await call('dropdrive_download', { ...args, request_id: randomUUID(), as_audio: true });
  const failed = await finish(invalidFormat.job.command.id);
  assert.equal(failed.job.state, 'failed'); assert.equal(failed.job.errorCode, 'invalid_format');
  console.log('PASS real MCP -> installed DropDrive -> Google Drive -> files in Downloads; verification and idempotency. Test files preserved: ' + downloaded.job.outputPath);
} finally { await client.close(); }
