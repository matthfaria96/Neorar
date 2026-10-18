import SwiftUI

/// Neorar's own action icons: flat-vector illustrations drawn in a 32×32 grid,
/// each with its own colour family so the main bar reads at a glance.
nonisolated enum RibbonGlyph: Sendable {
    case compress, extractTo, extractHere, delete, preview, test, info
}

struct RibbonGlyphView: View {
    let glyph: RibbonGlyph
    var size: CGFloat = 30
    var glass = false

    var body: some View {
        ZStack {
            if glass { GlassBase(glyph: glyph, size: size) }
            symbols
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var symbols: some View {
        Canvas { context, canvas in
            let scale = min(canvas.width, canvas.height) / 32
            context.scaleBy(x: scale, y: scale)
            var shadowed = context
            switch glyph {
            case .compress: Self.compress(&shadowed, glass)
            case .extractTo: Self.extractTo(&shadowed, glass)
            case .extractHere: Self.extractHere(&shadowed, glass)
            case .delete: Self.delete(&shadowed, glass)
            case .preview: Self.preview(&shadowed, glass)
            case .test: Self.test(&shadowed, glass)
            case .info: Self.info(&shadowed, glass)
            }
        }
    }

    // MARK: - Glass base (shared with GlassBase)

    struct Palette { let top: Color; let bottom: Color }

    /// Colour family per action. Main actions are vivid; secondary ones share one calm slate blue.
    static func palette(_ glyph: RibbonGlyph) -> Palette {
        let c = colors(glyph)
        return Palette(top: hex(c.top), bottom: hex(c.bottom))
    }

    nonisolated static func colors(_ glyph: RibbonGlyph) -> (top: UInt32, bottom: UInt32) {
        switch glyph {
        case .compress: (0x62D883, 0x1C8A49)      // green
        case .extractTo: (0xB07CFA, 0x6A2FD2)     // purple
        case .extractHere: (0x55B4FF, 0x1C6DE6)   // blue
        case .delete: (0xFF6B8B, 0xE0244F)        // rose red
        case .preview, .test, .info: (0xA3B4C8, 0x5A6C84) // slate blue-grey
        }
    }

    nonisolated static func isPrimary(_ glyph: RibbonGlyph) -> Bool {
        switch glyph {
        case .compress, .extractTo, .extractHere, .delete: true
        case .preview, .test, .info: false
        }
    }

    /// Base outline in the 32-point grid: soft hexagons for the main actions, circles for the secondary ones.
    nonisolated static func basePath(_ glyph: RibbonGlyph) -> Path {
        if isPrimary(glyph) {
            let hexagon = polygon(sides: 6, radius: 11.6, rotation: -.pi / 2)
            return hexagon.strokedPath(StrokeStyle(lineWidth: 4.4, lineCap: .round, lineJoin: .round)).union(hexagon)
        }
        return circle(16, 16, 13)
    }

    // MARK: - Helpers

    static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255, opacity: alpha)
    }

