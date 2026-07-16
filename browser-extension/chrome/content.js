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
  const SENT_MESSAGE = "✓ Sent to DropDrive";
  const RELOAD_MESSAGE = "DropDrive was updated — reload this page to use it";

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

  /// Two layers on purpose: the outer box is sized to match the reference
  /// Download button exactly, so this sits in the same vertical band as
  /// every other icon in the row regardless of how that row aligns its
  /// children (flexbox cross-axis centering, line-height, etc. — all
  /// unknown/unstable in Drive's own markup). The inner pill is the small
  /// visible chip, centered inside that box independent of its height.
  function makeToolbarButton(referenceButton) {
    const button = document.createElement("div");
    button.id = TOOLBAR_BUTTON_ID;
    button.setAttribute("role", "button");
    button.setAttribute("tabindex", "0");
    button.setAttribute("aria-label", TOOLTIP_TEXT);
    button.setAttribute("data-tooltip", TOOLTIP_TEXT);
    button.title = TOOLTIP_TEXT;

    const refRect = referenceButton.getBoundingClientRect();
    const boxHeight = Math.round(refRect.height) || 36;

    button.style.cssText = `
      display: inline-flex;
      align-items: center;
      justify-content: center;
      height: ${boxHeight}px;
      margin: 0 2px;
      cursor: pointer;
      flex-shrink: 0;
    `;
    button.innerHTML =
      '<span style="display:inline-flex;align-items:center;gap:2px;padding:2px 6px;border-radius:999px;background-color:#2563eb;color:#ffffff;font-size:10px;font-weight:500;">' +
      dropDriveGlyphSVG() +
      "<span>DropDrive</span>" +
      "</span>";

    const pill = button.firstElementChild;
    button.addEventListener("mouseenter", () => {
      pill.style.backgroundColor = "#1d4ed8";
    });
    button.addEventListener("mouseleave", () => {
      pill.style.backgroundColor = "#2563eb";
    });

    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      sendSelectionToDropDrive();
    });

    return button;
  }

  /// DropDrive icon: a cloud-with-down-arrow glyph in white, so it reads
  /// clearly against the button's solid blue fill (distinct from Drive's
  /// own gray/outline icon language, by design).
  function dropDriveGlyphSVG() {
    return (
      '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">' +
      '<path d="M7 18a4 4 0 01-.6-7.96A5.5 5.5 0 0117.5 9.5 4 4 0 0117 18H7z" stroke="#ffffff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>' +
      '<path d="M12 11v6m0 0l-2.3-2.3M12 17l2.3-2.3" stroke="#ffffff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>' +
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

  /// Drive renders this menu in two passes — a quick partial menu first,
  /// then a fuller one moments later — and can carry more than one node
  /// whose text is "Download" while that settles (a compact quick-actions
  /// row plus the full list). The last match in DOM order is the one that
  /// survives Drive's later re-render; anchoring to an earlier duplicate
  /// left our item stranded in the wrong place once Drive's own re-render
  /// reshuffled its children around it.
  function findDownloadMenuItem(menu) {
    const items = menu.querySelectorAll('[role="menuitem"]');
    let match = null;
    for (const item of items) {
      const text = (item.textContent || "").trim().toLowerCase();
      for (const label of DOWNLOAD_LABELS) {
        if (text === label.toLowerCase()) match = item;
      }
    }
    return match;
  }

  /// Re-entrant by design: called again on every later mutation of an
  /// already-open menu (not just once at creation), since Drive's second
  /// render pass can otherwise leave a previously-inserted item stranded
  /// in the wrong spot. Always removes any stale copy first and re-anchors
  /// fresh off the current DOM rather than trusting a one-time insertion.
  function injectContextMenuItem(menu) {
    const downloadItem = findDownloadMenuItem(menu);
    if (!downloadItem) return;

    const stale = menu.querySelector(`.${MENU_ITEM_CLASS}`);
    if (stale) {
      if (stale.previousElementSibling === downloadItem) return; // already correctly placed
      stale.remove();
    }

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

  /// Reloading or updating the extension leaves the already-injected content
  /// script running in open Drive tabs with a dead `chrome.runtime` handle.
  /// Every call into it then throws "Extension context invalidated", which used
  /// to escape as an uncaught error — the button looked simply dead, with the
  /// real reason only visible on chrome://extensions. `chrome.runtime.id` goes
  /// undefined in exactly that state, so it's the cheapest way to detect it.
  function isExtensionContextAlive() {
    try {
      return Boolean(chrome.runtime && chrome.runtime.id);
    } catch (error) {
      return false;
    }
  }

  function sendSelectionToDropDrive() {
    const items = getSelectedItems();
    if (items.length === 0) return;

    const links = items.map((item) => driveLinkForID(item.id));

    if (!isExtensionContextAlive()) {
      showToast(RELOAD_MESSAGE);
      return;
    }

    try {
      chrome.runtime.sendMessage({ action: "openDropDrive", urls: links }, () => {
        if (chrome.runtime.lastError) {
          console.error("DropDrive:", chrome.runtime.lastError.message);
          showToast(RELOAD_MESSAGE);
          return;
        }
        showToast(SENT_MESSAGE);
      });
    } catch (error) {
      // sendMessage throws synchronously if the context died between the check
      // above and the call itself.
      console.error("DropDrive:", error);
      showToast(RELOAD_MESSAGE);
    }
  }

  // ---- Toast ----------------------------------------------------------------

  let toastHideTimer = null;

  function showToast(message) {
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
      document.body.appendChild(toast);
    }

    // Set every time, not just on create — a reused toast would otherwise keep
    // whatever text it was first given.
    toast.textContent = message;

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

  let pendingMenuSync = false;

  /// Re-checks every currently-open menu, not just the one that was open
  /// when this was scheduled — Drive's own two-pass render means a menu
  /// can keep mutating internally for a bit after it first appears, and
  /// injectContextMenuItem is cheap to re-run (it short-circuits once
  /// correctly placed) so a debounced sweep is simpler and more reliable
  /// than trying to track exactly which mutation matters.
  function scheduleMenuSync() {
    if (pendingMenuSync) return;
    pendingMenuSync = true;
    requestAnimationFrame(() => {
      pendingMenuSync = false;
      document.querySelectorAll('[role="menu"]').forEach((menu) => {
        if (menu.offsetParent !== null) injectContextMenuItem(menu);
      });
    });
  }

  /// Every mutation batch schedules at most one debounced toolbar re-sync
  /// (rAF-coalesced, so a burst of DOM churn during navigation still only
  /// costs one pass) and, whenever a mutation touches anything inside an
  /// open menu (its first render or Drive's later re-render pass), one
  /// debounced menu re-check.
  function handleMutations(mutations) {
    scheduleSync();

    for (const mutation of mutations) {
      const target = mutation.target;
      if (target.nodeType === Node.ELEMENT_NODE && target.closest?.('[role="menu"]')) {
        scheduleMenuSync();
      }
      for (const node of mutation.addedNodes || []) {
        if (node.nodeType !== Node.ELEMENT_NODE) continue;
        const menu = node.matches?.('[role="menu"]') ? node : node.querySelector?.('[role="menu"]');
        if (menu) scheduleMenuSync();
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
