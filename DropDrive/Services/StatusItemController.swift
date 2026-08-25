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
    /// The live controller, so code that opens a modal panel can keep the
    /// popover from dismissing underneath it.
    private(set) static weak var current: StatusItemController?

    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var lastImageKey = ""

    /// While a system panel (the folder chooser) is up it takes key focus, and a
    /// `.transient` popover closes the instant that happens — taking the card
    /// the user was working with away with it. Pinning switches the popover to
    /// dismissing only when we say so, for the duration of that panel.
    func setPopoverPinned(_ pinned: Bool) {
        popover.behavior = pinned ? .applicationDefined : .transient
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
        }

        Self.current = self
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

    func showPopover() {
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
        }
    }

    func showSettings() {
        showPopover()
        Task { @MainActor in
            // Let a newly opened popover install its SwiftUI subscriptions
            // before selecting the pane.
            await Task.yield()
            NotificationCenter.default.post(name: .dropDriveShowSettings, object: nil)
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
        if viewModel.queue.contains(where: { $0.status == .failed }) { return .failed }
        // Ranked below anything to do with a download: an update can wait, and
        // a failed download is what the user needs to see first.
        if case .available = UpdateService.shared.state { return .updateAvailable }
        return .idle
    }

    private func refreshIcon() {
        let state = currentState()
        let key: String
        switch state {
        case .idle: key = "idle"
        case .updateAvailable: key = "update"
        case .done: key = "done"
        case .failed: key = "failed"
        case .progress(let f): key = "p\(f)"
        }
        guard key != lastImageKey else { return }
        lastImageKey = key
        statusItem.button?.image = Self.image(for: state)
    }

    private func observeState() {
        withObservationTracking {
            _ = currentState()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshIcon()
                self?.observeState()
            }
        }
        refreshIcon()
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
