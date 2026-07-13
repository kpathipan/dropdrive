// DropDrive Background Service Worker

// Create context menu items for downloading from Google Drive
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: 'sendToDropDrive',
    title: 'Send to DropDrive',
    contexts: ['page', 'link'],
    targetUrlPatterns: ['https://drive.google.com/*']
  });
});

// Handle context menu clicks
chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === 'sendToDropDrive') {
    // Get the current tab's URL (for files/folders) or link URL
    let driveLink = info.linkUrl || tab.url;

    // Ensure it's a proper Google Drive link
    if (driveLink && driveLink.includes('drive.google.com')) {
      // Extract file/folder ID from URL
      const idMatch = driveLink.match(/(?:file|folders)\/([a-zA-Z0-9-_]+)/);
      if (idMatch && idMatch[1]) {
        driveLink = `https://drive.google.com/file/d/${idMatch[1]}/view`;
      }

      // Send to DropDrive via deep link
      const deepLink = `dropdrive://add?url=${encodeURIComponent(driveLink)}`;
      chrome.tabs.sendMessage(tab.id, {
        action: 'downloadFileFromDrive',
        url: driveLink
      });

      // Also try to open the deep link directly
      chrome.tabs.update(tab.id, { url: deepLink });
    }
  }
});

// Listen for messages from content scripts
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === 'contextMenuClicked') {
    const deepLink = `dropdrive://add?url=${encodeURIComponent(request.url)}`;
    chrome.tabs.update(sender.tab.id, { url: deepLink });
  }
});
