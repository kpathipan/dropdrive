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
const uploadWrite = { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: true };
server.registerTool('dropdrive_upload', {
  description: 'Upload a local regular file to Google Drive using the Mac app. source_path can be any absolute readable file path specified by the user; no Submit directory restriction. destination_folder accepts a Drive folder ID or link, including Shared Drives. Optional name sets the remote filename. Enable drive.file once in DropDrive first. No per-file UI confirmation. Retain request_id: retries return the same job and never create a second Drive file. Poll dropdrive_status, then dropdrive_upload_verify. Tokens and resumable session URLs never leave the app. Name conflicts require explicit rename via dropdrive_upload_retry or cancellation; no overwrite.',
  inputSchema: { source_path: z.string().min(1).max(16384), destination_folder: z.string().min(1).max(8192),
    name: z.string().min(1).max(255).optional(), account_id: z.string().min(1).max(256).optional(), request_id: z.string().uuid() },
  annotations: uploadWrite
}, guard(args => bridge.request({ action: 'upload', id: uuid(args.request_id), sourcePath: args.source_path,
  driveFolder: args.destination_folder, ...(args.name === undefined ? {} : { name: args.name }),
  ...(args.account_id === undefined ? {} : { accountID: args.account_id }) })));
server.registerTool('dropdrive_upload_folders', {
  description: 'Resolve a Drive folder link/ID and show its name, ancestor path, Shared Drive ID and write capability, or list available folders with pagination. Uses the account already authorized in DropDrive. A folder must be accessible to the app/account; this tool never expands OAuth permissions.',
  inputSchema: { folder: z.string().min(1).max(8192).optional(), account_id: z.string().max(256).optional(), page_token: z.string().max(4096).optional() },
  annotations: { ...readOnly, openWorldHint: true }
}, guard(args => bridge.request({ action: 'upload_folders', ...(args.folder ? { driveFolder: args.folder } : {}),
  ...(args.account_id ? { accountID: args.account_id } : {}), ...(args.page_token ? { pageToken: args.page_token } : {}) })));
server.registerTool('dropdrive_upload_create_folder', {
  description: 'Create an explicitly requested Drive destination folder using drive.file, without overwriting existing content. parent_folder defaults to My Drive root. Retain request_id for safe retries; query dropdrive_status for the resulting folder. This creates a real cloud folder.',
  inputSchema: { name: z.string().min(1).max(255), parent_folder: z.string().max(8192).default('root'),
    account_id: z.string().max(256).optional(), request_id: z.string().uuid() }, annotations: uploadWrite
}, guard(args => bridge.request({ action: 'upload_create_folder', id: uuid(args.request_id), name: args.name,
  driveFolder: args.parent_folder, ...(args.account_id ? { accountID: args.account_id } : {}) })));
server.registerTool('dropdrive_upload_retry', {
  description: 'Resume a failed, interrupted or cancelled upload using its durable Drive file ID and confirmed bytes. new_name explicitly resolves a name conflict before any bytes are uploaded. A started upload cannot be renamed. Does not log in, open Chrome or create a second file for this job.',
  inputSchema: { job_id: z.string().uuid(), new_name: z.string().min(1).max(255).optional() }, annotations: uploadWrite
}, guard(args => bridge.request({ action: 'upload_retry', jobID: uuid(args.job_id), ...(args.new_name === undefined ? {} : { name: args.new_name }) })));
server.registerTool('dropdrive_upload_cancel', {
  description: 'Stop this upload and its automatic retry. Does not delete local files or any file already committed on Drive. If the final response was lost, the app verifies completion before declaring cancellation. Retrying the same job keeps its original Drive file ID.',
  inputSchema: { job_id: z.string().uuid() }, annotations: uploadWrite
}, guard(args => bridge.request({ action: 'upload_cancel', jobID: uuid(args.job_id) })));
server.registerTool('dropdrive_upload_verify', {
  description: 'Independently re-fetch the uploaded file from Drive and check exact ID, filename, destination parent, size and MD5 against the original source checkpoint. Returns job.upload.verified only on a match. No tokens, session URLs or file contents cross MCP.',
  inputSchema: { job_id: z.string().uuid() }, annotations: { ...readOnly, openWorldHint: true }
}, guard(args => bridge.request({ action: 'upload_verify', jobID: uuid(args.job_id) })));
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
  description: 'Read a download or upload job. Upload states include hashing, preparing, uploading, retrying, verifying and cancelling; job.upload contains bytesUploaded/totalBytes/remoteFileID/verified, never session URLs or tokens. Other states include queued, completed, failed, interrupted and cancelled. awaiting_restore requires user action in DropDrive. Optional bounded wait avoids rapid polling. Transferred bytes alone are not proof of completion.',
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
