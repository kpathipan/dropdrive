import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { randomUUID } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const run = promisify(execFile);
export const defaultRoot = path.join(os.homedir(), 'Library/Application Support/DropDrive/Automation/v1');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
export const id = () => randomUUID().toUpperCase();
export function uuid(value) {
  if (!/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value)) throw new Error('Invalid job/request UUID');
  return value.toUpperCase();
}

export async function readPrivate(file) {
  const handle = await fs.open(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  try {
    const stat = await handle.stat();
    if (!stat.isFile() || stat.nlink !== 1 || stat.uid !== process.getuid() || (stat.mode & 0o077) !== 0 || stat.size > 65536) throw new Error('Unsafe IPC file');
    return JSON.parse(await handle.readFile('utf8'));
  } finally { await handle.close(); }
}

export class Bridge {
  constructor(root = defaultRoot, { autoLaunch = true, timeout = 12000 } = {}) {
    this.root = root; this.autoLaunch = autoLaunch; this.timeout = timeout;
  }
  async checkDirectories() {
    for (const dir of [this.root, ...['requests', 'replies', 'jobs'].map(name => path.join(this.root, name))]) {
      const stat = await fs.lstat(dir);
      if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o077) !== 0) throw new Error('Unsafe IPC directory; run the local installer.');
    }
  }
  async ensureApp() {
    if (!this.autoLaunch) return;
    if (process.platform !== 'darwin') throw new Error('This local bridge currently requires DropDrive on macOS.');
    try {
      const endpoint = await readPrivate(path.join(this.root, 'endpoint.json'));
      const pid = Number(endpoint.pid);
      if (!Number.isSafeInteger(pid) || pid <= 0) throw new Error('Invalid app endpoint');
      process.kill(pid, 0);
      return;
    } catch {
      // Fixed executable and arguments; no link, path or name is executed as code.
      await run('/usr/bin/open', ['-g', '/Applications/DropDrive.app']);
    }
  }
  async request(fields) {
    await this.checkDirectories();
    await this.ensureApp();
    const command = { protocolVersion: 1, ...fields, id: uuid(fields.id ?? id()) };
    const request = path.join(this.root, 'requests', command.id + '.json');
    const reply = path.join(this.root, 'replies', command.id + '.json');
    const temporary = path.join(this.root, 'requests', '.' + id() + '.tmp');
    await fs.unlink(reply).catch(error => { if (error.code !== 'ENOENT') throw error; });
    const body = JSON.stringify(command);
    if (Buffer.byteLength(body) > 16384) throw new Error('Request too large');
    await fs.writeFile(temporary, body, { flag: 'wx', mode: 0o600 });
    try {
      try { await fs.link(temporary, request); }
      catch (error) {
        if (error.code !== 'EEXIST') throw error;
        if (JSON.stringify(await readPrivate(request)) !== body) throw new Error('Request ID already has different pending arguments');
      }
    } finally { await fs.unlink(temporary); }
    const deadline = Date.now() + this.timeout;
    while (Date.now() < deadline) {
      try {
        const result = await readPrivate(reply);
        if (result.id !== command.id) throw new Error('Reply ID mismatch');
        await fs.unlink(reply);
        return result;
      } catch (error) { if (error.code !== 'ENOENT') throw error; }
      await sleep(100);
    }
    // A timeout does not cancel an accepted download. Preserve the request ID.
    return { ok: false, error: { code: 'app_unavailable', message: 'No app response. The command may have been accepted; query/retry the SAME request ID, never invent a new one.' }, requestID: command.id };
  }
  async status(jobID) { return this.request({ action: 'status', jobID: uuid(jobID) }); }
  async wait(jobID, seconds = 20) {
    const deadline = Date.now() + Math.min(40, Math.max(0, seconds)) * 1000;
    let reply;
    do {
      reply = await this.status(jobID);
      if (!reply.ok || ['analyzed', 'completed', 'failed', 'duplicate', 'cancelled', 'interrupted', 'paused', 'awaiting_restore'].includes(reply.job?.state)) return reply;
      if (Date.now() >= deadline) return reply;
      await sleep(750);
    } while (true);
  }
}

/// Verify only a completed job's recorded output, never scan unrelated downloads.
export async function verifyOutput(job) {
  if (job.state !== 'completed' || !job.outputPath || !job.command.destination) return { verified: false, reason: 'job_not_completed' };
  const root = path.resolve(job.outputPath), parent = await fs.realpath(job.command.destination);
  const actual = await fs.realpath(root).catch(() => null);
  if (!actual) return { verified: false, reason: 'output_missing' };
  const relative = path.relative(parent, actual);
  if (relative === '' || relative.startsWith('..' + path.sep) || path.isAbsolute(relative)) return { verified: false, reason: 'output_not_isolated_under_destination' };
  let files = 0, bytes = 0, partials = 0, links = 0, visited = 0;
  const names = [];
  async function visit(file) {
    if (++visited > 10000) throw new Error('Output verification exceeds 10,000 entries; not certified complete.');
    const stat = await fs.lstat(file);
    if (stat.isSymbolicLink()) { links++; return; }
    if (stat.isDirectory()) {
      for (const name of await fs.readdir(file)) await visit(path.join(file, name));
    } else if (stat.isFile()) {
      if (/\.dddownload(?:\.|$)|\.part(?:\.|$)|\.ytdl$/.test(path.basename(file))) { partials++; return; }
      if (path.basename(file).startsWith('.')) return;
      files++; bytes += stat.size;
      if (names.length < 100) names.push(path.relative(parent, file));
    }
  }
  await visit(root);
  const expectedFiles = job.fileCount ?? null;
  return { verified: partials === 0 && links === 0 && files > 0 && (expectedFiles === null || files === expectedFiles),
    files, expectedFiles, bytes, partials, symbolicLinks: links, paths: names, outputPath: root,
    scope: 'local file presence and count; engine performs transfer/integrity checks' };
}
