import NeorarCore
import SwiftUI

/// Archive properties, similar to WinRAR's "Info" dialog.
struct ArchiveInfoSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let url: URL

    @State private var listing: ArchiveListing?
    @State private var error: ArchiveError?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                FileIcon(url: url, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent).font(.title3.weight(.semibold)).lineLimit(2)
                    Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
            }

            Group {
                if let listing {
                    Form {
                        LabeledContent("Formato", value: listing.format.displayName)
                        LabeledContent("Arquivos", value: "\(listing.fileCount)")
                        LabeledContent("Pastas", value: "\(listing.entries.filter(\.isDirectory).count)")
                        LabeledContent("Tamanho original", value: Format.bytes(listing.totalSize))
                        LabeledContent("Tamanho do arquivo", value: Format.bytes(archiveSize))
                        LabeledContent("Taxa de compressão", value: ratio(listing))
                        LabeledContent("Volumes", value: "\(VolumeSet.resolve(url).members.count)")
                        LabeledContent("Sólido", value: listing.isSolid ? String(localized: "Sim") : String(localized: "Não"))
                        LabeledContent("Criptografia", value: encryption(listing))
                        if let comment = listing.comment {
                            Section("Comentário") {
                                Text(comment)
                                    .font(.callout.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .transition(.opacity)
                } else if let error {
                    ContentUnavailableView(error.errorDescription ?? String(localized: "Erro"), systemImage: "exclamationmark.triangle",
                                           description: Text(error == .passwordRequired
                                                             ? "Abra o arquivo e informe a senha para ver os detalhes." : ""))
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .animation(.smooth(duration: 0.2), value: listing == nil)

            HStack {
                Spacer()
                Button("OK") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .task { await load() }
    }

    private var archiveSize: UInt64 {
        VolumeSet.resolve(url).members.reduce(0) { total, volume in
            total + UInt64((try? volume.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private func ratio(_ listing: ArchiveListing) -> String {
        guard listing.totalSize > 0 else { return "—" }
        let value = Double(archiveSize) / Double(listing.totalSize)
        return value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func encryption(_ listing: ArchiveListing) -> String {
        if listing.hasEncryptedHeaders { return String(localized: "Arquivos e nomes") }
        if listing.isEncrypted { return String(localized: "Arquivos (nomes visíveis)") }
        return String(localized: "Nenhuma")
    }

    private func load() async {
        if let browser = model.browser, browser.archive == url, let current = browser.listing {
            listing = current
            return
        }
        do {
            listing = try await Engines.list(VolumeSet.resolve(url).first, password: nil, codePage: nil).listing
        } catch {
            self.error = (error as? ArchiveError) ?? .failed(error.localizedDescription)
        }
    }
}
