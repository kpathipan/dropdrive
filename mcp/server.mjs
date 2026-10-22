import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { Bridge, id, uuid, verifyOutput } from './bridge.mjs';

const bridge = new Bridge();
const server = new McpServer({ name: 'dropdrive', version: '1.0.0' });
const result = value => ({ content: [{ type: 'text', text: JSON.stringify(value) }], structuredContent: value, isError: value.ok === false });
const guard = callback => async args => {
  try { return result(await callback(args)); }
  catch (error) { return result({ ok: false, error: { code: 'local_bridge_error', message: error.message } }); }
};
const readOnly = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };
server.registerTool('dropdrive_health', {
  description: 'Check the installed local DropDrive command channel. Starts DropDrive in the background if it is not running. Never reads Google credentials.',
  inputSchema: {}, annotations: { ...readOnly, readOnlyHint: false }
}, guard(() => bridge.request({ action: 'ping' })));

server.registerTool('dropdrive_analyze', {
  description: 'Analyze a supported HTTPS Drive/video link using DropDrive and its existing accounts, without downloading. Returns a job ID; use dropdrive_status to await metadata/errors. No Google tokens leave the app.',
  inputSchema: { url: z.string().url().max(8192), request_id: z.string().uuid().optional() },
  annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: true }
}, guard(args => bridge.request({ action: 'analyze', id: args.request_id ? uuid(args.request_id) : id(), url: args.url })));

server.registerTool('dropdrive_download', {
  description: 'Start a real download through DropDrive. Provide an existing absolute destination directory and optional single filename/folder name. Leaves UI selections and paused queues unchanged. Keep request_id for retries: same ID never enqueues twice. Duplicate sources require explicit allow_duplicate=true. Returns a job ID, NOT proof of download completion; call dropdrive_status then dropdrive_verify. Google OAuth remains inside DropDrive.',
  inputSchema: { url: z.string().url().max(8192), destination: z.string().min(1).max(4096), name: z.string().min(1).max(200).optional(),
    request_id: z.string().uuid(), as_audio: z.boolean().default(false), allow_duplicate: z.boolean().default(false) },
  annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: true }
}, guard(args => bridge.request({ action: 'download', id: uuid(args.request_id), url: args.url, destination: args.destination,
  ...(args.name === undefined ? {} : { name: args.name }), asAudio: args.as_audio, allowDuplicate: args.allow_duplicate })));

server.registerTool('dropdrive_status', {
  description: 'Read a previously submitted job: analyzing, queued, downloading, waiting, completed, failed, duplicate, interrupted, cancelled, paused or awaiting_restore. awaiting_restore requires the user to decide in DropDrive. Optional bounded wait avoids rapid polling. Queued/100% bytes is not completed.',
  inputSchema: { job_id: z.string().uuid(), wait_seconds: z.number().int().min(0).max(40).default(0) }, annotations: readOnly
}, guard(args => bridge.wait(args.job_id, args.wait_seconds)));

server.registerTool('dropdrive_verify', {
  description: 'After DropDrive reports completed, verify its recorded output under the requested destination: actual files/count/bytes and no partial files. Does not scan unrelated folders or change files. Analyzed/duplicate jobs are not verified as new downloads.',
  inputSchema: { job_id: z.string().uuid() }, annotations: readOnly
}, guard(async args => {
  const reply = await bridge.status(args.job_id);
  if (!reply.ok) return reply;
  return { ...reply, verification: await verifyOutput(reply.job) };
}));

await server.connect(new StdioServerTransport());
