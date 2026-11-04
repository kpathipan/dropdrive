# Mac uploads: OAuth, destination selection and verification

This change is local Mac development. It does not change Windows, release
versions, published installers, tags or release state.

## One-time account setup

1. Use the existing macOS OAuth client configured by `GIDClientID` and
   `REVERSED_CLIENT_ID`; enable the Google Drive API in the same Cloud project.
2. Include `https://www.googleapis.com/auth/drive.file` in the OAuth consent
   configuration. For an app in Testing, the selected account must be an allowed
   test user. A Workspace administrator may restrict this consent.
3. In DropDrive's **Uploads / อัปโหลด** tab choose the Google account, then
   **Enable uploads / เปิดสิทธิ์อัปโหลด**. Complete Google's native authorization
   flow once. Passwords are entered only into Google's own flow.
4. The request adds only `drive.file` plus OpenID/profile/email; it uses
   `include_granted_scopes=true` to retain earlier grants. Existing download
   accounts may already have `drive.readonly`. Upload enablement does not request
   that scope anew and never requests full `https://www.googleapis.com/auth/drive`.
5. Select a permitted destination in the native folder browser, paste its link
   or ID, or explicitly create a new folder. Confirm the displayed account,
   folder name and ancestor path before Upload. MCP can resolve the same folder
   and upload without another confirmation for each file.

The native browser uses Drive API metadata available under that account's
existing grants. A drive.file-only account can see only items authorized for
this app (including app-created destinations); pasting a folder ID does not
grant access. Existing readonly download grants can provide folder metadata,
but do not grant broad write access. If Google refuses an existing folder,
choose an accessible account/destination or create an app-owned destination.
Granting per-file access to arbitrary previously unauthorized items may require
Google Picker on the provider side; this implementation does not silently
substitute full-Drive write permission or pretend that typing an ID grants it.

This app uses its native folder browser; it does not control Chrome, send Google
tokens to MCP, or require a hosted picker/backend for the tested flow. If a
future account/policy requires additional grants, explain the concrete failure
before changing scopes. Do not widen scopes merely to hide a 403/404.

## Local file and destination controls

- Choose files or drop them in Uploads; dropping regular files on the menu-bar
  icon also selects them. Local folder drops keep their download-destination
  meaning. Remote names are editable before submission.
- Any readable regular file can be uploaded; there is no Submit directory
  allow-list. All symlink path components are refused, including system aliases
  such as `/var` and `/tmp`; supply their real `/private/...` paths for MCP.
- Source size/inode/device/mtime and streamed MD5 bind a retry to the original
  content. Keep the source in place and unchanged until verified completion.
- `root`, folder IDs and `https://drive.google.com/.../folders/ID` are accepted.
  The selected folder must exist, not be trashed, and allow `canAddChildren`.
  Ancestor names are shown when Google permits reading those ancestors.
- Shared Drives use their real parent and Drive IDs with all-drives API flags.
  The account needs an appropriate role and must satisfy organization policies.
  Some Shared Drives forbid external users, particular types or additional items.
- Collisions stop before sending content. Rename explicitly or cancel. Drive
  has no global unique-filename lock against uploads from another application.
- Active uploads block an app update/replacement and count as active transfers
  in the quit confirmation. Restarted uploads stay interrupted until Retry.

## Reliability and privacy

The UI and MCP use `UploadCoordinator` → `DriveUploadEngine`. Accepted commands
and server-generated IDs are written atomically and flushed to app-private
0700/0600 checkpoints before create/upload side effects. The source is streamed,
not copied; memory is bounded by 8 MiB chunks and small hashing buffers. One
upload runs at a time; downloads keep their existing engine/queue.

Session URLs stay in app-private checkpoints outside the MCP spool. Credentials
stay in the existing per-account Keychain. HTTP redirects are refused; resumable
requests accept only Google's HTTPS upload endpoint. Error messages never
forward URLSession errors or raw provider responses that might contain secrets.
Cancel stops the task and automatic backoff. A final response lost during cancel
is checked against Drive before calling the job cancelled. Local files and
already committed cloud files are preserved. Retry retains the generated ID.

Drive metadata must match ID, remote name, parent, byte count and original MD5
before a file is marked verified. This path uploads binary files without Google
Docs conversion, which preserves checksum/size verification and generated-ID
idempotency. Retrying a cancelled upload does not delete the earlier partial
session; Google expires abandoned sessions. Never purge an uncertain checkpoint
and submit a fresh ID just because a response timed out.

## Real Google limits

DropDrive sets no arbitrary maximum upload size. Google currently documents a
maximum file upload size of 5,120 GB; available account/Shared Drive storage,
upload quotas, API rate limits and administrator policies may impose lower
limits. Google Workspace also enforces a 750 GB/day upload/copy quota across
My Drive and Shared Drives, with its documented first-large-file exceptions.
A resumable session expires after about one week. The app probes the
server's accepted offset, retries transient failures with exponential backoff,
and reports quota/permission failures; it never buys storage, changes sharing
or requests broader permissions automatically.

References: [Upload API and resumable behavior](https://developers.google.com/workspace/drive/api/guides/manage-uploads),
[files.create size and scopes](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/create),
[Drive scope guidance](https://developers.google.com/workspace/drive/api/guides/api-specific-auth),
[Shared Drive support](https://developers.google.com/workspace/drive/api/guides/enable-shareddrives),
[Drive quota limits](https://developers.google.com/workspace/drive/api/guides/limits).

## Verified locally, 2026-10-26

- Debug and Release Mac builds; installation with the existing stable
  certificate, keeping accounts/history and one installed app.
- Native Google consent completed once by the user. No token/session capability
  was read by the MCP adapter or printed during tests.
- Real MCP: 149-byte UTF-8 text, empty file and 17 MiB multi-chunk upload; exact
  remote size and MD5 passed. Identical request replay retained its Drive ID;
  conflicting arguments were rejected; a filename collision required explicit
  rename. Cancelling during upload and retrying retained the same ID and passed
  remote verification.
- Real app UI: chose a source outside Submit, renamed it, selected a Drive link,
  saw the full destination path, pressed Upload, and observed verified success.
  System file-picker close/reopen behavior preserved the review state.
- Offline engine fixtures: Shared Drive flags, lost ACK recovery, interruption
  and checkpoint serialization, changed source, symlinks, unsafe upload hosts,
  checksum failure and secret-free public JSON. Native file drag pasteboard
  selection is covered; a complete physical drag gesture was not automated.
- A real Shared Drive membership/organization-policy upload and upload-only
  accounts lacking all previous metadata grants were not exercised in this
  live pass. Do not describe those as live-tested or guarantee all folder IDs.
- New tool definitions may require reopening the MCP client/Codex before an
  existing chat discovers them. SDK stdio integration is tested independently.

Test folder (preserved):
`https://drive.google.com/drive/folders/1rMCg5Yu18PntW5QZ44iAyQV1qO5yKpXP`.
Only self-created fixtures were uploaded, not user production files.

Final installed-build smoke test also created a nested destination using a
parent **link**, uploaded `verified-final.txt`, independently verified remote
metadata, and replayed the original request without allocating another file.
Previously completed empty/multi-chunk/cancel-and-resume jobs remained verified
after app restart. Automated checks passed: 16 upload-engine/native-pasteboard
checks, 75 existing Swift regressions, 6 Node IPC checks, and the existing
Debug/Release Keychain namespace isolation checks. CoreSimulator diagnostics
from this Xcode installation did not prevent either native Mac build.
