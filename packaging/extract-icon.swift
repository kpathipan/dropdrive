import AppKit
import CoreGraphics

let src = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]
let outSize = CGFloat(Double(CommandLine.arguments[3]) ?? 1024)

guard let data = try? Data(contentsOf: URL(fileURLWithPath: src)),
      let rep = NSBitmapImageRep(data: data),
      let cg = rep.cgImage else {
    fputs("load failed\n", stderr); exit(1)
}

// Detected squircle bounds in source pixels (top-left origin)
let cropRect = CGRect(x: 184, y: 101, width: 266, height: 266)
guard let cropped = cg.cropping(to: cropRect) else { fputs("crop failed\n", stderr); exit(1) }

let px = Int(outSize)
guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fputs("ctx failed\n", stderr); exit(1)
}
ctx.interpolationQuality = CGInterpolationQuality.high
ctx.clear(CGRect(x: 0, y: 0, width: px, height: px))

// Rounded-rect (squircle-ish) clip matching the icon's own corner radius (~22.5%)
let radius = outSize * 0.225
let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: outSize, height: outSize),
                  cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(path)
ctx.clip()
ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: outSize, height: outSize))

guard let outImg = ctx.makeImage() else { fputs("makeImage failed\n", stderr); exit(1) }
let outRep = NSBitmapImageRep(cgImage: outImg)
guard let png = outRep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { fputs("png failed\n", stderr); exit(1) }
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) @ \(px)px")
