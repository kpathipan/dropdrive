import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { defaultRoot } from './bridge.mjs';

if (process.platform !== 'darwin') throw new Error('Install on macOS with the automation-enabled DropDrive build.');
for (const directory of [defaultRoot, ...['requests', 'replies', 'jobs'].map(name => path.join(defaultRoot, name))]) {
  await fs.mkdir(directory, { recursive: true, mode: 0o700 });
  const stat = await fs.lstat(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o077) !== 0) throw new Error('Refusing unsafe automation directory: ' + directory);
}
const enabled = path.join(defaultRoot, 'enabled');
await fs.writeFile(enabled, 'Local same-user automation enabled by the owner.\n', { flag: 'wx', mode: 0o600 })
  .catch(error => { if (error.code !== 'EEXIST') throw error; });
const server = fileURLToPath(new URL('./server.mjs', import.meta.url));
const run = promisify(execFile);
// Homebrew's versioned Cellar path disappears after upgrades; prefer its stable
// symlink only when it points to the same trusted Node used by this installer.
let runtime = process.execPath;
for (const candidate of ['/opt/homebrew/bin/node', '/usr/local/bin/node']) {
  if (await fs.realpath(candidate).catch(() => null) === await fs.realpath(process.execPath)) {
    runtime = candidate; break;
  }
}
// Supported CLI writes only this named MCP configuration, retaining other servers.
await run('codex', ['mcp', 'add', 'dropdrive', '--', runtime, server]);
console.log('Installed local DropDrive MCP. The desktop client may require a tool refresh/restart to expose newly configured tools.');
