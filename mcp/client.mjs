import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { fileURLToPath } from 'node:url';

export async function connect() {
  const transport = new StdioClientTransport({ command: process.execPath, args: [fileURLToPath(new URL('./server.mjs', import.meta.url))], stderr: 'inherit' });
  const client = new Client({ name: 'dropdrive-integration-check', version: '1.0.0' });
  await client.connect(transport);
  return client;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const client = await connect();
  try {
    const response = process.argv[2] === 'list' ? await client.listTools()
      : await client.callTool({ name: process.argv[2] ?? 'dropdrive_health', arguments: JSON.parse(process.argv[3] ?? '{}') });
    console.log(JSON.stringify(response, null, 2));
  } finally { await client.close(); }
}
