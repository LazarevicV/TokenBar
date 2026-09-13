import AppKit
import SwiftUI
import TokenBarCore

/// Provider mark for a section header: a tinted template glyph from the app's resources,
/// falling back to the display name when the image is missing.
struct ProviderGlyph: View {
    var id: ProviderID
    var displayName: String
    var height: CGFloat = 18

    var body: some View {
        Group {
            if let image = Self.image(for: id) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: height)
                    .foregroundStyle(Self.tint(for: id))
            } else {
                Text(displayName).font(.headline)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayName)
        .help(displayName)
    }

    /// Claude's mark in its brand orange; every other provider adapts to the label colour.
    static func tint(for id: ProviderID) -> Color {
        id == .claude ? Color(red: 0.85, green: 0.45, blue: 0.30) : .primary
    }

    private static let cache = NSCache<NSString, NSImage>()

    /// A copy of the glyph pre-sized for the status bar. `MenuBarExtra` labels ignore SwiftUI
    /// frames and draw the `NSImage` at its own point size, so the size must live on the image.
    static func menuBarImage(for id: ProviderID, pointSize: CGFloat = 15) -> NSImage? {
        let key = "\(id.rawValue)-menubar-\(Int(pointSize))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let base = image(for: id), let copy = base.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: pointSize, height: pointSize)
        copy.isTemplate = true
        cache.setObject(copy, forKey: key)
        return copy
    }

    /// White-on-transparent PNG (`<provider>-glyph.png`) marked as a template so SwiftUI can tint it.
    static func image(for id: ProviderID) -> NSImage? {
        let name = "\(id.rawValue)-glyph"
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

struct ProviderGlyph_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 24) {
            ProviderGlyph(id: .claude, displayName: "Claude")
            ProviderGlyph(id: .codex, displayName: "Codex")
        }
        .padding()
        .previewDisplayName("Provider glyphs")
    }
}
