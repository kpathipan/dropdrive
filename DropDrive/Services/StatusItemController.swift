import AppKit
import SwiftUI
import Observation

/// Owns the menu bar status item and the popover it toggles. Left-click opens
/// the app popover; right-click (or control-click) shows a small menu whose only
/// item quits the app. The icon reflects download state — idle tray, a live
/// progress ring, a completion checkmark, or a warning triangle — refreshed on a
/// Observation-driven so the idle menu-bar app does not wake twice a second.
@MainActor
final class StatusItemController: NSObject {
    /// The live controller, so a modal panel can fold and restore the existing
    /// popover without rebuilding its SwiftUI state.
    private(set) static weak var current: StatusItemController?

    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var dropTargetView: StatusItemDropTargetView?
    private var globalShortcut: GlobalShortcutService?
    private var lastImageKey = ""
    private var lastTitle = ""

    /// A folder panel needs the same part of the screen as this compact window.
    /// Close the chrome but retain its SwiftUI controller/state, then restore it
    /// after the panel finishes so the exact analysis card and selection return.
    func hidePopoverForExternalPanel() -> Bool {
        let wasShown = popover.isShown
        if wasShown { popover.performClose(nil) }
        return wasShown
    }

    func restorePopoverAfterExternalPanel(if wasShown: Bool) {
        guard wasShown else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.showPopover(importClipboard: false)
        }
    }

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MenuBarView())

        super.init()

        if let button = statusItem.button {
            button.image = Self.image(for: .idle)
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("DropDrive")
            button.toolTip = "DropDrive · \(GlobalShortcutService.displayName)"

            let dropTarget = StatusItemDropTargetView(frame: button.bounds)
            dropTarget.autoresizingMask = [.width, .height]
            dropTarget.onClick = { [weak self] isContextClick in
                if isContextClick {
                    self?.showMenu()
                } else {
                    self?.togglePopover()
                }
            }
            dropTarget.onHighlight = { [weak button] highlighted in
                button?.highlight(highlighted)
            }
            dropTarget.onDrop = { [weak self] links in
                self?.receiveDroppedLinks(links)
            }
            dropTarget.onDestinationDrop = { [weak self] folderURL in
                DropDriveViewModel.shared.selectDestinationFolder(folderURL)
                self?.showPopover(importClipboard: false)
                NotificationCenter.default.post(name: .dropDriveShowQueue, object: nil)
            }
            dropTarget.toolTip = button.toolTip
            button.addSubview(dropTarget)
            dropTargetView = dropTarget
        }

        Self.current = self
        globalShortcut = GlobalShortcutService { [weak self] in
            self?.showPopover()
        }
        if globalShortcut == nil {
            statusItem.button?.toolTip = tr(
                "DropDrive · global shortcut unavailable",
                "DropDrive · คีย์ลัดถูกใช้งานโดยแอปอื่น"
            )
            dropTargetView?.toolTip = statusItem.button?.toolTip
        }
        observeState()
    }

    // MARK: - Click handling

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)

        if isRightClick {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover(importClipboard: Bool = true) {
        let importedClipboardLink = importClipboard
            && UserDefaults.standard.bool(forKey: "hasSeenWelcome")
            && DropDriveViewModel.shared.importClipboardLinksIfAppropriate()

        if !popover.isShown, let button = statusItem.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            // Opening the window is the moment someone is actually looking, so
            // it's the moment worth having a current answer for — and it gets a
            // fifteen-minute leash rather than the background check's daily one,
            // since sharing that meant opening the window often changed nothing
            // and the Preferences button stayed the only way to find a release.
            UpdateService.shared.checkOnOpen()
        } else if popover.isShown {
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }

        if importedClipboardLink {
            Task { @MainActor in
                await Task.yield()
                NotificationCenter.default.post(name: .dropDriveShowQueue, object: nil)
            }
        }
    }

    func showSettings() {
        showPopover(importClipboard: false)
        Task { @MainActor in
            // Let a newly opened popover install its SwiftUI subscriptions
            // before selecting the pane.
            await Task.yield()
            NotificationCenter.default.post(name: .dropDriveShowSettings, object: nil)
        }
    }

    func showAttention() {
        showPopover(importClipboard: false)
        Task { @MainActor in
            await Task.yield()
            NotificationCenter.default.post(name: .dropDriveShowAttention, object: nil)
        }
    }

    private func showMenu() {
        popover.performClose(nil)

        let menu = NSMenu()
        let quit = NSMenuItem(
            title: tr("Quit DropDrive", "ปิด DropDrive"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    /// Dragging onto the tiny menu-bar icon is an intentional quick action: if
    /// a destination is ready, the links use the same silent queue path as the
    /// Share extension. If setup or sign-in needs attention, preserve the links
    /// in the normal review field and reveal the popover instead of losing them.
    private func receiveDroppedLinks(_ links: [String]) {
        guard !links.isEmpty else { return }
        let viewModel = DropDriveViewModel.shared
        guard viewModel.selectedDestinationURL != nil else {
            viewModel.driveLink = links.joined(separator: "\n")
            showPopover(importClipboard: false)
            NotificationCenter.default.post(name: .dropDriveShowQueue, object: nil)
            return
        }

        Task { @MainActor [weak self] in
            let receipt = await viewModel.receiveExternalLinks(
                links,
                sourceLabel: tr("from the menu bar", "จากเมนูบาร์")
            )
            if !receipt.retryableLinks.isEmpty {
                viewModel.driveLink = receipt.retryableLinks.joined(separator: "\n")
                self?.showPopover(importClipboard: false)
                NotificationCenter.default.post(name: .dropDriveShowQueue, object: nil)
            }
        }
    }

    @objc private func quit() {
        let viewModel = DropDriveViewModel.shared
        guard viewModel.isQueueProcessing else {
            NSApp.terminate(nil)
            return
        }

        let alert = NSAlert()
        alert.messageText = tr("A download is in progress. Quit anyway?", "กำลังดาวน์โหลดอยู่ ต้องการปิดแอพเลยไหม?")
        alert.addButton(withTitle: tr("Quit and stop downloading", "ปิดและหยุดดาวน์โหลด"))
        alert.addButton(withTitle: tr("Keep downloading", "ดาวน์โหลดต่อ"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Icon state

    private enum IconState: Equatable {
        case idle
        /// Idle, but an update is waiting to be installed. Distinct from `idle`
        /// so the resting icon can carry a hint that clicking is worth it —
        /// otherwise the update banner only rewards someone who happened to
        /// open the window for another reason.
        case updateAvailable
        case progress(Double)
        case done
        case failed
    }

    private func currentState() -> IconState {
        let viewModel = DropDriveViewModel.shared
        if viewModel.showCompletionFlash { return .done }
        if viewModel.isQueueProcessing {
            let raw = viewModel.activeProgress?.fractionCompleted ?? 0
            return .progress((raw * 50).rounded() / 50) // 2% steps
        }
        if viewModel.queue.contains(where: { $0.status == .failed || $0.status == .waiting }) { return .failed }
        // Ranked below anything to do with a download: an update can wait, and
        // a failed download is what the user needs to see first.
        if case .available = UpdateService.shared.state { return .updateAvailable }
        return .idle
    }

    private func refreshIcon() {
        let state = currentState()
        let title = menuBarProgressTitle()
        let key: String
        switch state {
        case .idle: key = "idle"
        case .updateAvailable: key = "update"
        case .done: key = "done"
        case .failed: key = "failed"
        case .progress(let f): key = "p\(f)"
        }
        if key != lastImageKey {
            lastImageKey = key
            statusItem.button?.image = Self.image(for: state)
        }
        if title != lastTitle {
            lastTitle = title
            statusItem.button?.title = title
            statusItem.button?.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        }
    }

    private func observeState() {
        withObservationTracking {
            _ = currentState()
            _ = menuBarProgressTitle()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshIcon()
                self?.observeState()
            }
        }
        refreshIcon()
    }

    private func menuBarProgressTitle() -> String {
        guard PreferencesStore.shared.showMenuBarProgress,
              DropDriveViewModel.shared.isQueueProcessing,
              let progress = DropDriveViewModel.shared.activeProgress else { return "" }

        var parts: [String] = []
        if let fraction = progress.fractionCompleted {
            parts.append("\(Int((fraction * 100).rounded()))%")
        }
        if let eta = progress.etaSeconds, let remaining = Formatters.remainingTime(eta) {
            parts.append(remaining)
        }
        if parts.isEmpty, progress.bytesPerSecond > 0 {
            parts.append(Formatters.transferSpeed(progress.bytesPerSecond))
        }
        return parts.prefix(2).joined(separator: " · ")
    }

    private static func image(for state: IconState) -> NSImage {
        switch state {
        case .idle:
            return appIcon()
        case .updateAvailable:
            return appIcon(withUpdateDot: true)
        case .done:
            return symbol("checkmark.circle")
        case .failed:
            return symbol("exclamationmark.triangle")
        case .progress(let fraction):
            return ringImage(fraction: fraction)
        }
    }

    /// The actual app icon, in its original colors, scaled to menu bar size — so
    /// the resting icon reads as DropDrive. Not a template (kept colored).
    private static func appIcon(withUpdateDot: Bool = false) -> NSImage {
        let side: CGFloat = 18
        guard let logo = NSImage(named: "AppLogo") else {
            return symbol("tray.and.arrow.down.fill")
        }
        let scaled = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            logo.draw(in: rect)
            guard withUpdateDot else { return true }

            // A small badge on the top-right corner. Sized and coloured by
            // rendering the candidates and looking at them at true menu bar
            // scale: 7pt read as a defect rather than a badge, and the accent
            // blue disappeared into the icon, which is blue. Orange separates
            // from it and still says "worth a look" rather than "something is
            // wrong" — the failed-download state owns the alarming end. The
            // white ring is what keeps it legible on both a light and a dark
            // menu bar, where a background-coloured one resolved to black.
            let diameter: CGFloat = 4.5
            let dot = NSRect(
                x: rect.maxX - diameter - 0.5,
                y: rect.maxY - diameter - 0.5,
                width: diameter,
                height: diameter
            )
            NSColor.white.setFill()
            NSBezierPath(ovalIn: dot.insetBy(dx: -1, dy: -1)).fill()
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        scaled.isTemplate = false
        return scaled
    }

    private static func symbol(_ name: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "DropDrive")
            ?? NSImage()
        image.isTemplate = true
        return image
    }

    private static func ringImage(fraction: Double) -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width / 2 - 2

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = 2
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()

            let progress = NSBezierPath()
            let start: CGFloat = 90
            progress.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: start,
                endAngle: start - CGFloat(fraction) * 360,
                clockwise: true
            )
            progress.lineWidth = 2
            progress.lineCapStyle = .round
            NSColor.black.setStroke()
            progress.stroke()

            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: center.x, y: center.y + 3.2))
            arrow.line(to: NSPoint(x: center.x, y: center.y - 2.6))
            arrow.move(to: NSPoint(x: center.x - 2.4, y: center.y - 0.2))
            arrow.line(to: NSPoint(x: center.x, y: center.y - 2.8))
            arrow.line(to: NSPoint(x: center.x + 2.4, y: center.y - 0.2))
            arrow.lineWidth = 1.4
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            NSColor.black.setStroke()
            arrow.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Transparent interaction layer over NSStatusBarButton. AppKit does not let a
/// caller replace the system-created button with a subclass, so this child view
/// handles both normal clicks and registered drag destinations while the parent
/// continues to draw the real menu-bar icon.
@MainActor
private final class StatusItemDropTargetView: NSView {
    var onClick: ((Bool) -> Void)?
    var onHighlight: ((Bool) -> Void)?
    var onDrop: (([String]) -> Void)?
    var onDestinationDrop: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.URL, .fileURL, .string])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onHighlight?(true)
    }

    override func mouseUp(with event: NSEvent) {
        onHighlight?(false)
        onClick?(event.modifierFlags.contains(.control))
    }

    override func rightMouseDown(with event: NSEvent) {
        onHighlight?(true)
    }

    override func rightMouseUp(with event: NSEvent) {
        onHighlight?(false)
        onClick?(true)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let acceptsDrop = Self.destinationFolder(from: sender.draggingPasteboard) != nil
            || !Self.links(from: sender.draggingPasteboard).isEmpty
        onHighlight?(acceptsDrop)
        return acceptsDrop ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onHighlight?(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onHighlight?(false)
        if let folderURL = Self.destinationFolder(from: sender.draggingPasteboard) {
            onDestinationDrop?(folderURL)
            return true
        }
        let links = Self.links(from: sender.draggingPasteboard)
        guard !links.isEmpty else { return false }
        onDrop?(links)
        return true
    }

    private static func destinationFolder(from pasteboard: NSPasteboard) -> URL? {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [NSURL])?
            .map { $0 as URL } ?? []
        return urls.first { url in
            guard url.isFileURL,
                  url.pathExtension.caseInsensitiveCompare("webloc") != .orderedSame else { return false }
            return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private static func links(from pasteboard: NSPasteboard) -> [String] {
        var rawValues: [String] = []
        for type in [NSPasteboard.PasteboardType.URL, .string] {
            if let value = pasteboard.string(forType: type), !value.isEmpty {
                rawValues.append(value)
            }
        }

        let draggedURLs = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [NSURL])?
            .map { $0 as URL } ?? []
        for url in draggedURLs {
            if url.isFileURL, url.pathExtension.caseInsensitiveCompare("webloc") == .orderedSame,
               let data = try? Data(contentsOf: url),
               let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
               let dictionary = propertyList as? [String: Any],
               let link = dictionary["URL"] as? String {
                rawValues.append(link)
            } else if !url.isFileURL {
                rawValues.append(url.absoluteString)
            }
        }

        return SupportedLinkExtractor.links(from: rawValues.joined(separator: "\n"))
    }
}
