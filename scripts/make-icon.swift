// Renders the Neorar app icon (1024×1024 PNG): a glass tile split by a zipper that runs edge to edge
// and opens at the bottom, letting light out — the archive being unzipped.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit
import SwiftUI

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"
let space = CGColorSpace(name: CGColorSpace.displayP3)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
    ])!
}

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { color($0.0, $0.1) } as CFArray, locations: stops.map(\.2))!
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    Path(roundedRect: rect, cornerRadius: radius, style: .continuous).cgPath
}

func polygon(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    return path
}

/// Fills `path` with a gradient running from `start` to `end`.
func fill(_ c: CGContext, _ path: CGPath, _ g: CGGradient, _ start: CGPoint, _ end: CGPoint, evenOdd: Bool = false) {
    c.saveGState()
    c.addPath(path)
    if evenOdd { c.clip(using: .evenOdd) } else { c.clip() }
    c.drawLinearGradient(g, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}

/// Strokes `path` with a gradient (used for specular rims).
func strokeGradient(_ c: CGContext, _ path: CGPath, width: CGFloat, _ g: CGGradient, _ start: CGPoint, _ end: CGPoint) {
    c.saveGState()
    c.addPath(path)
    c.setLineWidth(width)
    c.replacePathWithStrokedPath()
    c.clip()
    c.drawLinearGradient(g, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}

/// A single glass zipper tooth centred at the origin of the current transform.
func tooth(_ c: CGContext, width: CGFloat, height: CGFloat) {
    let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    let path = rounded(rect, height * 0.42)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -5), blur: 9, color: color(0x10141C, 0.5))
    c.addPath(path)
    c.setFillColor(color(0xFFFFFF))
    c.fillPath()
    c.restoreGState()
    fill(c, path, gradient([(0xFFFFFF, 1, 0), (0xE6EBF1, 1, 0.45), (0x98A3B3, 1, 1)]),
         CGPoint(x: 0, y: rect.minY), CGPoint(x: 0, y: rect.maxY))
    // Specular line along the top of the tooth.
    c.addPath(rounded(CGRect(x: rect.minX + width * 0.14, y: rect.minY + height * 0.16,
                             width: width * 0.72, height: height * 0.24), height * 0.12))
    c.setFillColor(color(0xFFFFFF, 0.9))
    c.fillPath()
}

