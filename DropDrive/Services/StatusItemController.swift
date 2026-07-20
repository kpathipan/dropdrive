import AppKit
import SwiftUI
import Observation

/// Owns the menu bar status item and the popover it toggles. Left-click opens
/// the app popover; right-click (or control-click) shows a small menu whose only
/// item quits the app. The icon reflects download state — idle tray, a live
/// progress ring, a completion checkmark, or a warning triangle — refreshed on a
/// light timer so no Observation plumbing is needed in AppKit.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var refreshTimer: Timer?
    private var lastImageKey = ""

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

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshIcon() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
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
        } else if let button = statusItem.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
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
        return .idle
    }

    private func refreshIcon() {
        let state = currentState()
        let key: String
        switch state {
        case .idle: key = "idle"
        case .done: key = "done"
        case .failed: key = "failed"
        case .progress(let f): key = "p\(f)"
        }
        guard key != lastImageKey else { return }
        lastImageKey = key
        statusItem.button?.image = Self.image(for: state)
    }

    private static func image(for state: IconState) -> NSImage {
        switch state {
        case .idle:
            return appIcon()
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
    private static func appIcon() -> NSImage {
        let side: CGFloat = 18
        guard let logo = NSImage(named: "AppLogo") else {
            return symbol("tray.and.arrow.down.fill")
        }
        let scaled = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            logo.draw(in: rect)
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
