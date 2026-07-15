import AppKit

let width: CGFloat = 560
let height: CGFloat = 438
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.png"

let bgFill = NSColor(srgbRed: 0xE6 / 255, green: 0xF1 / 255, blue: 0xFB / 255, alpha: 1) // blue-50
let arrowColor = NSColor(srgbRed: 0x0C / 255, green: 0x44 / 255, blue: 0x7C / 255, alpha: 1) // blue-800

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

bgFill.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

// Arrow between the two icon slots, at the same vertical center Finder will
// place the icons (icon size 96, positioned at y=180 in Finder's top-down
// coordinate system -> AppKit bottom-up y = height - 180).
let iconCenterY = height - 180
let shaftStartX: CGFloat = 210
let shaftEndX: CGFloat = 330
let shaftThickness: CGFloat = 5
let headLength: CGFloat = 20
let headWidth: CGFloat = 16

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: shaftStartX, y: iconCenterY - shaftThickness / 2))
arrow.line(to: NSPoint(x: shaftEndX - headLength, y: iconCenterY - shaftThickness / 2))
arrow.line(to: NSPoint(x: shaftEndX - headLength, y: iconCenterY - headWidth / 2))
arrow.line(to: NSPoint(x: shaftEndX, y: iconCenterY))
arrow.line(to: NSPoint(x: shaftEndX - headLength, y: iconCenterY + headWidth / 2))
arrow.line(to: NSPoint(x: shaftEndX - headLength, y: iconCenterY + shaftThickness / 2))
arrow.line(to: NSPoint(x: shaftStartX, y: iconCenterY + shaftThickness / 2))
arrow.close()
arrowColor.setFill()
arrow.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to render background image\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
