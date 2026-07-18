import AppKit
import SwiftUI

/// The menu bar status icon: the plain tray when idle, a live progress ring while
/// downloading, a checkmark flash right after the queue finishes, and a warning
/// triangle while a failed item is waiting for a retry. Drawn as template images
/// so it matches the menu bar in both light and dark appearance.
struct MenuBarIconLabel: View {
    @State private var viewModel = DropDriveViewModel.shared

    var body: some View {
        if viewModel.showCompletionFlash {
            Image(systemName: "checkmark.circle")
        } else if viewModel.isQueueProcessing {
            Image(nsImage: Self.ringImage(fraction: quantizedFraction))
        } else if viewModel.queue.contains(where: { $0.status == .failed }) {
            Image(systemName: "exclamationmark.triangle")
        } else {
            Image(systemName: "tray.and.arrow.down.fill")
        }
    }

    /// Quantized to 2% steps so the label isn't re-rendered on every byte callback.
    private var quantizedFraction: Double {
        let raw = viewModel.activeProgress?.fractionCompleted ?? 0
        return (raw * 50).rounded() / 50
    }

    private static func ringImage(fraction: Double) -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width / 2 - 2

            // Track: the full circle at low opacity.
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = 2
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()

            // Progress arc, clockwise from 12 o'clock.
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

            // Small arrow in the middle.
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
        // Template rendering: the system recolors the alpha mask for the current
        // menu bar appearance (and the highlighted state when the item is open).
        image.isTemplate = true
        return image
    }
}
