import Foundation

/// Reads and writes the archive comment stored in a ZIP's end-of-central-directory record.
public enum ZipComment {
    public static func read(_ archive: URL, codePage: Int? = nil) -> String? {
        guard let (data, eocd, _) = endRecord(archive) else { return nil }
        let length = Int(data[eocd + 20]) | Int(data[eocd + 21]) << 8
        let start = eocd + 22
        guard length > 0, start + length <= data.count else { return nil }
        let bytes = data[start..<start + length]
        if let text = String(data: bytes, encoding: .utf8) { return text }
        if let codePage {
            let cf = CFStringConvertWindowsCodepageToEncoding(UInt32(codePage))
            if cf != kCFStringEncodingInvalidId,
               let text = String(data: bytes, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))) {
                return text
            }
        }
        return String(data: bytes, encoding: .windowsCP1252)
    }

    /// Replaces the comment of a single-file ZIP (UTF-8, at most 65 535 bytes).
    /// Only the end record is rewritten; the compressed data is never touched.
    public static func write(_ comment: String, to archive: URL) throws {
        guard let (_, _, recordOffset) = endRecord(archive) else {
            throw ArchiveError.failed(String(localized: "Não foi possível gravar o comentário no ZIP."))
        }
        let bytes = Data(comment.utf8.prefix(65_535))
        let handle = try FileHandle(forWritingTo: archive)
        defer { try? handle.close() }
        try handle.seek(toOffset: recordOffset + 20)
        try handle.write(contentsOf: Data([UInt8(bytes.count & 0xFF), UInt8(bytes.count >> 8)]) + bytes)
        try handle.truncate(atOffset: recordOffset + 22 + UInt64(bytes.count))
    }

    /// The last 64 KB of the file, the record's offset inside it, and its absolute offset in the file.
    private static func endRecord(_ archive: URL) -> (Data, Int, UInt64)? {
        guard let handle = try? FileHandle(forReadingFrom: archive) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size >= 22 else { return nil }
        let tailLength = min(size, 65_557)
        guard (try? handle.seek(toOffset: size - tailLength)) != nil,
              let tail = try? handle.read(upToCount: Int(tailLength)) else { return nil }
        let bytes = [UInt8](tail)
        var index = bytes.count - 22
        while index >= 0 {
            if bytes[index] == 0x50, bytes[index + 1] == 0x4B, bytes[index + 2] == 0x05, bytes[index + 3] == 0x06 {
                return (Data(bytes), index, size - tailLength + UInt64(index))
            }
            index -= 1
        }
        return nil
    }
}