let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
    guard let c = NSGraphicsContext.current?.cgContext else { return false }

    // macOS icon grid: 824 pt squircle centred on the 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = rounded(tile, 186)
    let mid: CGFloat = 512
    let apex = CGPoint(x: mid, y: 520)                 // where the zipper starts to open
    let leftFoot = CGPoint(x: 236, y: 970)             // the V reaches past the bottom edge
    let rightFoot = CGPoint(x: 788, y: 970)

    // Ground shadow.
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -16), blur: 36, color: color(0x140A04, 0.45))
    c.addPath(tilePath)
    c.setFillColor(color(0x2A1A10))
    c.fillPath()
    c.restoreGState()

    c.saveGState()
    c.addPath(tilePath)
    c.clip()

    // Light pouring out of the opening (drawn first; the panels cover the rest).
    c.setFillColor(color(0xF0428F))
    c.fill(tile)
    c.drawRadialGradient(
        gradient([(0xFFFFFF, 1, 0), (0xFFFBEA, 1, 0.2), (0xFFE27A, 1, 0.42), (0xFF8DB8, 1, 0.7), (0xF0428F, 1, 1)]),
        startCenter: CGPoint(x: mid, y: 880), startRadius: 0,
        endCenter: CGPoint(x: mid, y: 880), endRadius: 430, options: [])
    // Soft rays.
    for (angle, alpha) in [(-0.34, 0.16), (-0.12, 0.22), (0.1, 0.2), (0.3, 0.14)] as [(CGFloat, CGFloat)] {
        c.saveGState()
        c.translateBy(x: mid, y: 940)
        c.rotate(by: angle)
        c.addPath(polygon([CGPoint(x: -14, y: 0), CGPoint(x: 14, y: 0), CGPoint(x: 46, y: -380), CGPoint(x: -46, y: -380)]))
        c.setFillColor(color(0xFFFFFF, alpha))
        c.fillPath()
        c.restoreGState()
    }

    // Two glass panels meeting at the seam.
    let leftPanel = polygon([CGPoint(x: 60, y: 60), CGPoint(x: mid, y: 60), apex, leftFoot, CGPoint(x: 60, y: 980)])
    let rightPanel = polygon([CGPoint(x: mid, y: 60), CGPoint(x: 980, y: 60), CGPoint(x: 980, y: 980), rightFoot, apex])
    // Three stacked "books" (WinRAR's idea) in a vivid, harmonious palette: pink, amber, blue-violet.
    let books: [(CGFloat, CGFloat, UInt32, UInt32)] = [
        (60, 372, 0xFF5C9E, 0xE81C7E),
        (372, 668, 0xFFC93C, 0xFF7A18),
        (668, 980, 0x4F8BFF, 0x5B2BE8),
    ]
    for panel in [leftPanel, rightPanel] {
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -6), blur: 22, color: color(0x0A0410, 0.65))
        c.addPath(panel)
        c.setFillColor(color(0x3A1E5C))
        c.fillPath()
        c.restoreGState()
        c.saveGState()
        c.addPath(panel)
        c.clip()
        for (top, bottom, light, dark) in books {
            c.saveGState()
            c.clip(to: CGRect(x: 0, y: top, width: size, height: bottom - top))
            c.drawLinearGradient(gradient([(light, 1, 0), (dark, 1, 1)]),
                                 start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [])
            c.restoreGState()
            // Book edges: a lit top line and a dark seam below.
            c.setFillColor(color(0xFFFFFF, 0.35))
            c.fill(CGRect(x: 0, y: top + 2, width: size, height: 5))
            c.setFillColor(color(0x000000, 0.16))
            c.fill(CGRect(x: 0, y: bottom - 5, width: size, height: 5))
        }
        // Glass sheen across the stack.
        c.drawLinearGradient(gradient([(0xFFFFFF, 0.26, 0), (0xFFFFFF, 0.05, 0.45), (0xFFFFFF, 0, 1)]),
                             start: CGPoint(x: 160, y: 120), end: CGPoint(x: 520, y: 640), options: [])
        c.restoreGState()
    }

    // Graphite zipper tape under the metal teeth, with fine stitching.
    func strap(from start: CGPoint, to end: CGPoint, width: CGFloat) {
        let line = CGMutablePath()
        line.move(to: start)
        line.addLine(to: end)
        let band = line.copy(strokingWithWidth: width, lineCap: .butt, lineJoin: .round, miterLimit: 10)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: color(0x1A0A02, 0.5))
        c.addPath(band)
        c.setFillColor(color(0x2B303B))
        c.fillPath()
        c.restoreGState()
        let dx = end.x - start.x, dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        let nx = -dy / length, ny = dx / length
        fill(c, band, gradient([(0x1C2029, 1, 0), (0x454C5B, 1, 0.5), (0x1C2029, 1, 1)]),
             CGPoint(x: start.x - nx * width / 2, y: start.y - ny * width / 2),
             CGPoint(x: start.x + nx * width / 2, y: start.y + ny * width / 2))
        for side in [CGFloat(-1), 1] {
            let offset = side * (width / 2 - 12)
            let stitch = CGMutablePath()
            stitch.move(to: CGPoint(x: start.x + nx * offset, y: start.y + ny * offset))
            stitch.addLine(to: CGPoint(x: end.x + nx * offset, y: end.y + ny * offset))
            c.saveGState()
            c.addPath(stitch)
            c.setLineWidth(4)
            c.setLineDash(phase: 0, lengths: [14, 10])
            c.setStrokeColor(color(0xFFFFFF, 0.35))
            c.strokePath()
            c.restoreGState()
        }
    }
    strap(from: CGPoint(x: mid, y: 60), to: CGPoint(x: mid, y: apex.y + 20), width: 150)
    for foot in [leftFoot, rightFoot] {
        let dx = foot.x - apex.x, dy = foot.y - apex.y
        let length = (dx * dx + dy * dy).squareRoot()
        let side: CGFloat = foot.x < mid ? -1 : 1
        // Each open half of the strap sits just outside the opening.
        let shift = CGPoint(x: dy / length * 34 * -side * -1, y: -dx / length * 34 * -side * -1)
        strap(from: CGPoint(x: apex.x + shift.x, y: apex.y + shift.y),
              to: CGPoint(x: foot.x + shift.x, y: foot.y + shift.y), width: 76)
    }

    // Glass edges of the opening catch the light.
    for foot in [leftFoot, rightFoot] {
        let edge = CGMutablePath()
        edge.move(to: apex)
        edge.addLine(to: foot)
        c.saveGState()
        c.addPath(edge)
        c.setLineWidth(4)
        c.setStrokeColor(color(0xFFFFFF, 0.55))
        c.strokePath()
        c.restoreGState()
    }

    // Closed teeth, interlocking from the very top edge down to the slider.
    var y: CGFloat = 92
    var left = true
    while y < 420 {
        c.saveGState()
        c.translateBy(x: left ? mid - 24 : mid + 24, y: y)
        tooth(c, width: 78, height: 30)
        c.restoreGState()
        left.toggle()
        y += 30
    }

    // Open teeth along both edges of the V, all the way to the bottom edge.
    for (foot, side) in [(leftFoot, CGFloat(1)), (rightFoot, CGFloat(-1))] {
        let dx = foot.x - apex.x, dy = foot.y - apex.y
        let length = (dx * dx + dy * dy).squareRoot()
        let ux = dx / length, uy = dy / length
        let angle = atan2(uy, ux) + .pi / 2
        var t: CGFloat = 70
        while t < length {
            // Sit on the panel edge, poking slightly into the opening.
            let x = apex.x + ux * t + uy * 14 * side
            let ty = apex.y + uy * t - ux * 14 * side
            c.saveGState()
            c.translateBy(x: x, y: ty)
            c.rotate(by: angle)
            tooth(c, width: 62, height: 28)
            c.restoreGState()
            t += 60
        }
    }

    // Sparkles in the light.
    for (point, radius) in [(CGPoint(x: 452, y: 760), CGFloat(18)), (CGPoint(x: 560, y: 690), 12), (CGPoint(x: 600, y: 850), 9), (CGPoint(x: 400, y: 880), 8)] {
        let star = CGMutablePath()
        star.move(to: CGPoint(x: point.x, y: point.y - radius))
        star.addQuadCurve(to: CGPoint(x: point.x + radius, y: point.y), control: point)
        star.addQuadCurve(to: CGPoint(x: point.x, y: point.y + radius), control: point)
        star.addQuadCurve(to: CGPoint(x: point.x - radius, y: point.y), control: point)
        star.addQuadCurve(to: CGPoint(x: point.x, y: point.y - radius), control: point)
        c.addPath(star)
        c.setFillColor(color(0xFFFFFF, 0.95))
        c.fillPath()
    }

    // Slider (zipper head) in thick glass.
    let slider = CGMutablePath()
    slider.addPath(rounded(CGRect(x: 418, y: 378, width: 188, height: 96), 40))
    slider.addPath(polygon([CGPoint(x: 432, y: 448), CGPoint(x: 592, y: 448), CGPoint(x: 560, y: 558), CGPoint(x: 464, y: 558)]))
    let sliderShape = slider.copy(strokingWithWidth: 18, lineCap: .round, lineJoin: .round, miterLimit: 10).union(slider)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -14), blur: 26, color: color(0x0E1118, 0.55))
    c.addPath(sliderShape)
    c.setFillColor(color(0xFFFFFF))
    c.fillPath()
    c.restoreGState()
    fill(c, sliderShape, gradient([(0xFFFFFF, 1, 0), (0xEEF1F5, 1, 0.3), (0xB8C1CD, 1, 0.72), (0x7C8797, 1, 1)]),
         CGPoint(x: mid, y: 368), CGPoint(x: mid, y: 568))
    c.addPath(rounded(CGRect(x: 440, y: 386, width: 144, height: 26), 13))
    c.setFillColor(color(0xFFFFFF, 0.95))
    c.fillPath()
    strokeGradient(c, sliderShape, width: 5, gradient([(0xFFFFFF, 1, 0), (0xFFFFFF, 0.2, 0.6), (0xFFFFFF, 0.6, 1)]),
                   CGPoint(x: 420, y: 368), CGPoint(x: 600, y: 568))

    // Pull tab hanging from the slider, slightly swung, with the Neorar "N" and a light-through hole.
    c.saveGState()
    c.translateBy(x: mid, y: 510)
    c.rotate(by: -0.36) // swung aside so the light shows
    let tab = CGMutablePath()
    tab.addPath(rounded(CGRect(x: -66, y: 10, width: 132, height: 272), 62))
    tab.addPath(rounded(CGRect(x: -26, y: 196, width: 52, height: 62), 24))
    c.saveGState()
    c.setShadow(offset: CGSize(width: 6, height: -16), blur: 26, color: color(0x0E1118, 0.55))
    c.addPath(tab)
    c.setFillColor(color(0xFFFFFF))
    c.fillPath(using: .evenOdd)
    c.restoreGState()
    fill(c, tab, gradient([(0xFFFFFF, 1, 0), (0xEDF0F4, 1, 0.38), (0xB5BECA, 1, 0.8), (0x7A8595, 1, 1)]),
         CGPoint(x: -60, y: 10), CGPoint(x: 60, y: 282), evenOdd: true)
    // Gloss on the left edge of the tab.
    c.addPath(rounded(CGRect(x: -50, y: 30, width: 26, height: 150), 13))
    c.setFillColor(color(0xFFFFFF, 0.85))
    c.fillPath()
    strokeGradient(c, tab, width: 5, gradient([(0xFFFFFF, 1, 0), (0xFFFFFF, 0.25, 0.6), (0xFFFFFF, 0.7, 1)]),
                   CGPoint(x: -60, y: 10), CGPoint(x: 60, y: 282))
    // Hinge ring.
    c.addPath(rounded(CGRect(x: -24, y: -6, width: 48, height: 40), 18))
    c.setLineWidth(10)
    c.setStrokeColor(color(0xCDD4DE))
    c.strokePath()

    // Engraved "N": violet-to-cyan, like light caught inside the glass.
    let base = NSFont.systemFont(ofSize: 120, weight: .black)
    let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: 120) ?? base
    var glyph = CGGlyph()
    var character = UniChar(("N" as String).utf16.first!)
    CTFontGetGlyphsForCharacters(font as CTFont, &character, &glyph, 1)
    if let glyphPath = CTFontCreatePathForGlyph(font as CTFont, glyph, nil) {
        let box = glyphPath.boundingBox
        var flip = CGAffineTransform(translationX: -box.midX, y: 112 + box.height / 2).scaledBy(x: 1, y: -1)
        if let letter = glyphPath.copy(using: &flip) {
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: -2), blur: 1.5, color: color(0xFFFFFF, 0.9))
            c.addPath(letter)
            c.setFillColor(color(0xE8327E))
            c.fillPath()
            c.restoreGState()
            fill(c, letter, gradient([(0xFF4E91, 1, 0), (0xFF8A3D, 1, 0.5), (0x5B5BFF, 1, 1)]),
                 CGPoint(x: 0, y: 112 - box.height / 2), CGPoint(x: 0, y: 112 + box.height / 2))
        }
    }
    c.restoreGState()

    // Whole-tile glass: top gloss, bottom depth.
    c.drawLinearGradient(gradient([(0xFFFFFF, 0.22, 0), (0xFFFFFF, 0, 0.32)]),
                         start: CGPoint(x: mid, y: 100), end: CGPoint(x: mid, y: 924), options: [])
    c.drawLinearGradient(gradient([(0x000000, 0, 0.72), (0x000000, 0.22, 1)]),
                         start: CGPoint(x: mid, y: 100), end: CGPoint(x: mid, y: 924), options: [])
    c.restoreGState()

    // Specular rim around the tile.
    strokeGradient(c, rounded(tile.insetBy(dx: 3, dy: 3), 183), width: 6,
                   gradient([(0xFFFFFF, 0.95, 0), (0xFFFFFF, 0.15, 0.45), (0xFFFFFF, 0.08, 0.7), (0xFFFFFF, 0.5, 1)]),
                   CGPoint(x: 130, y: 110), CGPoint(x: 900, y: 920))
    return true
}

guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Não foi possível gerar o PNG")
}
try png.write(to: URL(fileURLWithPath: output))
print("Ícone salvo em \(output)")
