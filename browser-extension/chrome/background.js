// DropDrive Chrome Extension - Background Service Worker
// Single source of truth for building the dropdrive:// deep link and
// launching the app; content.js never builds this URL itself, it just asks
// the background worker to do it (chrome.tabs.update is only available
// here, not in a content script).

const DRIVE_URL_PATTERN = "https://drive.google.com/*";

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: "sendToDropDrive",
    title: "Send to DropDrive",
    contexts: ["page", "link"],
    documentUrlPatterns: [DRIVE_URL_PATTERN],
    targetUrlPatterns: [DRIVE_URL_PATTERN]
  });
});

// Native browser right-click menu (only reachable on a plain link/page —
// Google Drive's own file rows render a custom menu that suppresses this
// entirely, which is what content.js's in-page menu injection is for).
chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId !== "sendToDropDrive") return;

  const driveLink = normalizedDriveLink(info.linkUrl || tab.url);
  if (driveLink) {
    openDropDrive([driveLink], tab.id);
  }
});

// Messages from content.js: a toolbar-button or in-page-menu click carrying
// one or more selected item links, in selection order.
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === "openDropDrive" && Array.isArray(request.urls) && request.urls.length > 0) {
    const tabId = sender.tab ? sender.tab.id : undefined;
    openDropDrive(request.urls, tabId);
    sendResponse({ success: true });
  }
});

function normalizedDriveLink(url) {
  if (!url || !url.includes("drive.google.com")) return null;
  const idMatch = url.match(/(?:file|folders)\/([a-zA-Z0-9-_]+)/);
  return idMatch ? `https://drive.google.com/file/d/${idMatch[1]}/view` : url;
}

/// Every integration hands off through the one `dropdrive://download?url=`
/// endpoint. A multi-selection is still that same endpoint, just with the
/// `url` query parameter repeated once per link in order — not a second
/// endpoint or a made-up batch format.
function openDropDrive(driveLinks, tabId) {
  const query = driveLinks.map((link) => `url=${encodeURIComponent(link)}`).join("&");
  const deepLink = `dropdrive://download?${query}`;
  const update = { url: deepLink };
  const callback = () => {
    if (chrome.runtime.lastError) {
      console.log("Error opening DropDrive:", chrome.runtime.lastError);
    }
  };

  if (tabId !== undefined) {
    chrome.tabs.update(tabId, update, callback);
  } else {
    chrome.tabs.update(update, callback);
  }
}
