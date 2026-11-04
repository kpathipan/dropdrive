# DropDrive local MCP (macOS)

This local integration uses the installed DropDrive app's download and upload
engine and Google account manager. No OAuth sessions, cookies, tokens or
passwords are read by the MCP process. It does not publish a release.

```text
Codex --stdio MCP--> Node adapter --private JSON IPC--> DropDrive queue
                       |                                  |
                       +-- verify recorded output <--------+-- Drive/video engine
```

## Install

Requires Node 20+ and an automation-enabled Mac app built from this source.
From `mcp/`, run `npm ci`, then `node install.mjs`. The installer adds only the
`dropdrive` server using the supported `codex mcp add` command. Existing server
configuration is preserved. Codex desktop/CLI share this user-level configuration.
New tools may need a desktop tool refresh/restart before an existing chat sees
them; registration or a standalone MCP client test alone is not proof of live
tool discovery in that chat.

The app must be restarted once after the installer enables its command channel.
Do not replace/restart an app with active downloads. Keep the stable signing
identity and app identifier so existing Keychain access continues.

## Tools

| Tool | Effect |
| --- | --- |
| `dropdrive_health` | Check channel/app version; start app in background if absent |
| `dropdrive_analyze` | Analyze a source; return job ID, then query status |
| `dropdrive_download` | Queue an explicit source/destination/name/MP3 choice |
| `dropdrive_status` | Read job/progress; optional wait up to 40 seconds |
| `dropdrive_verify` | Check completed output's real files/count and partial files |
| `dropdrive_upload` | Upload a regular local file to an explicit Drive folder |
| `dropdrive_upload_folders` | Resolve a folder link/ID or browse permitted folders |
| `dropdrive_upload_create_folder` | Explicitly create a named destination folder |
| `dropdrive_upload_retry` | Resume the same job; optionally resolve a name conflict |
| `dropdrive_upload_cancel` | Stop upload/retry while preserving local/remote files |
| `dropdrive_upload_verify` | Re-fetch Drive metadata and verify ID/name/parent/size/MD5 |

## Uploads (Mac)

One-time setup: open **Uploads → Enable uploads**, select the intended Google
account and consent to `drive.file`. Existing Google download permissions are
retained with incremental authorization; enabling uploads requests no full
`drive` write scope and no new `drive.readonly` scope. See
[OAuth and destination setup](../docs/uploads-macos.md).

The app's Uploads pane has a native file picker, editable remote filenames, file
drop area, Drive folder link/ID entry, folder browser, named destination preview,
folder creation, progress and retry/cancel. Dropping files on the menu-bar icon
also opens Uploads with those files selected. Folder drops retain the existing
download-destination behavior. The UI and MCP share `UploadCoordinator` and
`DriveUploadEngine`; neither creates an independent upload implementation.

Example arguments to `dropdrive_upload`:

```json
{
  "source_path": "/Users/me/Movies/final.mov",
  "name": "Final delivery.mov",
  "destination_folder": "https://drive.google.com/drive/folders/FOLDER_ID",
  "account_id": "OPTIONAL_GOOGLE_SUBJECT_ID",
  "request_id": "3F44AF38-1D80-4FCD-B0E4-8F36B8088036"
}
```

