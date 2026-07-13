# DropDrive Browser Integration

Both extensions send a right-clicked or active-tab Drive link straight into
DropDrive's queue via its `dropdrive://add?url=<link>` URL scheme — no copy/paste,
no native messaging host to install.

- [`chrome/`](chrome/) — Chrome MV3 extension (source of truth), load unpacked via
  Developer Mode. Not published to the Chrome Web Store.
- [`safari/`](safari/) — Safari Web Extension, generated from the Chrome extension
  source with Apple's `safari-web-extension-converter` and built as its own small
  companion app.

See each folder's README for install steps.
