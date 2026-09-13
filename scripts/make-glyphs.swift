// Crops the provider marks out of the logo and converts them to white template
// PNGs (alpha = brightness) so SwiftUI can tint them.
// Usage: swift scripts/make-glyphs.swift <logo.png> <out-dir>
import AppKit
let a = CommandLine.arguments
let src = NSImage(contentsOfFile: a[1])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let out = a[2]
let crops: [(String, CGRect)] = [
    ("claude-glyph", CGRect(x: 385, y: 345, width: 220, height: 220)),
    ("codex-glyph",  CGRect(x: 640, y: 350, width: 230, height: 230)),
]
for (name, rect) in crops {
    // CGImage.cropping uses top-left origin like the pixel grid.
    let c = src.cropping(to: rect)!
    let w = c.width, h = c.height
    var raw = [UInt8](repeating: 0, count: w*h*4)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: &raw, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(c, in: CGRect(x: 0, y: 0, width: w, height: h))
    var outPx = [UInt8](repeating: 0, count: w*h*4)
    for i in stride(from: 0, to: w*h*4, by: 4) {
        let lum = max(Int(raw[i]), Int(raw[i+1]), Int(raw[i+2]))
        let alpha = UInt8(min(255, max(0, (lum - 40) * 255 / 160)))   // black bg -> 0, mark -> 255
        outPx[i] = alpha; outPx[i+1] = alpha; outPx[i+2] = alpha; outPx[i+3] = alpha  // premultiplied white
    }
    let octx = CGContext(data: &outPx, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4, space: cs,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let img = octx.makeImage()!
    // downscale to 96 px for the bundle
    let size = 96
    let sctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    sctx.interpolationQuality = .high
    sctx.draw(img, in: CGRect(x: 0, y: 0, width: size, height: size))
    let data = NSBitmapImageRep(cgImage: sctx.makeImage()!).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
print("ok")
