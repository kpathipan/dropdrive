import AppKit

// The installer window's backdrop. It carries the instructions itself rather
// than leaving them to the help file beside the app: the help file is easy to
// miss, and someone who hits Gatekeeper's warning without having read anything
// concludes the app is broken — or malware — and stops there. Everything needed
// to finish the install is visible the moment the disk image opens.
//
// The one thing this can't carry is the Terminal command: text in an image
// can't be copied, and asking someone to retype `xattr -cr /Applications/...`
// by hand is worse than any amount of reading. So the backdrop describes the
// click-only route, and the help file keeps the command behind a Copy button
// as a shortcut for whoever prefers it.

let width: CGFloat = 620
let height: CGFloat = 650
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.png"

let bgFill = NSColor(srgbRed: 0xE6 / 255, green: 0xF1 / 255, blue: 0xFB / 255, alpha: 1)
let ink = NSColor(srgbRed: 0x0C / 255, green: 0x44 / 255, blue: 0x7C / 255, alpha: 1)
let inkSoft = NSColor(srgbRed: 0x18 / 255, green: 0x5F / 255, blue: 0xA5 / 255, alpha: 1)
let cardStroke = NSColor(srgbRed: 0x85 / 255, green: 0xB7 / 255, blue: 0xEB / 255, alpha: 1)

/// Sukhumvit Set is the app's own typeface and the loopless Thai family macOS
/// ships; its Latin glyphs read cleanly too, so both languages use it here and
/// the window matches the app.
func font(_ size: CGFloat, bold: Bool = false) -> NSFont {
    NSFont(name: bold ? "SukhumvitSet-Bold" : "SukhumvitSet-Text", size: size)
        ?? NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
}

func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, bold: Bool = false, centered: Bool = false) {
    let string = NSAttributedString(
        string: text,
        attributes: [.font: font(size, bold: bold), .foregroundColor: color]
    )
    let originX = centered ? (width - string.size().width) / 2 : x
    string.draw(at: NSPoint(x: originX, y: y))
}

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

bgFill.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

// AppKit draws bottom-up while Finder positions icons top-down; the icons sit
// at y=155 in Finder's space, so their centre is height - 155 here.
let iconCenterY = height - 155

draw("ลากไปวางที่ Applications", x: 0, y: height - 72, size: 15, color: ink, bold: true, centered: true)
draw("Drag DropDrive onto Applications", x: 0, y: height - 94, size: 11.5, color: inkSoft, centered: true)

let shaftStartX: CGFloat = 245
let shaftEndX: CGFloat = 375
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
ink.setFill()
arrow.fill()

// The card that explains Gatekeeper's warning before it appears.
let cardRect = NSRect(x: 40, y: 195, width: width - 80, height: 186)
let card = NSBezierPath(roundedRect: cardRect, xRadius: 12, yRadius: 12)
NSColor.white.setFill()
card.fill()
cardStroke.setStroke()
card.lineWidth = 1
card.stroke()

let textX = cardRect.minX + 24
var y = cardRect.maxY - 30

// Terminal first, deliberately: the help file carries the command behind a Copy
// button, so that route is two steps with nothing to type, while the
// click-only route is three and buried in System Settings.
draw("เปิดครั้งแรกแล้วขึ้นเตือน? ปกติครับ ไม่ใช่ไวรัส", x: textX, y: y, size: 13, color: ink, bold: true)
y -= 18
draw("Normal, not a virus — one time only.", x: textX, y: y, size: 10, color: inkSoft)

y -= 28
draw("วิธีที่เร็วที่สุด · Fastest", x: textX, y: y, size: 11.5, color: ink, bold: true)

let steps = [
    "ดับเบิลคลิกไฟล์คู่มือด้านล่าง  Open the guide below",
    "กดปุ่ม Copy แล้ววางใน Terminal  Copy, paste in Terminal"
]
y -= 25
for (index, text) in steps.enumerated() {
    let bulletRect = NSRect(x: textX, y: y - 2, width: 18, height: 18)
    ink.setFill()
    NSBezierPath(ovalIn: bulletRect).fill()
    draw("\(index + 1)", x: bulletRect.minX + 6, y: bulletRect.minY + 2.5, size: 10, color: .white, bold: true)
    draw(text, x: textX + 28, y: y, size: 11, color: ink)
    y -= 24
}

y -= 8
draw("ไม่อยากใช้ Terminal? System Settings → Privacy & Security → Open Anyway", x: textX, y: y, size: 10, color: inkSoft)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to render background image\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
