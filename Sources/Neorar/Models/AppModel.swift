import AppKit
import NeorarCore
import Observation
import SwiftUI

@Observable
final class AppModel {
    /// Defaults must be registered before any stored property (e.g. CompressModel) reads them.
    static let shared: AppModel = {
        Preferences.registerDefaults()
        return AppModel()
    }()

    let folder = FolderModel()
    /// Archive currently opened inside the browser (WinRAR-style); nil shows the folder.
    var browser: BrowserModel?
    var jobs: [ExtractionJob] = []
    var passwordRequests: [PasswordRequest] = []
    let compress = CompressModel()
    var showCompress = false
    /// Archive whose properties the Info sheet shows.
    var infoTarget: URL?
    var toasts: [Toast] = []
    var conflictRequests: [ConflictRequest] = []
    /// Results of "Testar", shown one after another.
    var testReports: [TestReport] = []
    /// "Apply to all" answer for the current batch of extractions.
    private var batchConflictChoice: ConflictChoice?
    let rarTool = RarToolModel()
    let setup = SetupModel()
    /// Passwords typed this session, offered again in the password sheet. Never written to disk.
    var recentPasswords: [String] = []

    private init() {}

    /// Items dragged out of the archive preview must not be dropped back in (that would add them to the archive).
    @ObservationIgnored private var ownDragChangeCount: Int?

    func markOwnDrag() {
        // The drag pasteboard is written right after the payload is built.
        DispatchQueue.main.async { [weak self] in self?.ownDragChangeCount = NSPasteboard(name: .drag).changeCount }
    }

    var isOwnDrag: Bool { ownDragChangeCount == NSPasteboard(name: .drag).changeCount }

    var hasActiveWork: Bool { jobs.contains { $0.isActive || $0.isWaiting } || compress.isRunning }
    var activeJobs: [ExtractionJob] { jobs.filter(\.isActive) }

    // MARK: - Navigation

    func navigate(to url: URL) {
        browser = nil
        folder.navigate(to: url)
    }

    func goBack() {
        if browser != nil { browser = nil } else { folder.goBack() }
    }

    func goUp() {
        if let browser {
            if !browser.gridPath.isEmpty { browser.gridUp() } else { self.browser = nil }
        } else {
            folder.goUp()
        }
    }

    var canGoUp: Bool { browser != nil || folder.canGoUp }

    func chooseLocation() {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Escolha uma pasta ou um arquivo compactado")
        panel.prompt = String(localized: "Abrir")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.directoryURL = folder.location
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open([url])
    }

    /// Double-click / Return on an item in the folder list.
    func activate(_ item: FolderItem) {
        if item.isDirectory {
            navigate(to: item.url)
        } else if item.isArchive {
            browse(item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func browse(_ url: URL) {
        let archive = VolumeSet.resolve(url).first
        if archive.deletingLastPathComponent().standardizedFileURL != folder.location.standardizedFileURL {
            folder.navigate(to: archive.deletingLastPathComponent())
        }
        folder.selection = [url]
        let model = BrowserModel(archive: archive, app: self)
        browser = model
        model.load()
    }

    // MARK: - Opening (Finder, Dock, drag-and-drop)

    /// `fromFinder`: a double-click in Finder or a drop on the Dock icon (Finder-style result: the folder opens in Finder).
    func open(_ urls: [URL], fromFinder: Bool = false) {
        let directories = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]))
            .map { $0.isDirectory == true && $0.isPackage != true } ?? false }
        let archives = urls.filter { !directories.contains($0) && isArchive($0) }
        let others = urls.filter { !directories.contains($0) && !archives.contains($0) }

