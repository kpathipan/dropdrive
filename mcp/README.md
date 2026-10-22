# DropDrive local MCP (macOS)

This local integration uses the installed DropDrive app's existing download
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

RPC v1 actions: `ping`, `analyze`, `download`, `status`. Each command has `id`
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

Windows command-channel support is not implemented by this local Mac adapter.
The JSON protocol can be reused with OS-specific transport/permissions; do not
advertise Windows MCP parity until its handler and installed tests exist.

References: [Codex MCP configuration](https://learn.chatgpt.com/docs/extend/mcp?surface=cli),
[official MCP SDK](https://github.com/modelcontextprotocol/typescript-sdk/tree/v1.x).