`source_path` is any absolute regular-file path explicitly provided by the user
and readable by DropDrive under macOS permissions. It is **not restricted to
Submit** or another directory. Symlinks in the file or ancestor path, relative
components, directories, devices and FIFOs are rejected. Use a canonical real
path (for example `/private/var/...` instead of macOS's `/var` symlink). Files
are read through a retained no-follow descriptor; editing/replacing the source
prevents an unsafe retry. UI selections retain security-scoped bookmarks.

`destination_folder` accepts a folder ID/link or `root`. The app pins one Google
account per accepted job; changing the default account never switches a running
or retried upload to another account. Resolve a folder with
`dropdrive_upload_folders` to inspect its name, ancestor path, Shared Drive ID
and `canUpload` before starting. A supplied ID does not bypass Google access
controls. Shared Drive operations use `supportsAllDrives`; listings also use
`includeItemsFromAllDrives` and drive-specific collision checks.

Poll **`dropdrive_status`** with the returned job ID. Upload details appear in
`job.upload` (`bytesUploaded`, `totalBytes`, `retryCount`, `nextRetryAt`,
`remoteFileID`, `remoteURL`, `verified`). States include `queued`, `hashing`,
`preparing`, `uploading`, `retrying`, `verifying`, `completed`, `failed`,
`cancelling`, `cancelled`, and `interrupted`. Call **`dropdrive_upload_verify`**
for independent remote verification, rather than the local-download verifier.
Transferred bytes alone do not establish completion.

Uploads stream in 8 MiB chunks (a 256 KiB multiple), with a streamed source MD5.
The chunk size bounds memory; it is **not a file-size cap**. There is no 100 MB
limit. Drive storage, service quotas, organization policy, filesystem limits and
network availability still apply. Retry uses server-acknowledged offsets and
bounded exponential backoff. Restarted jobs require explicit retry and retain
their original generated Drive file IDs. Identical request replay only returns
the existing job; use `dropdrive_upload_retry` to resume it.

An existing destination name returns `name_conflict`; use
`dropdrive_upload_retry({"job_id":"...", "new_name":"..."})` before sending
any bytes, or cancel. Uploads never silently overwrite, auto-suffix or update an
existing Drive file. Google permits duplicate names and provides no atomic
unique-name transaction against other apps; a concurrent external creation may
still create two separate same-named files, never an overwrite.

Tokens remain in the app's existing Keychain sessions. Resumable URLs are kept
only in app-private `~/Library/Application Support/DropDrive/Uploads/v1/`
checkpoints, mode 0700/0600, outside the Automation spool. Checkpoints atomically
persist and flush the generated ID before a create request. Public IPC jobs,
MCP results and logs contain neither OAuth credentials nor resumable URLs.
Cancellation preserves local files and already committed Drive files; retry
does not allocate a second file ID. Checkpoints/IDs are not automatically
forgotten when the bounded 1,000-job ledger fills. Freeing disk/storage or
manual maintenance may be needed; do not delete checkpoints for uncertain jobs.

Download arguments: `url`, absolute existing `destination`, UUID `request_id`,
optional `name`, `as_audio`, `allow_duplicate`. Names must be single path
components. Downloads use a captured per-job destination, not the UI selection.
The existing queue's pause/recovery decisions are never overridden.

Always keep `request_id` and retry the **same ID** after timeout. An identical
request returns the same job; changed arguments with that ID produce
`id_conflict`. Already queued sources are rejected, and completed sources require
explicit `allow_duplicate=true` to download again. Files remain subject to the
app's no-overwrite rules.

`completed` is the app's successful engine state, not merely 100% transferred.
Call `dropdrive_verify` before claiming all files are present. Verification is a
bounded scan of that job's recorded output only; it does not certify unrelated
files, follow symlinks, or claim cryptographic integrity beyond the app engine.
Media sidecars/collections with unknown output counts may need inspection; a
count mismatch is not silently accepted. A source-named destination reused as
the output root is intentionally not certified by the adapter.

## IPC and security

The opt-in channel lives under
`~/Library/Application Support/DropDrive/Automation/v1/` with mode 0700 and
0600 request/reply/job files. It exposes no TCP port, HTTP endpoint, shell command
or URL-scheme permission to set arbitrary destinations. The trust boundary is
the current OS user; this is not isolation from malicious code running as that
same user. File ownership, permissions, symlinks, hard links, request sizes,
UUID filenames, protocol versions, HTTPS hosts and destination/name inputs are
checked. Atomic acceptance is journaled before dispatch. Concurrency is bounded
to four analyses and a 100-item application queue.

RPC v1 actions: `ping`, `analyze`, `download`, `status`, `upload`,
`upload_folders`, `upload_create_folder`, `upload_cancel`, `upload_retry`,
`upload_verify`. Each command has `id`
(UUID) and `protocolVersion: 1`; `status` also has `jobID`. Replies correlate the
same `id`, with `ok`, structured errors, and optional job/progress. Job records
exclude Google credentials and full provider metadata. The 1,000-job ledger is
bounded and fails closed when full; IDs are not silently forgotten/reused.

App crashes never cause automatic re-submission. Queue-backed jobs are recovered
for status; unfinished jobs without a queue checkpoint become `interrupted`.
The user retains control over resuming saved jobs. Download files are never
deleted by MCP timeout, verification, uninstall or test failure.
Saved jobs report `awaiting_restore` until the user decides in DropDrive;
removing/discarding an unfinished queue item reports `cancelled`.

Disable: `codex mcp remove dropdrive`, remove only the channel's `enabled` marker,
then restart DropDrive when idle. Retain job records and downloads if needed.
Do not recursively delete the DropDrive application-support directory.

## Tests

`npm test` checks private IPC boundaries, ID validation, timeout semantics and
file verification. `node client.mjs list` uses an actual SDK MCP client/stdio
handshake. `node e2e.mjs` uses a small public Drive fixture, names a unique output
under Downloads, checks analyze/download/status/verify, replays the same request,
rejects conflicting arguments and checks duplicate protection. Test downloads
are preserved and their path is printed. `bash scripts/test-regressions.sh`
also covers Swift command validation and journal serialization.

`bash scripts/test-uploads.sh` uses the production engine with an offline
URLProtocol fixture: lost chunk replies, same-ID resume, checkpoint restore,
Shared Drive flags, source mutation, symlink escapes, unsafe session hosts,
checksum mismatch and credential-free IPC serialization. It reads no real
Google credentials. `node mcp/upload-e2e.mjs --large` performs real Drive uploads
in an explicitly named test folder, using durable test IDs in ignored `dist/`.
It preserves test files and checks replay, collision/rename, independent metadata
verification and a 17 MiB multi-chunk upload. See the dated verification record
in [Mac upload setup](../docs/uploads-macos.md) for actual coverage and limits.

Windows command-channel support is not implemented by this local Mac adapter.
The JSON protocol can be reused with OS-specific transport/permissions; do not
advertise Windows MCP parity until its handler and installed tests exist.

References: [Codex MCP configuration](https://learn.chatgpt.com/docs/extend/mcp?surface=cli),
[official MCP SDK](https://github.com/modelcontextprotocol/typescript-sdk/tree/v1.x).
