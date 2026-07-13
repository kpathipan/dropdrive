const DRIVE_HOST_PATTERN = /(^|\.)(drive|docs)\.google\.com$/;
const LINK_MENU_ID = "dropdrive-download-link";
const PAGE_MENU_ID = "dropdrive-download-page";

function isDriveURL(url) {
  try {
    return DRIVE_HOST_PATTERN.test(new URL(url).hostname);
  } catch {
    return false;
  }
}

// Hands the link to DropDrive via its registered `dropdrive://` URL scheme —
// the OS launches/activates the app and passes the link along, no native
// messaging host or extra install step required. The helper tab that
// triggers the scheme is opened in the background and closed right after;
// it exists only to make the OS handle the custom-scheme navigation.
function openInDropDrive(url) {
  if (!url) return;
  const target = `dropdrive://add?url=${encodeURIComponent(url)}`;
  chrome.tabs.create({ url: target, active: false }, (tab) => {
    if (chrome.runtime.lastError || !tab || tab.id === undefined) return;
    setTimeout(() => {
      chrome.tabs.remove(tab.id, () => void chrome.runtime.lastError);
    }, 800);
  });
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: LINK_MENU_ID,
    title: "Download with DropDrive",
    contexts: ["link"],
    targetUrlPatterns: ["*://drive.google.com/*", "*://docs.google.com/*"]
  });

  chrome.contextMenus.create({
    id: PAGE_MENU_ID,
    title: "Download this Drive item with DropDrive",
    contexts: ["page"],
    documentUrlPatterns: ["*://drive.google.com/*", "*://docs.google.com/*"]
  });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === LINK_MENU_ID && info.linkUrl) {
    openInDropDrive(info.linkUrl);
  } else if (info.menuItemId === PAGE_MENU_ID && tab && tab.url) {
    openInDropDrive(tab.url);
  }
});

chrome.action.onClicked.addListener((tab) => {
  if (tab && tab.url && isDriveURL(tab.url)) {
    openInDropDrive(tab.url);
  }
});
