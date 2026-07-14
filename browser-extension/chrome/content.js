// DropDrive Chrome Extension - Content Script
//
// Injects a "DropDrive" toolbar action next to Google Drive's own Download
// button, and a matching entry in Drive's right-click menu. Both send the
// currently-selected item(s) to the background worker, which is the only
// place that builds the dropdrive:// deep link and asks Chrome to open it.
//
// Google Drive is a single-page app with an obfuscated, frequently-changing
// DOM, so every selector here is deliberately layered: a primary signal
// (data-tooltip / aria-label, which Google keeps stable for accessibility)
// with a text-content fallback. Selection state and DOM injection are driven
// by one debounced MutationObserver rather than polling.
//
// KNOWN GAP: "Download" is matched in English. This was written without
// interactive access to a live Drive session to check whether Google
// localizes data-tooltip/aria-label values themselves (as opposed to just
// the visible text) — if it does, none of the selectors below will match
// on a non-English Drive locale, and the extension will silently do
// nothing rather than break. Confirm against a real account before relying
// on this for non-English users.

(function () {
  "use strict";

  const TOOLBAR_BUTTON_ID = "dropdrive-toolbar-btn";
  const MENU_ITEM_CLASS = "dropdrive-menu-item";
  const TOAST_ID = "dropdrive-toast";
  const TOOLTIP_TEXT = "Download with DropDrive";

  // ---- Selection tracking -------------------------------------------------

  /// A selected row/tile always carries Drive's own `data-id` (the file or
  /// folder id) — used both to detect "something is selected" and to build
  /// the actual links to send. Restricting to `[aria-selected="true"]`
  /// elements that also carry `data-id` avoids matching unrelated selected
  /// UI (e.g. a selected sidebar item) that isn't a Drive file/tile.
  function getSelectedItems() {
    const nodes = document.querySelectorAll('[aria-selected="true"][data-id]');
    const items = [];
    const seen = new Set();
    for (const node of nodes) {
      const id = node.getAttribute("data-id");
      if (!id || seen.has(id)) continue;
      seen.add(id);
      items.push({ id, node });
    }
    return items;
  }

  function driveLinkForID(id) {
    // Works for both files and folders without needing to know which —
    // GoogleDriveLinkParser (app-side) already supports this ?id= form.
    return `https://drive.google.com/open?id=${encodeURIComponent(id)}`;
  }

  // ---- Toolbar injection ---------------------------------------------------

  /// "Download" as Drive itself renders it in `data-tooltip`/`aria-label` —
  /// confirmed BOTH attributes are localized (not just visible text), by
  /// live inspection of a real Thai-locale Drive session on 2026-07-14
  /// ("ดาวน์โหลด"). Only English and Thai are verified against the live
  /// site; the rest are best-effort and unverified — extend this list (or
  /// replace the strategy) once more locales can be checked for real.
  const DOWNLOAD_LABELS = ["Download", "ดาวน์โหลด"];

  function findToolbarDownloadButton() {
    for (const label of DOWNLOAD_LABELS) {
      const match =
        document.querySelector(`[data-tooltip="${label}"]`) || document.querySelector(`[aria-label="${label}"]`);
      if (match) return match;
    }
    return null;
  }

  function makeToolbarButton(referenceButton) {
    const button = document.createElement("div");
    button.id = TOOLBAR_BUTTON_ID;
    button.setAttribute("role", "button");
    button.setAttribute("tabindex", "0");
    button.setAttribute("aria-label", TOOLTIP_TEXT);
    button.setAttribute("data-tooltip", TOOLTIP_TEXT);
    button.title = TOOLTIP_TEXT;

    // Match the reference button's box size instead of inventing our own —
    // keeps this from ever becoming an "oversized" button next to Drive's
    // own compact Material icon-buttons.
    const refRect = referenceButton.getBoundingClientRect();
    const size = Math.max(28, Math.min(40, Math.round(refRect.height) || 36));

    button.style.cssText = `
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: ${size}px;
      height: ${size}px;
      margin: 0 2px;
      border-radius: 50%;
      cursor: pointer;
      color: #5f6368;
      flex-shrink: 0;
    `;
    button.innerHTML = dropDriveGlyphSVG();

    button.addEventListener("mouseenter", () => {
      button.style.backgroundColor = "rgba(60,64,67,0.08)";
    });
    button.addEventListener("mouseleave", () => {
      button.style.backgroundColor = "transparent";
    });

    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      sendSelectionToDropDrive();
    });

    return button;
  }

  /// A small circular download-to-device glyph, drawn inline so the
  /// extension doesn't need to ship/load a separate icon asset for this.
  function dropDriveGlyphSVG() {
    return (
      '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">' +
      '<path d="M12 3v10m0 0l-4-4m4 4l4-4" stroke="#5f6368" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>' +
      '<path d="M5 17v2a2 2 0 002 2h10a2 2 0 002-2v-2" stroke="#5f6368" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>' +
      "</svg>"
    );
  }

  function syncToolbarButton() {
    const downloadButton = findToolbarDownloadButton();
    const existing = document.getElementById(TOOLBAR_BUTTON_ID);

    if (!downloadButton) {
      // Drive removes its own Download button from the toolbar when nothing
      // is selected — ours should disappear with it, not linger stale.
      if (existing) existing.remove();
      return;
    }

    if (existing) {
      // Already in the right place from a previous pass — nothing to do.
      if (existing.previousElementSibling === downloadButton || existing.nextElementSibling === downloadButton) {
        return;
      }
      existing.remove();
    }

    const button = makeToolbarButton(downloadButton);
    downloadButton.insertAdjacentElement("afterend", button);
  }

  // ---- Context menu injection ---------------------------------------------

  function findDownloadMenuItem(menu) {
    const items = menu.querySelectorAll('[role="menuitem"]');
    for (const item of items) {
      const text = (item.textContent || "").trim().toLowerCase();
      for (const label of DOWNLOAD_LABELS) {
        if (text === label.toLowerCase()) return item;
      }
    }
    return null;
  }

  function injectContextMenuItem(menu) {
    if (menu.querySelector(`.${MENU_ITEM_CLASS}`)) return; // already inserted for this menu instance

    const downloadItem = findDownloadMenuItem(menu);
    if (!downloadItem) return;

    const dropDriveItem = downloadItem.cloneNode(true);
    dropDriveItem.classList.add(MENU_ITEM_CLASS);
    dropDriveItem.removeAttribute("id");

    // Replace whatever text node holds "Download" with "DropDrive", leaving
    // Drive's own icon/structure/styling around it intact.
    replaceMenuItemLabel(dropDriveItem, "DropDrive");

    dropDriveItem.addEventListener(
      "click",
      (event) => {
        event.preventDefault();
        event.stopPropagation();
        sendSelectionToDropDrive();
        closeMenu();
      },
      true
    );

    downloadItem.insertAdjacentElement("afterend", dropDriveItem);
  }

  function replaceMenuItemLabel(item, newText) {
    const walker = document.createTreeWalker(item, NodeFilter.SHOW_TEXT);
    let bestNode = null;
    let bestLength = 0;
    let node;
    while ((node = walker.nextNode())) {
      const trimmed = node.nodeValue.trim();
      if (trimmed.length > bestLength) {
        bestLength = trimmed.length;
        bestNode = node;
      }
    }
    if (bestNode) bestNode.nodeValue = newText;
  }

  function closeMenu() {
    // Ask Drive to dismiss its own menu the same way a real user interaction
    // would (click-outside and Escape are the two conventional triggers for
    // this kind of overlay) — deliberately not touching the menu's own DOM
    // node/styles directly, since forcing it hidden could leave Drive's own
    // re-render logic confused the next time the menu should open.
    document.body.click();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
  }

  // ---- Sending the selection -----------------------------------------------

  function sendSelectionToDropDrive() {
    const items = getSelectedItems();
    if (items.length === 0) return;

    const links = items.map((item) => driveLinkForID(item.id));
    chrome.runtime.sendMessage({ action: "openDropDrive", urls: links }, () => {
      if (chrome.runtime.lastError) {
        console.error("DropDrive:", chrome.runtime.lastError.message);
        return;
      }
      showToast();
    });
  }

  // ---- Toast ----------------------------------------------------------------

  let toastHideTimer = null;

  function showToast() {
    let toast = document.getElementById(TOAST_ID);
    if (!toast) {
      toast = document.createElement("div");
      toast.id = TOAST_ID;
      toast.style.cssText = `
        position: fixed;
        bottom: 24px;
        right: 24px;
        z-index: 2147483647;
        background: #202124;
        color: #fff;
        padding: 10px 16px;
        border-radius: 8px;
        font: 13px/1.4 "Google Sans", Roboto, Arial, sans-serif;
        box-shadow: 0 2px 10px rgba(0,0,0,0.3);
        opacity: 0;
        transition: opacity 0.15s ease-in-out;
        pointer-events: none;
      `;
      toast.textContent = "✓ Sent to DropDrive";
      document.body.appendChild(toast);
    }

    // Re-triggering while a toast is already visible just resets its timer
    // instead of stacking a second one.
    clearTimeout(toastHideTimer);
    requestAnimationFrame(() => {
      toast.style.opacity = "1";
    });
    toastHideTimer = setTimeout(() => {
      toast.style.opacity = "0";
    }, 2200);
  }

  // ---- Debounced observation -------------------------------------------------

  let pendingSync = false;

  function scheduleSync() {
    if (pendingSync) return;
    pendingSync = true;
    requestAnimationFrame(() => {
      pendingSync = false;
      syncToolbarButton();
    });
  }

  /// Every mutation batch schedules at most one debounced toolbar re-sync
  /// (rAF-coalesced, so a burst of DOM churn during navigation still only
  /// costs one pass) and separately checks only the newly-added nodes for a
  /// freshly-opened context menu — no full-document re-scanning either way.
  function handleMutations(mutations) {
    scheduleSync();

    for (const mutation of mutations) {
      for (const node of mutation.addedNodes || []) {
        if (node.nodeType !== Node.ELEMENT_NODE) continue;
        const menu = node.matches?.('[role="menu"]') ? node : node.querySelector?.('[role="menu"]');
        if (menu) {
          // The menu still needs to finish rendering its own items.
          requestAnimationFrame(() => injectContextMenuItem(menu));
        }
      }
    }
  }

  function start() {
    syncToolbarButton();
    const observer = new MutationObserver(handleMutations);
    observer.observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["aria-selected"]
    });
  }

  if (document.body) {
    start();
  } else {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  }
})();
