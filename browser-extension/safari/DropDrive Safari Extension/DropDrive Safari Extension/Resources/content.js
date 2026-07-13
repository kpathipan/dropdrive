// DropDrive Safari Extension Content Script
// Injects a download button and context menu options into Google Drive

(function() {
  'use strict';

  // Initialize context menu listeners
  chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.action === 'downloadFileFromDrive') {
      const driveLink = request.url;
      openDropDrive(driveLink);
    }
  });

  // Send current Google Drive URL when right-click menu item is clicked
  document.addEventListener('contextmenu', (e) => {
    const driveLink = getCurrentDriveLink();
    if (driveLink) {
      chrome.runtime.sendMessage({
        action: 'contextMenuClicked',
        url: driveLink
      });
    }
  });

  // Add download button to Google Drive interface
  function injectDownloadButton() {
    // Check if already injected
    if (document.getElementById('dropdrive-inject-btn')) return;

    // Observer for DOM changes to detect when Drive loads
    const observer = new MutationObserver(() => {
      injectButtonIfPossible();
    });

    observer.observe(document.body, { childList: true, subtree: true });
    injectButtonIfPossible();
  }

  function injectButtonIfPossible() {
    // Look for Google Drive toolbar
    const toolbars = document.querySelectorAll('[role="toolbar"]');

    for (const toolbar of toolbars) {
      // Check if this toolbar already has our button
      if (toolbar.querySelector('#dropdrive-inject-btn')) continue;

      // Create download button
      const button = document.createElement('button');
      button.id = 'dropdrive-inject-btn';
      button.setAttribute('aria-label', 'Send to DropDrive');
      button.title = 'Send to DropDrive';
      button.style.cssText = `
        padding: 8px 12px;
        margin: 0 4px;
        border: none;
        border-radius: 4px;
        background-color: #3b82f6;
        color: white;
        cursor: pointer;
        font-size: 14px;
        font-weight: 500;
        display: none;
      `;
      button.textContent = '⬇ DropDrive';

      button.addEventListener('click', () => {
        const driveLink = getCurrentDriveLink();
        if (driveLink) {
          openDropDrive(driveLink);
        }
      });

      // Insert button into toolbar
      toolbar.appendChild(button);
      updateButtonVisibility();
    }
  }

  function getCurrentDriveLink() {
    // Extract current file/folder ID from URL or page
    const urlMatch = window.location.href.match(/\/(?:file|folders)\/([a-zA-Z0-9-_]+)/);
    if (urlMatch && urlMatch[1]) {
      return `https://drive.google.com/file/d/${urlMatch[1]}/view`;
    }
    return null;
  }

  function updateButtonVisibility() {
    const button = document.getElementById('dropdrive-inject-btn');
    if (!button) return;

    const driveLink = getCurrentDriveLink();
    button.style.display = driveLink ? 'inline-block' : 'none';
  }

  function openDropDrive(driveLink) {
    // Use deep link to open DropDrive with the file
    const deepLink = `dropdrive://add?url=${encodeURIComponent(driveLink)}`;
    window.location.href = deepLink;
  }

  // Listen for URL changes
  let lastUrl = location.href;
  const urlObserver = new HistoryObserver(() => {
    if (location.href !== lastUrl) {
      lastUrl = location.href;
      setTimeout(() => {
        injectDownloadButton();
        updateButtonVisibility();
      }, 500);
    }
  });

  // History API observer
  class HistoryObserver {
    constructor(callback) {
      this.callback = callback;
      const originalPushState = history.pushState;
      const originalReplaceState = history.replaceState;

      history.pushState = function(...args) {
        originalPushState.apply(this, args);
        callback();
      };

      history.replaceState = function(...args) {
        originalReplaceState.apply(this, args);
        callback();
      };

      window.addEventListener('popstate', () => callback());
    }
  }

  // Initialize on page load
  injectDownloadButton();

  // Also watch for DOM changes
  document.addEventListener('DOMContentLoaded', () => {
    injectDownloadButton();
  });

  // Update button visibility when selection changes
  document.addEventListener('click', () => {
    updateButtonVisibility();
  });
})();
