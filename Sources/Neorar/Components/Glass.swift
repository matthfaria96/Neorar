import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Thin progress capsule with a glass track.
struct GlassProgressBar: View {
    let value: Double
    var tint: Color = .accentColor
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(height, proxy.size.width * min(1, max(0, value))))
                    .animation(.smooth(duration: 0.25), value: value)
            }
        }
        .frame(height: height)
    }
}

/// Finder icon for a file on disk or for a name inside an archive, cached by type.
struct FileIcon: View {
    let image: NSImage
    var size: CGFloat = 32

    init(url: URL, size: CGFloat = 32) {
        image = IconCache.icon(forFile: url)
        self.size = size
    }

    init(name: String, isDirectory: Bool, size: CGFloat = 18) {
        image = IconCache.icon(forName: name, isDirectory: isDirectory)
        self.size = size
    }

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

enum IconCache {
    private static var byType: [String: NSImage] = [:]

    static func icon(forFile url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    static func icon(forName name: String, isDirectory: Bool) -> NSImage {
        let ext = isDirectory ? "/folder" : (name as NSString).pathExtension.lowercased()
        if let cached = byType[ext] { return cached }
        let type: UTType = isDirectory ? .folder : (UTType(filenameExtension: ext) ?? .data)
        let image = NSWorkspace.shared.icon(for: type)
        byType[ext] = image
        return image
    }
}

enum Format {
    static func bytes<T: BinaryInteger>(_ value: T) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        bytes(UInt64(max(0, bytesPerSecond))) + "/s"
    }

    static func date(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "—"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return String(localized: "menos de 1 s") }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(1, seconds)) ?? ""
    }
}
