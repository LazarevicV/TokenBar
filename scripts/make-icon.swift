// Generates an .iconset from assets/tokenbar-logo-app-icon.png.
// Finds the non-black tile in the source, scales it to the macOS icon grid
// (824 pt tile centred on a 1024 pt transparent canvas) and masks it with a
// rounded rect (radius = 22.37% of the tile) like every other Mac app icon.
// Usage: swift scripts/make-icon.swift <source.png> <out.iconset>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let src = NSImage(contentsOfFile: args[1]),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("usage: make-icon.swift <source.png> <out.iconset>\n", stderr); exit(1)
}
let outDir = args[2]

// 1. Bounding box of "not near-black" pixels = the drawn tile.
let w = cg.width, h = cg.height
var raw = [UInt8](repeating: 0, count: w * h * 4)
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: &raw, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h { for x in 0..<w {
    let i = (y * w + x) * 4
    if Int(raw[i]) + Int(raw[i+1]) + Int(raw[i+2]) > 60 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}}
let side = max(maxX - minX, maxY - minY) + 1
let cropRect = CGRect(x: minX, y: minY, width: side, height: side)
fputs("tile bounds: \(cropRect)\n", stderr)
let tile = cg.cropping(to: cropRect)!

// 2. Render the masked tile into a transparent canvas at each size.
func render(_ canvas: Int) -> CGImage {
    let c = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let tileSide = CGFloat(canvas) * 824.0 / 1024.0
    let inset = (CGFloat(canvas) - tileSide) / 2
    let rect = CGRect(x: inset, y: inset, width: tileSide, height: tileSide)
    let radius = tileSide * 0.2237
    c.setAllowsAntialiasing(true)
    c.interpolationQuality = .high
    c.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    c.clip()
    c.draw(tile, in: rect)
    return c.makeImage()!
}
func write(_ img: CGImage, _ name: String) {
    let data = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (pts, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    write(render(pts * scale), scale == 1 ? "icon_\(pts)x\(pts).png" : "icon_\(pts)x\(pts)@2x.png")
}
print("wrote iconset to \(outDir)")