    private static func linear(_ colors: [UInt32], from start: CGPoint, to end: CGPoint) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors.map { hex($0) }), startPoint: start, endPoint: end)
    }

    private static func vertical(_ top: UInt32, _ bottom: UInt32, _ y0: CGFloat, _ y1: CGFloat) -> GraphicsContext.Shading {
        linear([top, bottom], from: CGPoint(x: 16, y: y0), to: CGPoint(x: 16, y: y1))
    }

    nonisolated private static func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .continuous)
    }

    nonisolated static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    private static let white = GraphicsContext.Shading.color(.white)
    private static func white(_ alpha: Double) -> GraphicsContext.Shading { .color(.white.opacity(alpha)) }

    // MARK: - Style kit
    // Every icon = solid base shape with a one-hue vertical gradient + a pastel, softly embossed symbol
    // of the same hue (optionally with a light badge), like the Big Sur–style utility icon sets.

    private static func base(_ c: inout GraphicsContext, _ glass: Bool, _ shape: Path, top: UInt32, bottom: UInt32) {
        if glass { return } // The glass variant gets its base from the system material.
        var layer = c
        layer.addFilter(.shadow(color: hex(bottom, 0.45), radius: 1.1, x: 0, y: 1))
        layer.fill(shape, with: vertical(top, bottom, 3, 29))
        // Soft top sheen.
        var sheen = c
        sheen.clip(to: shape)
        sheen.fill(Path(CGRect(x: 0, y: 0, width: 32, height: 14)),
                   with: .linearGradient(Gradient(colors: [.white.opacity(0.22), .white.opacity(0)]),
                                         startPoint: CGPoint(x: 16, y: 3), endPoint: CGPoint(x: 16, y: 15)))
    }

    /// Pastel symbol fill with a drop shadow tinted by the base colour.
    private static func pastel(_ c: inout GraphicsContext, _ path: Path, top: UInt32, bottom: UInt32, shadow: UInt32, glass: Bool = false) {
        var layer = c
        layer.addFilter(.shadow(color: hex(shadow, glass ? 0.5 : 0.55), radius: glass ? 1.2 : 0.8, x: 0, y: glass ? 1 : 0.8))
        if glass {
            // Frosted white symbol sitting on the glass.
            layer.fill(path, with: .linearGradient(Gradient(colors: [.white, .white.opacity(0.78)]),
                                                  startPoint: CGPoint(x: 16, y: path.boundingRect.minY),
                                                  endPoint: CGPoint(x: 16, y: path.boundingRect.maxY)))
        } else {
            layer.fill(path, with: vertical(top, bottom, path.boundingRect.minY, path.boundingRect.maxY))
        }
    }

    nonisolated static func polygon(sides: Int, radius: CGFloat, rotation: Double) -> Path {
        var path = Path()
        for i in 0..<sides {
            let angle = rotation + Double(i) * 2 * .pi / Double(sides)
            let point = CGPoint(x: 16 + radius * CGFloat(cos(angle)), y: 16 + radius * CGFloat(sin(angle)))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// Light round badge with a white rim, bottom-right.
    private static func badge(_ c: inout GraphicsContext, center: CGPoint, radius: CGFloat, top: UInt32, bottom: UInt32) {
        var layer = c
        layer.addFilter(.shadow(color: .black.opacity(0.25), radius: 0.9, x: 0, y: 0.8))
        layer.fill(circle(center.x, center.y, radius), with: .color(.white))
        c.fill(circle(center.x, center.y, radius - 1.1), with: vertical(top, bottom, center.y - radius, center.y + radius))
    }

    // MARK: - Glyphs

    /// Base for any glyph: soft hexagon or ringed circle, in the glyph's colour family.
    private static func shape(_ c: inout GraphicsContext, _ g: Bool, _ glyph: RibbonGlyph) {
        let colours = colors(glyph)
        base(&c, g, basePath(glyph), top: colours.top, bottom: colours.bottom)
        if !g, !isPrimary(glyph) {
            c.stroke(circle(16, 16, 11.3), with: .color(.white.opacity(0.32)), lineWidth: 1.2)
        }
    }

    /// Green hexagon, mint archive box with zipper.
    private static func compress(_ c: inout GraphicsContext, _ g: Bool) {
        shape(&c, g, .compress)
        pastel(&c, rounded(9.5, 12.5, 13, 11, 2.3), top: 0xF2FFF5, bottom: 0xBDEFCB, shadow: 0x0C5A2C, glass: g)
        pastel(&c, rounded(8.5, 9.2, 15, 4.4, 1.7), top: 0xFFFFFF, bottom: 0xD4F5DE, shadow: 0x0C5A2C, glass: g)
        c.fill(rounded(15.25, 13.6, 1.5, 6.4, 0.75), with: .color(hex(0x3DB86A)))
        c.fill(rounded(14.3, 18.4, 3.4, 3.9, 1.3), with: vertical(0x34B062, 0x1E8C48, 18.4, 22.3))
        c.fill(rounded(15.4, 19.5, 1.2, 1.5, 0.6), with: .color(hex(0xE6FBEC)))
    }

    /// Purple hexagon, lavender folder, light badge with an outbound arrow.
    private static func extractTo(_ c: inout GraphicsContext, _ g: Bool) {
        shape(&c, g, .extractTo)
        var folder = Path()
        folder.addRoundedRect(in: CGRect(x: 8, y: 10.5, width: 7, height: 4), cornerSize: CGSize(width: 1.2, height: 1.2))
        folder.addRoundedRect(in: CGRect(x: 8, y: 12.5, width: 16, height: 10), cornerSize: CGSize(width: 2, height: 2))
        pastel(&c, folder, top: 0xF6EEFF, bottom: 0xD5BFFF, shadow: 0x3E1A92, glass: g)
        c.fill(rounded(9.2, 13.8, 13.6, 0.9, 0.45), with: white(0.8))
        badge(&c, center: CGPoint(x: 23.2, y: 23.2), radius: 5.4, top: 0xFFFFFF, bottom: 0xE9DCFF)
        var arrow = Path()
        arrow.move(to: CGPoint(x: 21.2, y: 25.2))
        arrow.addLine(to: CGPoint(x: 25, y: 21.4))
        arrow.move(to: CGPoint(x: 22.2, y: 21.2))
        arrow.addLine(to: CGPoint(x: 25.2, y: 21.2))
        arrow.addLine(to: CGPoint(x: 25.2, y: 24.2))
        c.stroke(arrow, with: .color(hex(0x7A3FE0)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    /// Blue hexagon, pale-blue tray receiving an arrow.
    private static func extractHere(_ c: inout GraphicsContext, _ g: Bool) {
        shape(&c, g, .extractHere)
        var tray = Path()
        tray.move(to: CGPoint(x: 8.5, y: 17))
        tray.addLine(to: CGPoint(x: 12, y: 17))
        tray.addLine(to: CGPoint(x: 13.4, y: 19.4))
        tray.addLine(to: CGPoint(x: 18.6, y: 19.4))
        tray.addLine(to: CGPoint(x: 20, y: 17))
        tray.addLine(to: CGPoint(x: 23.5, y: 17))
        tray.addLine(to: CGPoint(x: 23.5, y: 21.8))
        tray.addQuadCurve(to: CGPoint(x: 21.5, y: 23.8), control: CGPoint(x: 23.5, y: 23.8))
        tray.addLine(to: CGPoint(x: 10.5, y: 23.8))
        tray.addQuadCurve(to: CGPoint(x: 8.5, y: 21.8), control: CGPoint(x: 8.5, y: 23.8))
        tray.closeSubpath()
        pastel(&c, tray, top: 0xEEF7FF, bottom: 0xB9D9FF, shadow: 0x0D4CB0, glass: g)
        var arrow = Path()
        arrow.addRoundedRect(in: CGRect(x: 14.4, y: 7.8, width: 3.2, height: 6.2), cornerSize: CGSize(width: 1.2, height: 1.2))
        arrow.move(to: CGPoint(x: 11.3, y: 12.6))
        arrow.addLine(to: CGPoint(x: 20.7, y: 12.6))
        arrow.addLine(to: CGPoint(x: 16, y: 17.6))
        arrow.closeSubpath()
        pastel(&c, arrow, top: 0xFFFFFF, bottom: 0xD6E9FF, shadow: 0x0D4CB0, glass: g)
    }

    /// Rose-red hexagon, blush bin.
    private static func delete(_ c: inout GraphicsContext, _ g: Bool) {
        shape(&c, g, .delete)
        pastel(&c, rounded(9.5, 9.6, 13, 2.5, 1.1), top: 0xFFFFFF, bottom: 0xFFDCE4, shadow: 0x8E1233, glass: g)
        c.stroke(rounded(13.6, 7.8, 4.8, 2.4, 1.1), with: g ? white : .color(hex(0xFFE4EB)), lineWidth: 1.1)
        var body = Path()
        body.move(to: CGPoint(x: 10.5, y: 12.8))
        body.addLine(to: CGPoint(x: 21.5, y: 12.8))
        body.addLine(to: CGPoint(x: 20.5, y: 22.2))
        body.addQuadCurve(to: CGPoint(x: 18.7, y: 24), control: CGPoint(x: 20.4, y: 24))
        body.addLine(to: CGPoint(x: 13.3, y: 24))
        body.addQuadCurve(to: CGPoint(x: 11.5, y: 22.2), control: CGPoint(x: 11.6, y: 24))
        body.closeSubpath()
        pastel(&c, body, top: 0xFFF1F4, bottom: 0xFFC2CE, shadow: 0x8E1233, glass: g)
        var ribs = Path()
        for x in [14.0, 16.0, 18.0] as [CGFloat] {
            ribs.move(to: CGPoint(x: x, y: 15.2))
            ribs.addLine(to: CGPoint(x: x, y: 21.4))
        }
        c.stroke(ribs, with: .color(hex(0xE8405F)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
    }

    /// Slate disc, pale eye.
    private static func preview(_ c: inout GraphicsContext, _ g: Bool) {
        shape(&c, g, .preview)
        var eye = Path()
        eye.move(to: CGPoint(x: 7.5, y: 16))
        eye.addQuadCurve(to: CGPoint(x: 24.5, y: 16), control: CGPoint(x: 16, y: 7.6))
        eye.addQuadCurve(to: CGPoint(x: 7.5, y: 16), control: CGPoint(x: 16, y: 24.4))
        eye.closeSubpath()
        pastel(&c, eye, top: 0xFFFFFF, bottom: 0xDCE4EE, shadow: 0x2B3A4E, glass: g)
        c.fill(circle(16, 16, 3.7), with: vertical(0x7E93AE, 0x4A5C76, 12.3, 19.7))
        c.fill(circle(16, 16, 1.6), with: .color(hex(0x26323F)))
        c.fill(circle(17.3, 14.7, 0.9), with: white)
    }

    /// Slate disc, pale shield with a check.
    private static func test(_ c: inout GraphicsContext, _ g: Bool) {
        shape(&c, g, .test)
        var shield = Path()
        shield.move(to: CGPoint(x: 16, y: 8))
        shield.addLine(to: CGPoint(x: 22.2, y: 10.2))
        shield.addLine(to: CGPoint(x: 22.2, y: 14.6))
        shield.addCurve(to: CGPoint(x: 16, y: 24), control1: CGPoint(x: 22.2, y: 19.2), control2: CGPoint(x: 19, y: 22.4))
        shield.addCurve(to: CGPoint(x: 9.8, y: 14.6), control1: CGPoint(x: 13, y: 22.4), control2: CGPoint(x: 9.8, y: 19.2))
        shield.addLine(to: CGPoint(x: 9.8, y: 10.2))
        shield.closeSubpath()
        pastel(&c, shield, top: 0xFFFFFF, bottom: 0xD8E1EC, shadow: 0x2B3A4E, glass: g)
        var check = Path()
        check.move(to: CGPoint(x: 13.2, y: 16))
        check.addLine(to: CGPoint(x: 15.3, y: 18.1))
        check.addLine(to: CGPoint(x: 19.1, y: 13.6))
        c.stroke(check, with: .color(hex(0x4F627C)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }

    /// Slate disc, pale disc with an "i".
    private static func info(_ c: inout GraphicsContext, _ g: Bool) {
        shape(&c, g, .info)
        pastel(&c, circle(16, 16, 7.8), top: 0xFFFFFF, bottom: 0xD8E1EC, shadow: 0x2B3A4E, glass: g)
        c.fill(circle(16, 12.4, 1.35), with: .color(hex(0x4F627C)))
        c.fill(rounded(14.9, 14.7, 2.2, 6.4, 1.1), with: .color(hex(0x4F627C)))
    }
}

/// Shape that draws a 32-point-grid path scaled into its frame.
nonisolated struct GridShape: Shape {
    let glyph: RibbonGlyph

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 32
        return RibbonGlyphView.basePath(glyph)
            .applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: rect.minX / scale, y: rect.minY / scale))
    }
}

/// Liquid Glass tile: system glass tinted with the action's hue, a specular rim and a soft inner glow.
private struct GlassBase: View {
    let glyph: RibbonGlyph
    let size: CGFloat

    var body: some View {
        let palette = RibbonGlyphView.palette(glyph)
        let shape = GridShape(glyph: glyph)
        ZStack {
            // Saturated colour body under the glass so the hue stays vivid on light and dark bars.
            shape.fill(LinearGradient(colors: [palette.top.opacity(0.95), palette.bottom],
                                      startPoint: .top, endPoint: .bottom))
            Color.clear
                .glassEffect(.clear.tint(palette.top.opacity(0.25)), in: shape)
            // Thick-glass depth: light enters at the top, the bottom edge darkens.
            shape.fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.0), .black.opacity(0.0), .black.opacity(0.18)],
                                      startPoint: .top, endPoint: .bottom))
            // Curved reflection band across the upper half.
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.72, height: size * 0.34)
                .offset(y: -size * 0.24)
                .blur(radius: size * 0.02)
                .mask(shape)
            // Specular rim: bright top-left edge fading to a faint lower edge.
            shape.stroke(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.15), .white.opacity(0.45)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing),
                         lineWidth: max(1, size / 36))
        }
        .compositingGroup()
        .shadow(color: palette.bottom.opacity(0.35), radius: size / 14, y: size / 22)
    }
}
