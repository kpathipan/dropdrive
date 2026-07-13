// DropDrive Chrome Extension - Content Script
// Injects download button and context menu into Google Drive

(function() {
  'use strict';

  const BUTTON_ID = 'dropdrive-download-btn';
  const EXTENSION_ICON = '⬇';

  // Listen for messages from background script
  chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.action === 'downloadFileFromDrive') {
      const driveLink = request.url;
      openDropDrive(driveLink);
      sendResponse({ success: true });
    }
  });

  // Inject download button into Google Drive toolbar
  function injectDownloadButton() {
    if (document.getElementById(BUTTON_ID)) return;

    const observer = new MutationObserver(() => {
      tryInjectButton();
    });

    observer.observe(document.body, { childList: true, subtree: true });
    tryInjectButton();
  }

  function tryInjectButton() {
    // Find Google Drive toolbar (main actions toolbar)
    const toolbars = document.querySelectorAll('[role="toolbar"]');

    for (const toolbar of toolbars) {
      if (toolbar.querySelector(`#${BUTTON_ID}`)) continue;

      const button = document.createElement('button');
      button.id = BUTTON_ID;
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
      button.textContent = `${EXTENSION_ICON} DropDrive`;

      button.addEventListener('click', () => {
        const driveLink = getCurrentDriveLink();
        if (driveLink) {
          openDropDrive(driveLink);
        }
      });

      toolbar.appendChild(button);
      updateButtonVisibility();
    }
  }

  function getCurrentDriveLink() {
    // Extract file/folder ID from URL
    const urlMatch = window.location.href.match(/\/(?:file|folders)\/([a-zA-Z0-9-_]+)/);
    if (urlMatch && urlMatch[1]) {
      return `https://drive.google.com/file/d/${urlMatch[1]}/view`;
    }
    return null;
  }

  function updateButtonVisibility() {
    const button = document.getElementById(BUTTON_ID);
    if (!button) return;

    const driveLink = getCurrentDriveLink();
    button.style.display = driveLink ? 'inline-block' : 'none';
  }

  function openDropDrive(driveLink) {
    // Use deep link to launch DropDrive
    const deepLink = `dropdrive://add?url=${encodeURIComponent(driveLink)}`;
    window.location.href = deepLink;
  }

  // Listen for URL changes (SPA navigation)
  let lastUrl = location.href;
  new HistoryObserver(() => {
    if (location.href !== lastUrl) {
      lastUrl = location.href;
      setTimeout(() => {
        injectDownloadButton();
        updateButtonVisibility();
      }, 500);
    }
  });

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

  // Initialize
  injectDownloadButton();
  document.addEventListener('DOMContentLoaded', () => {
    injectDownloadButton();
  });

  // Update visibility on navigation
  document.addEventListener('click', () => {
    setTimeout(updateButtonVisibility, 100);
  });
})();
