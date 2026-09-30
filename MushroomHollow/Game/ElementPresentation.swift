import GameCore
import SwiftUI
import UIKit

/// Client-only looks for the five elements: colors, symbols, and the little tile icon (Flyff's
/// element badges) shown on the target frame, nameplates, and item details.
extension Element {
    /// The element's color, for icons, text, and weapon effects.
    var tint: UIColor {
        switch self {
        case .fire: UIColor(red: 0.95, green: 0.33, blue: 0.2, alpha: 1)
        case .wind: UIColor(red: 0.3, green: 0.8, blue: 0.68, alpha: 1)
        case .earth: UIColor(red: 0.72, green: 0.52, blue: 0.3, alpha: 1)
        case .electric: UIColor(red: 0.98, green: 0.8, blue: 0.18, alpha: 1)
        case .water: UIColor(red: 0.32, green: 0.56, blue: 0.98, alpha: 1)
        }
    }

    var color: Color { Color(uiColor: tint) }

    /// SF Symbol drawn on the tile.
    var symbol: String {
        switch self {
        case .fire: "flame.fill"
        case .wind: "tornado"
        case .earth: "mountain.2.fill"
        case .electric: "bolt.fill"
        case .water: "drop.fill"
        }
    }

    /// The element's tile: a rounded square in its color with a white symbol and a dark rim.
    /// Cached per size (points).
    func icon(size: CGFloat = 40) -> UIImage {
        let key = "\(rawValue)-\(Int(size))"
        if let cached = ElementIconCache.images[key] { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            let rim = size * 0.07
            let rect = CGRect(x: rim / 2, y: rim / 2, width: size - rim, height: size - rim)
            let tile = UIBezierPath(roundedRect: rect, cornerRadius: size * 0.2)
            let cg = context.cgContext
            // Lighter at the top, like Flyff's glassy element tiles.
            cg.saveGState()
            tile.addClip()
            let colors = [tint.towardWhite(0.35).cgColor, tint.cgColor, tint.darker(0.75).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])
            }
            cg.restoreGState()
            UIColor(white: 0.08, alpha: 1).setStroke()
            tile.lineWidth = rim
            tile.stroke()
            let config = UIImage.SymbolConfiguration(pointSize: size * 0.5, weight: .bold)
            if let glyph = UIImage(systemName: symbol, withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                let fit = min(size * 0.6 / glyph.size.width, size * 0.6 / glyph.size.height)
                let glyphSize = CGSize(width: glyph.size.width * fit, height: glyph.size.height * fit)
                glyph.draw(in: CGRect(x: (size - glyphSize.width) / 2, y: (size - glyphSize.height) / 2,
                                      width: glyphSize.width, height: glyphSize.height))
            }
        }
        ElementIconCache.images[key] = image
        return image
    }
}

private extension UIColor {
    /// Blended `amount` of the way to white.
    func towardWhite(_ amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r + (1 - r) * amount, green: g + (1 - g) * amount, blue: b + (1 - b) * amount, alpha: a)
    }
}

private enum ElementIconCache {
    static var images: [String: UIImage] = [:]
}

extension ElementUpgrade {
    /// "Fire +3".
    var label: String { "\(element.displayName) +\(level)" }
}

extension ElementMatchup {
    /// How your weapon's element fares against a target, for the target frame; nil when it doesn't matter.
    var hint: (text: String, symbol: String, color: Color)? {
        switch self {
        case .strong: ("Strong", "arrow.up", .green)
        case .weak: ("Weak", "arrow.down", .red)
        case .same: ("Resists", "equal", .secondary)
        case .neutral: nil
        }
    }
}

/// An element's tile as a SwiftUI view.
struct ElementBadge: View {
    let element: Element
    var size: CGFloat = 18

    var body: some View {
        Image(uiImage: element.icon(size: 40))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityLabel("\(element.displayName) element")
    }
}
