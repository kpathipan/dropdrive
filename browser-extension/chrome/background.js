// DropDrive Chrome Extension - Background Service Worker
// Single source of truth for building the dropdrive:// deep link and
// launching the app; the content script never builds this URL itself, it
// just asks the background worker to do it (chrome.tabs.update is only
// available here, not in a content script).

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

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId !== "sendToDropDrive") return;

  const driveLink = normalizedDriveLink(info.linkUrl || tab.url);
  if (driveLink) {
    openDropDrive(driveLink, tab.id);
  }
});

// Messages from content.js (the injected per-page button) and popup.html.
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === "openDropDrive" && request.url) {
    const tabId = sender.tab ? sender.tab.id : undefined;
    openDropDrive(request.url, tabId);
    sendResponse({ success: true });
  }
});

function normalizedDriveLink(url) {
  if (!url || !url.includes("drive.google.com")) return null;
  const idMatch = url.match(/(?:file|folders)\/([a-zA-Z0-9-_]+)/);
  return idMatch ? `https://drive.google.com/file/d/${idMatch[1]}/view` : url;
}

function openDropDrive(driveLink, tabId) {
  const deepLink = `dropdrive://download?url=${encodeURIComponent(driveLink)}`;
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
