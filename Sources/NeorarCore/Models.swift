import Foundation

public enum ArchiveFormat: String, Sendable, Hashable, CaseIterable {
    case rar, sevenZip, zip, tar, gzip, bzip2, xz, zstd, lzma, cab, iso, dmg, xar, cpio, other

    public var displayName: String {
        switch self {
        case .rar: "RAR"
        case .sevenZip: "7-Zip"
        case .zip: "ZIP"
        case .tar: "TAR"
        case .gzip: "GZip"
        case .bzip2: "BZip2"
        case .xz: "XZ"
        case .zstd: "Zstandard"
        case .lzma: "LZMA"
        case .cab: "CAB"
        case .iso: "ISO"
        case .dmg: "DMG"
        case .xar: "XAR"
        case .cpio: "CPIO"
        case .other: String(localized: "Arquivo")
        }
    }

    /// Detects the container format from the first bytes of a file.
    public static func sniff(_ url: URL) -> ArchiveFormat {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .other }
        defer { try? handle.close() }
        let head = [UInt8]((try? handle.read(upToCount: 512)) ?? Data())
        func starts(_ bytes: [UInt8], at offset: Int = 0) -> Bool {
            head.count >= offset + bytes.count && Array(head[offset..<offset + bytes.count]) == bytes
        }
        if starts([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]) { return .rar }
        if starts([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return .sevenZip }
        if starts([0x50, 0x4B, 0x03, 0x04]) || starts([0x50, 0x4B, 0x05, 0x06]) || starts([0x50, 0x4B, 0x07, 0x08]) { return .zip }
        if starts([0x1F, 0x8B]) { return .gzip }
        if starts([0x42, 0x5A, 0x68]) { return .bzip2 }
        if starts([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) { return .xz }
        if starts([0x28, 0xB5, 0x2F, 0xFD]) { return .zstd }
        if starts([0x5D, 0x00, 0x00]) { return .lzma }
        if starts([0x4D, 0x53, 0x43, 0x46]) { return .cab }
        if starts([0x78, 0x61, 0x72, 0x21]) { return .xar }
        if starts([0x30, 0x37, 0x30, 0x37, 0x30]) || starts([0xC7, 0x71]) || starts([0x71, 0xC7]) { return .cpio }
        if starts(Array("ustar".utf8), at: 257) { return .tar }
        if head.count >= 1 && url.pathExtension.lowercased() == "iso" { return .iso }
        if url.pathExtension.lowercased() == "dmg" { return .dmg }
        // Split RAR volumes past the first one have no signature of their own.
        return .other
    }
}

public struct ArchiveEntry: Identifiable, Hashable, Sendable {
    public let id: Int
    /// Normalized path inside the archive, `/`-separated, without leading or trailing slash.
    public let path: String
    public let isDirectory: Bool
    public let size: UInt64
    public let packedSize: UInt64
    public let modified: Date?
    public let isEncrypted: Bool
    public let isLink: Bool

    public init(id: Int, path: String, isDirectory: Bool, size: UInt64, packedSize: UInt64,
                modified: Date?, isEncrypted: Bool, isLink: Bool = false) {
        self.id = id
        self.path = ArchiveEntry.normalize(path)
        self.isDirectory = isDirectory
        self.size = size
        self.packedSize = packedSize
        self.modified = modified
        self.isEncrypted = isEncrypted
        self.isLink = isLink
    }

    public var name: String { path.split(separator: "/").last.map(String.init) ?? path }
    public var parentPath: String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    static func normalize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .filter { $0 != "." }
            .joined(separator: "/")
    }
}

public struct ArchiveListing: Sendable {
    public let archiveURL: URL
    public let format: ArchiveFormat
    public let entries: [ArchiveEntry]
    public let hasEncryptedHeaders: Bool
    public let isSolid: Bool
    public let isMultiVolume: Bool
    /// Code page used to decode names (ZIP only), nil when names were Unicode.
    public let codePage: Int?
    /// Archive comment (RAR and ZIP), nil when absent.
    public let comment: String?

    public init(archiveURL: URL, format: ArchiveFormat, entries: [ArchiveEntry], hasEncryptedHeaders: Bool = false,
                isSolid: Bool = false, isMultiVolume: Bool = false, codePage: Int? = nil, comment: String? = nil) {
        self.archiveURL = archiveURL
        self.format = format
        self.entries = entries
        self.hasEncryptedHeaders = hasEncryptedHeaders
        self.isSolid = isSolid
        self.isMultiVolume = isMultiVolume
        self.codePage = codePage
        let trimmed = comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.comment = trimmed?.isEmpty == false ? trimmed : nil
    }

    public var isEncrypted: Bool { hasEncryptedHeaders || entries.contains(where: \.isEncrypted) }
    public var totalSize: UInt64 { entries.reduce(0) { $0 + $1.size } }
    public var packedSize: UInt64 { entries.reduce(0) { $0 + $1.packedSize } }
    public var fileCount: Int { entries.lazy.filter { !$0.isDirectory }.count }
}

public struct ExtractProgress: Sendable {
    public var fraction: Double
    public var bytesDone: UInt64
    public var bytesTotal: UInt64
    public var currentItem: String?

    public init(fraction: Double, bytesDone: UInt64 = 0, bytesTotal: UInt64 = 0, currentItem: String? = nil) {
        self.fraction = fraction
        self.bytesDone = bytesDone
        self.bytesTotal = bytesTotal
        self.currentItem = currentItem
    }
}

public typealias ProgressHandler = @Sendable (ExtractProgress) -> Void

public enum ArchiveError: LocalizedError, Equatable, Sendable {
    case passwordRequired
    case wrongPassword
    case corrupted(String?)
    case missingVolume(String?)
    case unsupportedFormat
    case cannotRead(String)
    case cannotWrite(String)
    case diskFull
    case cancelled
    case toolMissing(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .passwordRequired: String(localized: "Este arquivo é protegido por senha.")
        case .wrongPassword: String(localized: "A senha informada está incorreta.")
        case .corrupted(let detail): String(localized: "O arquivo está corrompido.") + (detail.map { " \($0)" } ?? "")
        case .missingVolume(let name):
            if let name, !name.isEmpty { String(localized: "Volume ausente: \((name as NSString).lastPathComponent).") }
            else { String(localized: "O arquivo está incompleto: falta um volume.") }
        case .unsupportedFormat: String(localized: "Formato não suportado ou arquivo danificado.")
        case .cannotRead(let path): String(localized: "Sem permissão para ler “\((path as NSString).lastPathComponent)”.")
        case .cannotWrite(let path): String(localized: "Sem permissão para gravar em “\((path as NSString).lastPathComponent)”.")
        case .diskFull: String(localized: "Não há espaço suficiente no disco.")
        case .cancelled: String(localized: "Operação cancelada.")
        case .toolMissing(let tool): String(localized: "Ferramenta necessária não encontrada: \(tool).")
        case .failed(let message): message
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .missingVolume: String(localized: "Coloque todas as partes na mesma pasta e tente de novo.")
        case .cannotWrite: String(localized: "Escolha outro destino nos Ajustes.")
        case .toolMissing: String(localized: "Abra Ajustes › RAR para instalar ou localizar o rar.")
        default: nil
        }
    }
}
