import Foundation

/// Detects the legacy code page used for ZIP entry names that lack the UTF-8 flag
/// (archives made on Windows in Japanese, Chinese, Cyrillic… locales).
public enum ZipEncodingDetector {
    public struct Choice: Hashable, Identifiable, Sendable {
        public let codePage: Int
        public let name: String
        public var id: Int { codePage }
    }

    public static let choices: [Choice] = [
        Choice(codePage: 65001, name: String(localized: "Unicode (UTF-8)")),
        Choice(codePage: 437, name: String(localized: "DOS Latino EUA (CP437)")),
        Choice(codePage: 850, name: String(localized: "DOS Europa Ocidental (CP850)")),
        Choice(codePage: 1252, name: String(localized: "Windows Latino 1 (1252)")),
        Choice(codePage: 932, name: String(localized: "Japonês (Shift JIS)")),
        Choice(codePage: 936, name: String(localized: "Chinês simplificado (GBK)")),
        Choice(codePage: 950, name: String(localized: "Chinês tradicional (Big5)")),
        Choice(codePage: 949, name: String(localized: "Coreano (EUC-KR)")),
        Choice(codePage: 866, name: String(localized: "Cirílico DOS (CP866)")),
        Choice(codePage: 1251, name: String(localized: "Cirílico Windows (1251)")),
        Choice(codePage: 1253, name: String(localized: "Grego Windows (1253)")),
        Choice(codePage: 1254, name: String(localized: "Turco Windows (1254)")),
        Choice(codePage: 1255, name: String(localized: "Hebraico Windows (1255)")),
        Choice(codePage: 1256, name: String(localized: "Árabe Windows (1256)")),
        Choice(codePage: 874, name: String(localized: "Tailandês (874)")),
    ]

    /// Returns a code page for 7-Zip's `-mcp=` switch, or nil when names are already Unicode/ASCII.
    public static func detect(_ archive: URL) -> Int? {
        let names = rawLegacyNames(archive)
        guard !names.isEmpty else { return nil }
        let joined = names.reduce(into: Data()) { $0.append($1); $0.append(0x0A) }
        if String(data: joined, encoding: .utf8) != nil { return 65001 }

        let candidates: [String.Encoding] = [932, 936, 950, 949, 866, 1251, 437, 1252].compactMap { page in
            let cf = CFStringConvertWindowsCodepageToEncoding(UInt32(page))
            guard cf != kCFStringEncodingInvalidId else { return nil }
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        }
        var converted: NSString?
        var lossy = ObjCBool(false)
        let detected = NSString.stringEncoding(
            for: joined,
            encodingOptions: [
                .suggestedEncodingsKey: candidates.map(\.rawValue),
                .useOnlySuggestedEncodingsKey: true,
                .allowLossyKey: false,
            ],
            convertedString: &converted,
            usedLossyConversion: &lossy
        )
        guard detected != 0 else { return nil }
        let cf = CFStringConvertNSStringEncodingToEncoding(detected)
        let page = Int(CFStringConvertEncodingToWindowsCodepage(cf))
        return page > 0 ? page : nil
    }

    /// Reads raw names from the central directory that carry high bytes but no UTF-8 flag.
    static func rawLegacyNames(_ archive: URL, limit: Int = 4000) -> [Data] {
        guard let handle = try? FileHandle(forReadingFrom: archive) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size >= 22 else { return [] }

        let tailLength = min(size, 65_557)
        guard (try? handle.seek(toOffset: size - tailLength)) != nil,
              let tail = try? handle.read(upToCount: Int(tailLength)) else { return [] }
        let bytes = [UInt8](tail)
        var eocd = -1
        var index = bytes.count - 22
        while index >= 0 {
            if bytes[index] == 0x50, bytes[index + 1] == 0x4B, bytes[index + 2] == 0x05, bytes[index + 3] == 0x06 {
                eocd = index
                break
            }
            index -= 1
        }
        guard eocd >= 0 else { return [] }
        let directorySize = UInt64(le32(bytes, eocd + 12))
        let directoryOffset = UInt64(le32(bytes, eocd + 16))
        guard directoryOffset != 0xFFFF_FFFF, directoryOffset + directorySize <= size, directorySize < 64 << 20,
              (try? handle.seek(toOffset: directoryOffset)) != nil,
              let directory = try? handle.read(upToCount: Int(directorySize)) else { return [] }

        let cd = [UInt8](directory)
        var names: [Data] = []
        var offset = 0
        while offset + 46 <= cd.count, names.count < limit {
            guard le32(cd, offset) == 0x0201_4B50 else { break }
            let flags = le16(cd, offset + 8)
            let nameLength = Int(le16(cd, offset + 28))
            let extraLength = Int(le16(cd, offset + 30))
            let commentLength = Int(le16(cd, offset + 32))
            let start = offset + 46
            guard start + nameLength <= cd.count else { break }
            let name = cd[start..<start + nameLength]
            if flags & 0x0800 == 0, name.contains(where: { $0 >= 0x80 }) { names.append(Data(name)) }
            offset = start + nameLength + extraLength + commentLength
        }
        return names
    }

    private static func le16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
    private static func le32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
}
