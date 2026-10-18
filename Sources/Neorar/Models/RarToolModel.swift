import AppKit
import NeorarCore
import Observation

/// Tracks RARLAB's `rar`, which Neorar needs to create .rar archives.
@Observable
final class RarToolModel {
    enum Status {
        case checking
        case available(path: URL, version: String)
        case missing
        case installing
        case failed(String)
    }

    var status: Status = .checking

    init() { refresh() }

    var isAvailable: Bool { if case .available = status { true } else { false } }

    func refresh() {
        guard let url = ToolLocator.rar else {
            status = .missing
            return
        }
        status = .checking
        Task {
            let version = await RarInstaller.installedVersion(at: url)
            status = version.map { .available(path: url, version: $0) } ?? .failed(String(localized: "O rar encontrado não pôde ser executado."))
        }
    }

    /// Shows RARLAB's terms, then downloads the official build into Application Support.
    func install() {
        status = .installing
        Task {
            do {
                let release = try await RarInstaller.latestRelease()
                let alert = NSAlert()
                alert.messageText = String(localized: "Instalar o rar \(release.version) da RARLAB?")
                alert.informativeText = String(localized: """
                O formato RAR é proprietário: só o rar oficial da RARLAB pode criá-lo. O Neorar vai baixá-lo \
                diretamente de rarlab.com para a pasta de suporte do app.

                O rar é shareware: o uso é gratuito por 40 dias e depois exige uma licença comprada em rarlab.com. \
                Extrair arquivos RAR no Neorar não depende dele.
                """)
                alert.addButton(withTitle: String(localized: "Baixar e Instalar"))
                alert.addButton(withTitle: String(localized: "Cancelar"))
                guard alert.runModal() == .alertFirstButtonReturn else {
                    refresh()
                    return
                }
                _ = try await RarInstaller.install(release)
                refresh()
            } catch {
                status = .failed((error as? ArchiveError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    func locate() {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Localize o executável rar")
        panel.prompt = String(localized: "Usar Este")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: ToolLocator.customRarPathKey)
        refresh()
    }

    func resetToAutomatic() {
        UserDefaults.standard.removeObject(forKey: ToolLocator.customRarPathKey)
        refresh()
    }
}
