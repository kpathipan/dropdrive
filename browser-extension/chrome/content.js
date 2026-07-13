// DropDrive Chrome Extension - Content Script
// Injects a "Send to DropDrive" button into Google Drive's toolbar. Building
// the deep link and launching the app is the background worker's job
// (chrome.tabs.update isn't available here) — this just asks for it.

(function () {
  "use strict";

  const BUTTON_ID = "dropdrive-download-btn";
  const EXTENSION_ICON = "⬇";

  class HistoryObserver {
    constructor(callback) {
      this.callback = callback;
      const originalPushState = history.pushState;
      const originalReplaceState = history.replaceState;

      history.pushState = function (...args) {
        originalPushState.apply(this, args);
        callback();
      };

      history.replaceState = function (...args) {
        originalReplaceState.apply(this, args);
        callback();
      };

      window.addEventListener("popstate", () => callback());
    }
  }

  function injectDownloadButton() {
    const observer = new MutationObserver(() => {
      tryInjectButton();
    });

    observer.observe(document.body, { childList: true, subtree: true });
    tryInjectButton();
  }

  function tryInjectButton() {
    const toolbars = document.querySelectorAll('[role="toolbar"]');

    for (const toolbar of toolbars) {
      if (toolbar.querySelector(`#${BUTTON_ID}`)) continue;

      const button = document.createElement("button");
      button.id = BUTTON_ID;
      button.setAttribute("aria-label", "Send to DropDrive");
      button.title = "Send to DropDrive";
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

      button.addEventListener("click", () => {
        const driveLink = getCurrentDriveLink();
        if (driveLink) {
          chrome.runtime.sendMessage({ action: "openDropDrive", url: driveLink });
        }
      });

      toolbar.appendChild(button);
      updateButtonVisibility();
    }
  }

  function getCurrentDriveLink() {
    const urlMatch = window.location.href.match(/\/(?:file|folders)\/([a-zA-Z0-9-_]+)/);
    return urlMatch ? `https://drive.google.com/file/d/${urlMatch[1]}/view` : null;
  }

  function updateButtonVisibility() {
    const button = document.getElementById(BUTTON_ID);
    if (!button) return;
    button.style.display = getCurrentDriveLink() ? "inline-block" : "none";
  }

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

  injectDownloadButton();
  document.addEventListener("DOMContentLoaded", () => {
    injectDownloadButton();
  });

  document.addEventListener("click", () => {
    setTimeout(updateButtonVisibility, 100);
  });
})();
