# DropDrive Browser Integration

The extension sends a right-clicked or active-tab Drive link straight into
DropDrive's queue via its `dropdrive://download?url=<link>` URL scheme — no
copy/paste, no native messaging host to install.

- [`chrome/`](chrome/) — Chrome MV3 extension (source of truth), load unpacked via
  Developer Mode. Not published to the Chrome Web Store.

Chrome only, by design — see each folder's README for install steps.
