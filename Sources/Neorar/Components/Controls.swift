import AppKit
import QuickLookThumbnailing
import SwiftUI

/// Large, colourful toolbar button in the spirit of WinRAR's main bar, with native hover/press feedback.
struct RibbonButton: View {
    let title: String
    let glyph: RibbonGlyph
    var help: String?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @AppStorage(PrefKey.iconStyle) private var iconStyle = IconStyle.color.rawValue
    @State private var hovering = false
    @State private var bounce = 0

    var body: some View {
        Button {
            bounce += 1
            action()
        } label: {
            VStack(spacing: 4) {
                RibbonGlyphView(glyph: glyph, size: 56, glass: iconStyle == IconStyle.glass.rawValue)
                    .saturation(isEnabled ? 1 : 0)
                    .opacity(isEnabled ? 1 : 0.5)
                    .scaleEffect(hovering && isEnabled ? 1.07 : 1)
                    .offset(y: hovering && isEnabled ? -1 : 0)
                    .keyframeAnimator(initialValue: 1.0, trigger: bounce) { view, scale in
                        view.scaleEffect(scale)
                    } keyframes: { _ in
                        SpringKeyframe(0.86, duration: 0.09)
                        SpringKeyframe(1.08, duration: 0.16)
                        SpringKeyframe(1.0, duration: 0.2)
                    }
                    .frame(height: 56)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 62)
            .padding(.horizontal, 3)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .opacity(hovering && isEnabled ? 1 : 0)
            }
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(RibbonPressStyle())
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
        .help(help ?? title)
        .animation(.smooth(duration: 0.2), value: isEnabled)
    }
}

private struct RibbonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(duration: 0.18, bounce: 0.4), value: configuration.isPressed)
    }
}

/// Quick Look thumbnail with the Finder icon as placeholder.
struct ThumbnailView: View {
    let url: URL
    var size: CGFloat = 64

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            } else {
                Image(nsImage: IconCache.icon(forFile: url)).resizable().interpolation(.high)
            }
        }
        .frame(width: size, height: size)
        .task(id: url) { image = await Thumbnails.image(for: url, size: size) }
    }
}

enum Thumbnails {
    private static let cache = NSCache<NSURL, NSImage>()

    static func image(for url: URL, size: CGFloat) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: size, height: size),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = representation.nsImage
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// One cell of the icon grid (folders and archives share it).
struct GridCell<Icon: View>: View {
    let title: String
    let subtitle: String?
    let selected: Bool
    @ViewBuilder var icon: Icon

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            icon
                .frame(width: 64, height: 64)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(selected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)))
            Text(title)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(selected ? Color.accentColor : .clear))
                .foregroundStyle(selected ? Color.white : .primary)
            if let subtitle {
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 112)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quinary).opacity(hovering && !selected ? 1 : 0))
        .contentShape(.rect(cornerRadius: 10))
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
        .animation(.smooth(duration: 0.15), value: selected)
    }
}