        if archives.isEmpty, others.isEmpty, directories.count == 1, let only = directories.first {
            navigate(to: only)
            return
        }
        if !archives.isEmpty {
            if Preferences.openBehavior == .browse, archives.count == 1, let only = archives.first {
                browse(only)
            } else if fromFinder {
                // Like Archive Utility: extract next to the archive, then open the result in Finder.
                enqueueExtraction(archives, folderPolicy: Preferences.safeHereFolderPolicy, origin: .finderOpen)
            } else {
                // Go to where the results will appear so the toast, progress and "new" badges are visible.
                if let first = archives.first, Preferences.destination(forPreview: first) == first.deletingLastPathComponent() {
                    navigate(to: first.deletingLastPathComponent())
                }
                enqueueExtraction(archives)
            }
        }
        let toCompress = others + (archives.isEmpty ? directories : [])
        if !toCompress.isEmpty { startCompress(toCompress) }
    }

    /// Actions sent by the Finder extension (right-click menu), e.g. neorar://extract-here?path=…
    func handleAction(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let paths = (components.queryItems ?? []).filter { $0.name == "path" }.compactMap(\.value)
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !paths.isEmpty else { return }
        // Finder actions run quietly: Neorar only comes forward when it needs an answer (password, conflict) or fails.
        switch components.host {
        case "extract-here":
            for (directory, group) in Dictionary(grouping: paths, by: { $0.deletingLastPathComponent() }) {
                enqueueExtraction(group, destination: directory, folderPolicy: Preferences.safeHereFolderPolicy,
                                  origin: .finderMenu)
            }
        case "compress":
            let mode = FinderCompressMode(rawValue: UserDefaults.standard.string(forKey: PrefKey.finderCompress) ?? "") ?? .ask
            if let format = mode.format {
                quickCompress(paths, format: format, revealInFinder: true)
            } else {
                AppDelegate.showMainWindow()
                startCompress(paths)
            }
        default:
            break
        }
    }

    /// One-click compression with the default options (Finder's menu when a format is preset in Settings).
    func quickCompress(_ urls: [URL], format: CompressionFormat, revealInFinder: Bool = false) {
        guard let first = urls.first else { return }
        var options = Preferences.compressionDefaults()
        options.format = format
        let directory = first.deletingLastPathComponent()
        let name = FileNaming.sanitize(CompressionService.defaultName(for: urls))
        let output = FileNaming.uniqueURL(in: directory, name: "\(name).\(format.fileExtension)", isDirectory: false)
        let working = Toast(style: .info, title: String(localized: "Comprimindo em \(format.title)…"), subtitle: output.lastPathComponent)
        post(working)
        Task {
            defer {
                dismissToast(working.id)
                if revealInFinder { AppDelegate.quitIfIdle() }
            }
            do {
                let written = try await CompressionService.compress(urls, to: output, options: options, progress: { _ in })
                compressFinished(written)
                if revealInFinder { NSWorkspace.shared.activateFileViewerSelecting(written) }
            } catch {
                let failure = (error as? ArchiveError) ?? .failed(error.localizedDescription)
                let title = String(localized: "Não foi possível comprimir")
                if revealInFinder { showFinderError(title, failure.errorDescription) }
                post(Toast(style: .error, title: title, subtitle: failure.errorDescription))
            }
        }
    }

    func startCompress(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if !compress.isRunning { compress.clear() }
        compress.destination = urls.first?.deletingLastPathComponent()
        compress.add(urls)
        showCompress = true
    }

    private func isArchive(_ url: URL) -> Bool {
        FileNaming.isArchive(url) || ArchiveFormat.sniff(url) != .other
    }

    // MARK: - Folder actions

    func extractSelection(here: Bool) {
        let archives = folder.selectedArchives
        guard !archives.isEmpty else { return }
        if here {
            enqueueExtraction(archives, destination: folder.location, folderPolicy: Preferences.safeHereFolderPolicy)
        } else if let destination = Preferences.askForFolder(title: String(localized: "Extrair para"), near: archives.first) {
            enqueueExtraction(archives, destination: destination)
        }
    }

    func testSelection() {
        if let browser {
            enqueueTest(browser.archive, from: browser)
        } else {
            for archive in folder.selectedArchives { enqueueTest(archive, from: nil) }
        }
    }

    func showInfo() {
        infoTarget = browser?.archive ?? folder.selectedArchives.first
    }

    private func enqueueTest(_ archive: URL, from browser: BrowserModel?) {
        let job = ExtractionJob(volumes: VolumeSet.resolve(archive))
        job.mode = .test
        if let browser, let listing = browser.listing, let engine = browser.engine {
            job.password = browser.password
            job.prepared = (listing, engine)
        }
        jobs.insert(job, at: 0)
        pump()
    }

    // MARK: - Editing the open archive

    /// Adds files to the archive on screen (asks for files when `items` is nil).
    func addToArchive(_ items: [URL]? = nil) {
        guard let browser, let listing = browser.listing else { return }
        if let reason = browser.editBlockedReason {
            post(Toast(style: .error, title: String(localized: "Não é possível alterar este arquivo"), subtitle: reason))
            return
        }
        var urls = items ?? []
        if items == nil {
            let panel = NSOpenPanel()
            panel.message = String(localized: "Escolha o que adicionar a “\(browser.archive.lastPathComponent)”")
            panel.prompt = String(localized: "Adicionar")
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = true
            guard panel.runModal() == .OK else { return }
            urls = panel.urls
        }
        guard !urls.isEmpty else { return }
        let folder = UserDefaults.standard.string(forKey: PrefKey.viewMode) == ViewMode.grid.rawValue ? browser.gridPath : ""
        let existing = Set(listing.entries.map(\.path))
        let replaced = urls.map { folder.isEmpty ? $0.lastPathComponent : "\(folder)/\($0.lastPathComponent)" }
            .filter(existing.contains)
        if !replaced.isEmpty {
            let alert = NSAlert()
            alert.messageText = replaced.count == 1 ? String(localized: "“\((replaced[0] as NSString).lastPathComponent)” já existe no arquivo")
                                                    : String(localized: "\(replaced.count) itens já existem no arquivo")
            alert.informativeText = String(localized: "Os itens com o mesmo nome dentro de “\(browser.archive.lastPathComponent)” serão substituídos.")
            alert.addButton(withTitle: String(localized: "Substituir"))
            alert.addButton(withTitle: String(localized: "Cancelar"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let names = urls.map(\.lastPathComponent)
        runEdit(on: browser, message: String(localized: "Adicionando a “\(browser.archive.lastPathComponent)”…"),
                done: names.count == 1 ? String(localized: "“\(names[0])” adicionado") : String(localized: "\(names.count) itens adicionados")) {
            try await ArchiveEditor.add(urls, to: browser.archive, inside: folder, listing: listing,
                                        password: browser.password, progress: { _ in })
        }
    }

    func deleteFromArchive() {
        guard let browser, let listing = browser.listing, !browser.selection.isEmpty else { return }
        if let reason = browser.editBlockedReason {
            post(Toast(style: .error, title: String(localized: "Não é possível alterar este arquivo"), subtitle: reason))
            return
        }
        let selection = browser.selection
        let alert = NSAlert()
        alert.messageText = selection.count == 1
            ? String(localized: "Excluir “\((selection.first! as NSString).lastPathComponent)” do arquivo?")
            : String(localized: "Excluir \(selection.count) itens do arquivo?")
        alert.informativeText = String(localized: "Eles serão removidos de “\(browser.archive.lastPathComponent)”. Isso não pode ser desfeito.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Excluir"))
        alert.addButton(withTitle: String(localized: "Cancelar"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runEdit(on: browser, message: String(localized: "Excluindo de “\(browser.archive.lastPathComponent)”…"),
                done: selection.count == 1 ? String(localized: "Item excluído do arquivo") : String(localized: "\(selection.count) itens excluídos do arquivo")) {
            try await ArchiveEditor.delete(selection, from: browser.archive, listing: listing, password: browser.password)
        }
    }

    private func runEdit(on browser: BrowserModel, message: String, done: String, _ work: @escaping () async throws -> Void) {
        browser.busyMessage = message
        Task {
            do {
                try await work()
                browser.busyMessage = nil
                browser.selection.removeAll()
                browser.load()
                post(Toast(style: .success, title: done, subtitle: browser.archive.lastPathComponent))
            } catch {
                browser.busyMessage = nil
                let failure = (error as? ArchiveError) ?? .failed(error.localizedDescription)
                post(Toast(style: .error, title: String(localized: "Não foi possível alterar o arquivo"), subtitle: failure.errorDescription))
            }
        }
    }

    // MARK: - Repair

    /// Archive the "Reparar" command applies to: the open one, or the single selected archive.
    var repairTarget: URL? {
        browser?.archive ?? (folder.selectedArchives.count == 1 ? folder.selectedArchives.first : nil)
    }

    func repair(_ archive: URL) {
        if case .failure(let error) = ArchiveRepair.method(for: archive) {
            post(Toast(style: .error, title: String(localized: "Não é possível reparar “\(archive.lastPathComponent)”"), subtitle: error.errorDescription))
            return
        }
        let working = Toast(style: .info, title: String(localized: "Reparando “\(archive.lastPathComponent)”…"), subtitle: String(localized: "O original não será alterado."))
        post(working)
        Task {
            defer { dismissToast(working.id) }
            do {
                let repaired = try await ArchiveRepair.repair(archive)
                let directory = repaired.deletingLastPathComponent()
                reveal([repaired], in: directory, navigate: false)
                post(Toast(style: .success, title: String(localized: "Reparado: \(repaired.lastPathComponent)"), subtitle: String(localized: "em \(directory.lastPathComponent)"),
                           actionTitle: String(localized: "Testar")) { AppModel.shared.enqueueTest(repaired, from: nil) })
            } catch {
                let failure = (error as? ArchiveError) ?? .failed(error.localizedDescription)
                post(Toast(style: .error, title: String(localized: "Não foi possível reparar"), subtitle: failure.errorDescription))
            }
        }
    }

    func compressSelection() {
        startCompress(folder.selectedItems.map(\.url))
    }

    func trashSelection() {
        let urls = folder.selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.recycle(urls) { [weak self] trashed, error in
            Task { @MainActor in
                guard let self else { return }
                self.folder.selection.removeAll()
                self.folder.reload(animated: true)
                if let error {
                    self.post(Toast(style: .error, title: String(localized: "Não foi possível mover para o Lixo"), subtitle: error.localizedDescription))
                    return
                }
                let title = trashed.count == 1 ? String(localized: "“\(urls[0].lastPathComponent)” foi para o Lixo") : String(localized: "\(trashed.count) itens foram para o Lixo")
                self.post(Toast(style: .info, title: title, actionTitle: String(localized: "Desfazer")) { [weak self] in
                    self?.restore(trashed)
                })
            }
        }
    }

    /// Undo for "Excluir": moves items back from the Trash.
    private func restore(_ trashed: [URL: URL]) {
        var restored: [URL] = []
        for (original, inTrash) in trashed where (try? FileManager.default.moveItem(at: inTrash, to: original)) != nil {
            restored.append(original)
        }
        guard !restored.isEmpty else {
            post(Toast(style: .error, title: String(localized: "Não foi possível restaurar"), subtitle: String(localized: "Os itens continuam no Lixo.")))
            return
        }
        folder.markNew(restored)
        post(Toast(style: .success, title: restored.count == 1 ? String(localized: "“\(restored[0].lastPathComponent)” restaurado") : String(localized: "\(restored.count) itens restaurados")))
    }

    // MARK: - Clipboard

    func copyPath(_ url: URL) { copyPaths([url]) }

    /// ⌥⌘C, like Finder: the selected items, or the folder/archive on screen when nothing is selected.
    func copyCurrentPath() {
        if browser == nil, !folder.selection.isEmpty {
            copyPaths(folder.selectedItems.map(\.url))
        } else {
            copyPath(browser?.archive ?? folder.location)
        }
    }

    func copyPaths(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let text = urls.map { $0.path(percentEncoded: false) }.map { $0.count > 1 && $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        post(Toast(style: .info, title: urls.count == 1 ? String(localized: "Caminho copiado") : String(localized: "\(urls.count) caminhos copiados"),
                   subtitle: urls.count == 1 ? (text as NSString).abbreviatingWithTildeInPath : nil))
    }

    // MARK: - Feedback

    func post(_ toast: Toast) {
        withAnimation(.spring(duration: 0.4, bounce: 0.25)) {
            toasts.append(toast)
            if toasts.count > 3 { toasts.removeFirst() }
        }
        let id = toast.id
        Task {
            try? await Task.sleep(for: .seconds(toast.actionTitle == nil ? 3.5 : 6))
            dismissToast(id)
        }
    }

    func dismissToast(_ id: UUID) {
        withAnimation(.smooth(duration: 0.3)) { toasts.removeAll { $0.id == id } }
    }

    /// Shows newly created items: refresh, select and badge them when they are in the folder on screen.
    func reveal(_ urls: [URL], in directory: URL, navigate: Bool) {
        if navigate, directory.standardizedFileURL != folder.location.standardizedFileURL {
            self.navigate(to: directory)
        } else if navigate {
            browser = nil
        }
        if directory.standardizedFileURL == folder.location.standardizedFileURL { folder.markNew(urls) }
    }

    func compressFinished(_ written: [URL]) {
        showCompress = false
        guard let first = written.first else { return }
        let directory = first.deletingLastPathComponent()
        reveal(written, in: directory, navigate: false)
        post(Toast(style: .success, title: String(localized: "Comprimido: \(first.lastPathComponent)"),
                   subtitle: written.count > 1 ? String(localized: "\(written.count) volumes em \(directory.lastPathComponent)") : String(localized: "em \(directory.lastPathComponent)"),
                   actionTitle: String(localized: "Mostrar")) { [weak self] in self?.reveal(written, in: directory, navigate: true) })
    }

    /// Jobs worth showing in the activity panel (completed ones are confirmed by a toast instead).
    var trayJobs: [ExtractionJob] {
        jobs.filter { job in
            switch job.state {
            case .finished, .verified: false
            default: true
            }
        }
    }

    var hudJob: ExtractionJob? { jobs.first { $0.isActive && $0.hudVisible && !$0.hudDismissed } }

    // MARK: - Extraction queue

    func enqueueExtraction(_ urls: [URL], destination: URL? = nil, folderPolicy: FolderPolicy? = nil, origin: ExtractionJob.Origin = .app) {
        for volumes in VolumeSet.group(urls) {
            if jobs.contains(where: { $0.archive == volumes.first && ($0.isActive || $0.isWaiting) }) { continue }
            let job = ExtractionJob(volumes: volumes)
            job.destination = destination
            job.folderPolicy = folderPolicy
            job.origin = origin
            jobs.insert(job, at: 0)
        }
        pump()
    }

    /// Queues an extraction prepared by the archive browser (listing, engine and password already known).
    func enqueueExtraction(from browser: BrowserModel, selection: Set<String>?, destination: URL?) {
        guard let listing = browser.listing, let engine = browser.engine else { return }
        let job = ExtractionJob(volumes: VolumeSet.resolve(browser.archive))
        job.password = browser.password
        job.selection = selection
        job.destination = destination
        job.prepared = (listing, engine)
        jobs.insert(job, at: 0)
        pump()
    }

    private func pump() {
        let running = jobs.filter(\.isActive).count
        let slots = Preferences.maxConcurrent - running
        if running == 0 && !jobs.contains(where: \.isWaiting) { batchConflictChoice = nil }
        guard slots > 0 else { return }
        for job in jobs.reversed().filter(\.isWaiting).prefix(slots) { start(job) }
    }

    /// Shows the progress panel only for work that takes longer than a blink.
    private func scheduleHUD(for job: ExtractionJob) {
        job.hudVisible = false
        Task { [weak job] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let job, job.isActive else { return }
            withAnimation(.spring(duration: 0.35)) { job.hudVisible = true }
        }
    }

    private func start(_ job: ExtractionJob) {
        if job.mode == .test { return startTest(job) }
        if job.destination == nil {
            guard let destination = Preferences.destination(for: job.archive) else {
                job.state = .cancelled
                pump()
                return
            }
            job.destination = destination
        }
        guard let destination = job.destination else { return }
        job.state = .preparing
        job.resetProgress()
        job.startedAt = Date()
        scheduleHUD(for: job)

        var options = Preferences.extractionOptions(destination: destination)
        options.selection = job.selection
        if let policy = job.folderPolicy { options.folderPolicy = policy }
        let archive = job.archive
        let password = job.password

        job.task = Task { [weak self, weak job] in
            do {
                let prepared: (listing: ArchiveListing, engine: any ArchiveEngine)
                if let existing = job?.prepared {
                    prepared = existing
                } else {
                    prepared = try await ExtractionService.prepare(archive, password: password, codePage: options.codePage)
                    job?.prepared = prepared
                }
                if prepared.listing.isEncrypted && (password ?? "").isEmpty { throw ArchiveError.passwordRequired }

                // Ask before touching anything that already exists.
                let conflicts = ExtractionService.conflicts(for: archive, listing: prepared.listing, options: options)
                if !conflicts.isEmpty, let self, let job {
                    let choice = await self.resolveConflict(job: job, names: conflicts, destination: destination)
                    switch choice {
                    case .cancel: throw ArchiveError.cancelled
                    case .replace: options.conflictPolicy = .overwrite
                    case .keepBoth: options.conflictPolicy = .rename
                    }
                }

                let result = try await ExtractionService.extract(
                    archive, options: options, password: password, prepared: prepared,
                    progress: { update in
                        Task { @MainActor in
                            guard let job, job.isActive else { return }
                            job.state = .extracting
                            job.apply(update)
                        }
                    }
                )
                guard let job else { return }
                job.progress = 1
                job.finishedAt = Date()
                job.state = .finished(result)
                UserDefaults.standard.set(destination.path, forKey: PrefKey.lastDestination)
                self?.extractionFinished(job, result: result, destination: destination)
            } catch {
                guard let job else { return }
                let failure = (error as? ArchiveError) ?? (error is CancellationError ? .cancelled : .failed(error.localizedDescription))
                switch failure {
                case .passwordRequired: self?.askPassword(for: job, wrong: false)
                case .wrongPassword: self?.askPassword(for: job, wrong: true)
                case .cancelled: job.state = .cancelled
                default:
                    job.state = .failed(failure)
                    let title = String(localized: "Falha ao extrair “\(job.name)”")
                    if job.origin != .app { self?.showFinderError(title, failure.errorDescription) }
                    self?.post(Toast(style: .error, title: title, subtitle: failure.errorDescription))
                }
            }
            self?.pump()
            AppDelegate.quitIfIdle()
        }
    }

    private func extractionFinished(_ job: ExtractionJob, result: ExtractionResult, destination: URL) {
        let created = result.createdFolder.map { [$0] } ?? result.items
        reveal(created, in: destination, navigate: false)
        // "Extrair para Nome/": the new folder itself is what appears in the folder on screen.
        if destination.deletingLastPathComponent().standardizedFileURL == folder.location.standardizedFileURL {
            folder.markNew([destination])
        }
        let elapsed = (job.finishedAt ?? Date()).timeIntervalSince(job.startedAt ?? Date())
        let title = created.count == 1 ? String(localized: "Extraído: \(created[0].lastPathComponent)") : String(localized: "Extraídos \(created.count) itens")
        post(Toast(style: .success, title: title,
                   subtitle: String(localized: "em \(destination.lastPathComponent) · \(Format.duration(elapsed))"),
                   actionTitle: String(localized: "Mostrar")) { [weak self] in self?.reveal(created, in: destination, navigate: true) })
        switch job.origin {
        case .finderOpen:
            // Double-click in Finder: step straight into the extracted folder (or select a lone extracted file).
            var isDirectory: ObjCBool = false
            if let target = created.count == 1 ? created.first : nil,
               FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory), isDirectory.boolValue {
                NSWorkspace.shared.open(target)
            } else if !created.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(created)
            }
        case .finderMenu:
            if !created.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(created) }
        case .app:
            if Preferences.revealAfter, let target = result.revealTarget {
                NSWorkspace.shared.activateFileViewerSelecting([target])
            }
        }
        // The toast confirms it; keep the activity list for work that still needs attention.
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.smooth) { jobs.removeAll { $0.id == job.id } }
        }
    }

    private func resolveConflict(job: ExtractionJob, names: [String], destination: URL) async -> ConflictChoice {
        if let batchConflictChoice { return batchConflictChoice }
        // Finder work never asks: like Archive Utility, the new copy gets a numbered name.
        if job.origin != .app { return .keepBoth }
        job.hudDismissed = true
        job.awaitingDecision = true
        defer { job.awaitingDecision = false }
        let othersPending = jobs.contains { $0.id != job.id && ($0.isWaiting || $0.isActive) && $0.mode == .extract }
        let choice = await withCheckedContinuation { (continuation: CheckedContinuation<ConflictChoice, Never>) in
            conflictRequests.append(ConflictRequest(
                archiveName: job.name, names: names, destination: destination, othersPending: othersPending
            ) { [weak self] choice, applyToAll in
                if applyToAll { self?.batchConflictChoice = choice }
                continuation.resume(returning: choice)
            })
        }
        job.hudDismissed = false
        return choice
    }

    func answerConflict(_ request: ConflictRequest, _ choice: ConflictChoice, applyToAll: Bool) {
        conflictRequests.removeAll { $0.id == request.id }
        request.resolve(choice, applyToAll)
    }

    private func startTest(_ job: ExtractionJob) {
        job.state = .preparing
        job.resetProgress()
        job.startedAt = Date()
        scheduleHUD(for: job)
        let archive = job.archive, password = job.password, prepared = job.prepared
        job.task = Task { [weak self, weak job] in
            do {
                let listing = try await ExtractionService.test(archive, password: password, prepared: prepared) { update in
                    Task { @MainActor in
                        guard let job, job.isActive else { return }
                        job.state = .extracting
                        job.apply(update)
                    }
                }
                guard let job else { return }
                job.progress = 1
                job.finishedAt = Date()
                job.state = .verified(files: listing.fileCount)
                self?.finishTest(job, files: listing.fileCount, error: nil)
            } catch {
                guard let job else { return }
                let failure = (error as? ArchiveError) ?? (error is CancellationError ? .cancelled : .failed(error.localizedDescription))
                switch failure {
                case .passwordRequired: self?.askPassword(for: job, wrong: false)
                case .wrongPassword: self?.askPassword(for: job, wrong: true)
                case .cancelled: job.state = .cancelled
                default:
                    job.state = .failed(failure)
                    self?.finishTest(job, files: 0, error: failure)
                }
            }
            self?.pump()
        }
    }

    private func finishTest(_ job: ExtractionJob, files: Int, error: ArchiveError?) {
        let elapsed = Date().timeIntervalSince(job.startedAt ?? Date())
        testReports.append(TestReport(archive: job.archive, archiveName: job.name, files: files, elapsed: elapsed, error: error))
        withAnimation(.smooth) { jobs.removeAll { $0.id == job.id } }
    }

    func refreshIfShowing(_ url: URL) {
        if url.standardizedFileURL == folder.location.standardizedFileURL { folder.reload(animated: true) }
    }

    private func askPassword(for job: ExtractionJob, wrong: Bool) {
        job.state = .needsPassword(wrong: wrong)
        if job.origin != .app {
            askPasswordFromFinder(for: job, wrong: wrong)
            return
        }
        requestPassword(for: job.name, wrong: wrong) { [weak self, weak job] password in
            guard let job else { return }
            job.password = password
            job.state = .waiting
            self?.pump()
        } cancel: { [weak job] in
            job?.state = .cancelled
        }
    }

    /// Password for Finder work: a small system alert instead of the main window.
    private func askPasswordFromFinder(for job: ExtractionJob, wrong: Bool) {
        DispatchQueue.main.async { [weak self, weak job] in
            guard let self, let job else { return }
            let alert = NSAlert()
            alert.messageText = wrong ? String(localized: "Senha incorreta") : String(localized: "Senha necessária")
            alert.informativeText = String(localized: "Digite a senha de “\(job.name)”.")
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            alert.accessoryView = field
            alert.addButton(withTitle: String(localized: "Extrair"))
            alert.addButton(withTitle: String(localized: "Cancelar"))
            alert.window.initialFirstResponder = field
            if AppDelegate.runAlert(alert) == .alertFirstButtonReturn, !field.stringValue.isEmpty {
                self.remember(field.stringValue)
                job.password = field.stringValue
                job.state = .waiting
                self.pump()
            } else {
                job.state = .cancelled
                AppDelegate.quitIfIdle()
            }
        }
    }

    /// Errors from Finder work: a small system alert instead of the main window.
    private func showFinderError(_ title: String, _ message: String?) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message ?? ""
            _ = AppDelegate.runAlert(alert)
            AppDelegate.quitIfIdle()
        }
    }

    func requestPassword(for name: String, wrong: Bool, submit: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        let request = PasswordRequest(archiveName: name, wrong: wrong, submit: { [weak self] password in
            self?.remember(password)
            submit(password)
        }, cancel: cancel)
        passwordRequests.append(request)
    }

    func resolvePassword(_ request: PasswordRequest, with password: String?) {
        passwordRequests.removeAll { $0.id == request.id }
        if let password, !password.isEmpty { request.submit(password) } else { request.cancel() }
    }

    private func remember(_ password: String) {
        recentPasswords.removeAll { $0 == password }
        recentPasswords.insert(password, at: 0)
        if recentPasswords.count > 8 { recentPasswords.removeLast() }
    }

    func cancel(_ job: ExtractionJob) {
        if job.isWaiting { job.state = .cancelled }
        job.task?.cancel()
    }

    func retry(_ job: ExtractionJob, destination: URL? = nil) {
        if let destination { job.destination = destination }
        job.state = .waiting
        pump()
    }

    func remove(_ job: ExtractionJob) {
        cancel(job)
        jobs.removeAll { $0.id == job.id }
    }

    func clearFinished() {
        jobs.removeAll(where: \.isDone)
    }

    func cancelAll() {
        jobs.forEach(cancel)
        compress.cancel()
    }
}
