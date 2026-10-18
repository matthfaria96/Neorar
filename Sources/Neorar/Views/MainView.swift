import NeorarCore
import QuickLook
import SwiftUI

/// Single WinRAR-style window: big action bar, path bar, folder or archive contents as list or grid.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(PrefKey.viewMode) private var viewMode = ViewMode.list.rawValue
    @State private var dropTargeted = false
    @State private var previewURL: URL?
    @FocusState private var searchFocused: Bool

    private var mode: ViewMode { ViewMode(rawValue: viewMode) ?? .list }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            RibbonBar(searching: searchFocused, preview: previewSelection)
            Divider()
            PathBar()
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay { if dropTargeted { dropOverlay } }
                .overlay {
                    if let job = model.hudJob {
                        ProgressHUD(job: job)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .bottom) { ToastStack() }
                .animation(.spring(duration: 0.35), value: model.hudJob?.id)
            if !model.trayJobs.isEmpty {
                JobsTray()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.smooth(duration: 0.28), value: model.trayJobs.isEmpty)
        .toolbar { NavigationToolbar(viewMode: $viewMode, searchText: searchText, searchFocused: $searchFocused) }
        .toolbar(removing: .title)
        .navigationTitle(model.browser?.archive.lastPathComponent ?? FileManager.default.displayName(atPath: model.folder.location.path))
        .quickLookPreview($previewURL, in: model.folder.selectedItems.filter { !$0.isDirectory }.map(\.url))
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty, !model.isOwnDrag else { return false }
            // With an archive open, dropped files are added to it (like WinRAR).
            if model.browser?.isEditable == true { model.addToArchive(files) } else { model.open(files) }
            return true
        } isTargeted: { targeted in withAnimation(.easeOut(duration: 0.15)) { dropTargeted = targeted && !model.isOwnDrag } }
        .modifier(MainSheets())
        .onKeyPress(keys: [.space]) { _ in
            // Space types a space in any text field (name, comment, filter, password); only the lists use it for Quick Look.
            if NSApp.keyWindow?.firstResponder is NSText { return .ignored }
            guard NSApp.keyWindow?.attachedSheet == nil, NSApp.keyWindow?.sheetParent == nil else { return .ignored }
            previewSelection()
            return .handled
        }
    }

    private var searchText: Binding<String> {
        Binding(
            get: { model.browser?.searchText ?? model.folder.filterText },
            set: { value in
                if let browser = model.browser { browser.searchText = value } else { model.folder.filterText = value }
            }
        )
    }

    private func previewSelection() {
        if let browser = model.browser {
            browser.quickLook()
        } else if let file = model.folder.selectedItems.first(where: { !$0.isDirectory }) {
            previewURL = file.url
        }
    }

    /// Identity of what is on screen; changing it cross-fades the content.
    private var contentID: String {
        let base = model.browser.map { "a:" + $0.archive.path } ?? "f:" + model.folder.location.path
        return base + "|" + viewMode
    }

    @ViewBuilder private var content: some View {
        ZStack {
            if let browser = model.browser {
                ArchiveContentsView(browser: browser, mode: mode)
            } else {
                FolderContentsView(folder: model.folder, mode: mode)
            }
        }
        .id(contentID)
        .transition(.opacity.combined(with: .scale(scale: 0.995)))
        .animation(.smooth(duration: 0.22), value: contentID)
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            .background(Color.accentColor.opacity(0.07), in: .rect(cornerRadius: 10))
            .overlay {
                Label(model.browser?.isEditable == true ? "Solte para adicionar ao arquivo" : "Solte para abrir, extrair ou comprimir",
                      systemImage: "arrow.down.doc")
                    .font(.headline)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: .rect(cornerRadius: 10))
            }
            .padding(8)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

/// Every sheet the main window can present (kept apart to keep the window's body simple to type-check).
private struct MainSheets: ViewModifier {
    @Environment(AppModel.self) private var model
    @AppStorage(PrefKey.onboardingDone) private var onboardingDone = false

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .sheet(item: Binding(get: { model.passwordRequests.first }, set: { _ in })) { request in
                PasswordSheet(request: request).environment(model)
            }
            .sheet(item: Binding(get: { model.conflictRequests.first }, set: { _ in })) { request in
                ConflictSheet(request: request).environment(model)
            }
            .sheet(item: testReport) { report in
                TestReportSheet(report: report).environment(model)
            }
            .sheet(isPresented: Binding(get: { !onboardingDone }, set: { if !$0 { onboardingDone = true } })) {
                OnboardingView().environment(model)
            }
            .sheet(isPresented: $model.showCompress) {
                CompressSheet().environment(model)
            }
            .sheet(item: Binding(get: { model.infoTarget.map(InfoTarget.init) }, set: { model.infoTarget = $0?.url })) { target in
                ArchiveInfoSheet(url: target.url).environment(model)
            }
    }

    private var testReport: Binding<TestReport?> {
        Binding(get: { model.testReports.first },
                set: { if $0 == nil, !model.testReports.isEmpty { model.testReports.removeFirst() } })
    }
}

private struct InfoTarget: Identifiable {
    let url: URL
    var id: URL { url }
}

// MARK: - Action bar

private struct RibbonBar: View {
    @Environment(AppModel.self) private var model
    /// While typing in the filter, ⌘⌫ must edit text, never trash files.
    let searching: Bool
    let preview: () -> Void

    var body: some View {
        let inArchive = model.browser != nil
        let folder = model.folder
        let hasArchive = inArchive ? model.browser?.listing != nil : !folder.selectedArchives.isEmpty
        HStack(spacing: 0) {
            if let browser = model.browser {
                RibbonButton(title: String(localized: "Adicionar"), glyph: .compress,
                             help: browser.editBlockedReason ?? "Adicionar arquivos a este arquivo compactado") { model.addToArchive() }
                    .disabled(!browser.isEditable)
            } else {
                RibbonButton(title: String(localized: "Comprimir"), glyph: .compress,
                             help: String(localized: "Comprimir os itens selecionados")) { model.compressSelection() }
                    .disabled(folder.selection.isEmpty)
            }
            RibbonButton(title: String(localized: "Extrair Para"), glyph: .extractTo,
                         help: String(localized: "Escolher onde extrair")) { extract(here: false) }
                .disabled(!hasArchive)
            RibbonButton(title: String(localized: "Extrair Aqui"), glyph: .extractHere,
                         help: String(localized: "Extrair na pasta atual")) { extract(here: true) }
                .disabled(!hasArchive)
            RibbonButton(title: String(localized: "Excluir"), glyph: .delete,
                         help: inArchive ? (model.browser?.editBlockedReason ?? "Excluir do arquivo compactado (⌘⌫)") : "Mover para o Lixo (⌘⌫)") {
                if inArchive { model.deleteFromArchive() } else { model.trashSelection() }
            }
                .disabled(inArchive ? (model.browser?.isEditable != true || model.browser?.selection.isEmpty != false)
                                    : folder.selection.isEmpty)
                .keyboardShortcut(searching ? nil : KeyboardShortcut(.delete, modifiers: .command))

            // Vertical rule separating the main actions from the secondary ones.
            Divider()
                .frame(height: 58)
                .padding(.horizontal, 14)

            RibbonButton(title: String(localized: "Espiar"), glyph: .preview, help: String(localized: "Visualização rápida (barra de espaço)")) { preview() }
                .disabled(inArchive ? model.browser?.selection.isEmpty != false
                                    : !folder.selectedItems.contains { !$0.isDirectory })
            RibbonButton(title: String(localized: "Testar"), glyph: .test,
                         help: String(localized: "Verificar a integridade do arquivo")) { model.testSelection() }
                .disabled(!hasArchive)
            RibbonButton(title: String(localized: "Info"), glyph: .info, help: String(localized: "Propriedades do arquivo")) { model.showInfo() }
                .disabled(!inArchive && folder.selectedArchives.isEmpty)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func extract(here: Bool) {
        if let browser = model.browser {
            if here {
                model.enqueueExtraction(from: browser, selection: browser.selection.isEmpty ? nil : browser.selection,
                                        destination: browser.archive.deletingLastPathComponent())
            } else {
                browser.extract(selectionOnly: !browser.selection.isEmpty, chooseDestination: true)
            }
        } else {
            model.extractSelection(here: here)
        }
    }
}

// MARK: - Path bar

private struct PathBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Button { withAnimation(.smooth(duration: 0.22)) { model.goUp() } } label: {
                Image(systemName: "arrow.turn.left.up")
            }
            .buttonStyle(.borderless)
            .disabled(!model.canGoUp)
            .keyboardShortcut(.upArrow, modifiers: .command)
            .help("Subir um nível (⌘↑)")

            if let browser = model.browser {
                FileIcon(url: browser.archive, size: 16)
                Text(archiveDescription(browser))
                    .lineLimit(1).truncationMode(.middle)
                    .contextMenu {
                        Button("Copiar Caminho", systemImage: "doc.on.doc") { model.copyPath(browser.archive) }
                    }
                CopyPathButton(url: browser.archive)
                if browser.listing?.isEncrypted == true {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.orange).help("Protegido por senha")
                }
                Spacer()
                if browser.isZip {
                    Picker("Codificação", selection: Binding(
                        get: { browser.codePage ?? 0 },
                        set: { browser.changeEncoding($0 == 0 ? nil : $0) }
                    )) {
                        Text("Codificação automática").tag(0)
                        Divider()
                        ForEach(ZipEncodingDetector.choices) { Text($0.name).tag($0.codePage) }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: 200)
                }
                Button("Fechar Arquivo", systemImage: "xmark.circle.fill") {
                    withAnimation(.smooth(duration: 0.22)) { model.browser = nil }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Voltar para a pasta")
            } else {
                FileIcon(url: model.folder.location, size: 16)
                Text((model.folder.location.path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1).truncationMode(.head)
                    .contextMenu {
                        Button("Copiar Caminho", systemImage: "doc.on.doc") { model.copyPath(model.folder.location) }
                        Button("Mostrar no Finder", systemImage: "magnifyingglass") {
                            NSWorkspace.shared.activateFileViewerSelecting([model.folder.location])
                        }
                    }
                CopyPathButton(url: model.folder.location)
                Spacer()
                if model.folder.isLoading { ProgressView().controlSize(.mini) }
                Text(countText).foregroundStyle(.secondary).monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.smooth, value: countText)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var countText: String {
        let folder = model.folder
        let count = folder.visibleItems.count
        if !folder.selection.isEmpty { return String(localized: "\(folder.selection.count) de \(count) selecionados") }
        return count == 1 ? String(localized: "1 item") : String(localized: "\(count) itens")
    }

    private func archiveDescription(_ browser: BrowserModel) -> String {
        var text = browser.archive.lastPathComponent
        if !browser.gridPath.isEmpty { text += " › " + browser.gridPath.replacingOccurrences(of: "/", with: " › ") }
        guard let listing = browser.listing else { return text }
        let size = listing.totalSize.formatted(.number.grouping(.automatic))
        return String(localized: "\(text) — arquivo \(listing.format.displayName), \(listing.fileCount) arquivos, \(size) bytes descompactados")
    }
}

// MARK: - Navigation toolbar

private struct NavigationToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model
    @Binding var viewMode: String
    let searchText: Binding<String>
    var searchFocused: FocusState<Bool>.Binding

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Voltar", systemImage: "chevron.left") { withAnimation(.smooth(duration: 0.22)) { model.goBack() } }
                .disabled(model.browser == nil && !model.folder.canGoBack)
                .keyboardShortcut("[", modifiers: .command)
        }
        ToolbarItem(placement: .navigation) {
            LocationMenu()
        }
        ToolbarItem(placement: .primaryAction) {
            // Finder-style view switcher.
            Picker("Visualização", selection: $viewMode.animation(.smooth(duration: 0.22))) {
                Label("Lista", systemImage: "list.bullet").tag(ViewMode.list.rawValue)
                Label("Ícones", systemImage: "square.grid.2x2").tag(ViewMode.grid.rawValue)
            }
            .pickerStyle(.segmented)
            .help("Mostrar como lista ou ícones (⌘1 / ⌘2)")
        }
        ToolbarItem(placement: .primaryAction) {
            RefreshButton()
        }
        ToolbarItem(placement: .primaryAction) {
            ToolbarSearchField(text: searchText, focused: searchFocused,
                               prompt: model.browser == nil ? "Filtrar pasta" : "Buscar no arquivo")
        }
        ToolbarItem(placement: .primaryAction) {
            SettingsButton()
        }
    }
}

/// Search field placed as a regular toolbar item so other buttons (Settings) can follow it.
private struct ToolbarSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let prompt: LocalizedStringKey

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused(focused)
                .onExitCommand { text = ""; focused.wrappedValue = false }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Limpar")
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 220, height: 30)
        .animation(.smooth(duration: 0.15), value: text.isEmpty)
        .background(Color.clear)
    }
}

/// Gear in the toolbar: opens Settings straight on "Geral", with a badge while something needs attention.
private struct SettingsButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @AppStorage(PrefKey.settingsTab) private var tab = SettingsTab.general.rawValue

    var body: some View {
        Button {
            tab = SettingsTab.general.rawValue
            openSettings()
        } label: {
            Image(systemName: "gearshape")
                .overlay(alignment: .topTrailing) {
                    if model.setup.pendingCount > 0 {
                        Circle().fill(.orange).frame(width: 7, height: 7).offset(x: 3, y: -2)
                    }
                }
        }
        .help(model.setup.pendingCount > 0 ? String(localized: "Ajustes — há itens para ativar") : String(localized: "Ajustes"))
    }
}

/// Glass toolbar button next to the search field; spins once per refresh.
private struct RefreshButton: View {
    @Environment(AppModel.self) private var model
    @State private var turns = 0

    var body: some View {
        Button {
            turns += 1
            if let browser = model.browser { browser.load() } else { model.folder.reload(animated: true) }
        } label: {
            Image(systemName: "arrow.clockwise")
                .symbolEffect(.rotate, value: turns)
        }
        .help("Atualizar (⌘R)")
        .keyboardShortcut("r", modifiers: .command)
    }
}

/// Dropdown with the current location, common folders, recents and "choose another".
private struct LocationMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let location = model.folder.location
        Menu {
            Section("Caminho") {
                ForEach(ancestors(of: location), id: \.self) { url in
                    Button { model.navigate(to: url) } label: {
                        Label { Text(displayName(url)) } icon: { FileIcon(url: url, size: 16) }
                    }
                }
            }
            Section("Locais") {
                ForEach(places, id: \.self) { url in
                    Button { model.navigate(to: url) } label: {
                        Label { Text(displayName(url)) } icon: { FileIcon(url: url, size: 16) }
                    }
                }
            }
            let recents = Recents.all.filter { !places.contains($0) && $0 != location }
            if !recents.isEmpty {
                Section("Recentes") {
                    ForEach(recents, id: \.self) { url in
                        Button(displayName(url)) { model.navigate(to: url) }
                    }
                }
            }
            Divider()
            Button("Escolher Outra Pasta…", systemImage: "folder") { model.chooseLocation() }
        } label: {
            Label {
                Text(title(for: location)).fontWeight(.semibold)
            } icon: {
                Image(nsImage: IconCache.icon(forFile: location))
            }
            .padding(.horizontal, 6)
        }
        .labelStyle(.titleAndIcon)
        .fixedSize()
        .help(location.path(percentEncoded: false))
    }

    private var places: [URL] {
        let fm = FileManager.default
        return [
            fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0],
            fm.urls(for: .desktopDirectory, in: .userDomainMask)[0],
            fm.urls(for: .documentDirectory, in: .userDomainMask)[0],
            fm.homeDirectoryForCurrentUser,
        ]
    }

    private func ancestors(of url: URL) -> [URL] {
        var result: [URL] = []
        var current = url.standardizedFileURL
        while current.path != "/" {
            result.append(current)
            current = current.deletingLastPathComponent()
        }
        result.append(URL(fileURLWithPath: "/"))
        return result
    }

    private func displayName(_ url: URL) -> String {
        FileManager.default.displayName(atPath: url.path)
    }

    private func title(for location: URL) -> String {
        guard let browser = model.browser else { return displayName(location) }
        return String(localized: "\(displayName(location)) › \(browser.archive.lastPathComponent)")
    }
}

// MARK: - Folder contents

private struct FolderContentsView: View {
    @Environment(AppModel.self) private var model
    @Bindable var folder: FolderModel
    let mode: ViewMode

    var body: some View {
        if let error = folder.error {
            ContentUnavailableView {
                Label("Não foi possível abrir esta pasta", systemImage: "lock.trianglebadge.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Escolher Outra Pasta…") { model.chooseLocation() }
            }
        } else if folder.items.isEmpty && !folder.isLoading {
            ContentUnavailableView("Pasta vazia", systemImage: "folder",
                                   description: Text("Arraste arquivos para cá para comprimir, ou arquivos compactados para extrair."))
        } else if mode == .grid {
            grid
        } else {
            list
        }
    }

    private var list: some View {
        Table(folder.visibleItems, selection: $folder.selection, sortOrder: $folder.sortOrder) {
            TableColumn("Nome", value: \.name, comparator: .localizedStandard) { item in
                HStack(spacing: 8) {
                    FileIcon(url: item.url, size: 18)
                        .overlay(alignment: .topTrailing) { FreshBadge(visible: folder.isFresh(item)).offset(x: 4, y: -3) }
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    if folder.isFresh(item) {
                        Text("novo").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
            }
            .width(min: 220, ideal: 380)
            TableColumn("Tamanho", value: \.size) { item in
                Text(item.isDirectory ? "—" : Format.bytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 64, ideal: 84)
            TableColumn("Tipo", value: \.kind) { item in
                Text(item.kind).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 90, ideal: 140)
            TableColumn("Modificado", value: \.modified) { item in
                Text(Format.date(item.modified)).foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            FolderContextMenu(urls: urls)
        } primaryAction: { urls in
            if let url = urls.first, let item = folder.items.first(where: { $0.url == url }) { model.activate(item) }
        }
        .onKeyPress(.return) {
            guard let item = folder.selectedItems.first else { return .ignored }
            model.activate(item)
            return .handled
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112, maximum: 132), spacing: 8)], spacing: 10) {
                ForEach(folder.visibleItems) { item in
                    GridCell(title: item.name, subtitle: item.isDirectory ? nil : Format.bytes(item.size),
                             selected: folder.selection.contains(item.url)) {
                        ThumbnailView(url: item.url, size: 64)
                            .overlay(alignment: .topTrailing) { FreshBadge(visible: folder.isFresh(item), size: 12) }
                    }
                    .simultaneousGesture(TapGesture(count: 2).onEnded { model.activate(item) })
                    .simultaneousGesture(TapGesture().onEnded { select(item.url) })
                    .contextMenu {
                        FolderContextMenu(urls: folder.selection.contains(item.url) ? folder.selection : [item.url])
                    }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .padding(14)
            .animation(.smooth(duration: 0.28), value: folder.visibleItems.map(\.id))
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        // Clicking empty space clears the selection; only this background layer catches it,
        // so taps on items are never undone by it.
        .background(Color(nsColor: .controlBackgroundColor).onTapGesture { folder.selection.removeAll() })
    }

    private func select(_ url: URL) {
        if NSEvent.modifierFlags.contains(.command) {
            if folder.selection.contains(url) { folder.selection.remove(url) } else { folder.selection.insert(url) }
        } else {
            folder.selection = [url]
        }
    }
}

private struct FolderContextMenu: View {
    @Environment(AppModel.self) private var model
    let urls: Set<URL>

    var body: some View {
        let folder = model.folder
        let items = folder.items.filter { urls.contains($0.url) }
        let archives = items.filter(\.isArchive).map(\.url)
        if let first = items.first, items.count == 1 {
            Button("Abrir", systemImage: "arrow.up.forward.app") { model.activate(first) }
        }
        if !archives.isEmpty {
            Divider()
            Button("Extrair Aqui", systemImage: "arrow.down.doc") {
                model.enqueueExtraction(archives, destination: folder.location)
            }
            Button("Extrair Para…", systemImage: "folder.badge.plus") {
                if let destination = Preferences.askForFolder(title: String(localized: "Extrair para"), near: archives.first) {
                    model.enqueueExtraction(archives, destination: destination)
                }
            }
            if archives.count == 1, let only = archives.first {
                Button("Extrair para “\(FileNaming.baseName(of: only))/”", systemImage: "folder") {
                    let target = FileNaming.uniqueURL(in: folder.location, name: FileNaming.baseName(of: only), isDirectory: true)
                    model.enqueueExtraction(archives, destination: target, folderPolicy: .never)
                }
            }
            Button("Testar", systemImage: "checkmark.shield") {
                folder.selection = Set(archives)
                model.testSelection()
            }
            if archives.count == 1, let only = archives.first, case .success = ArchiveRepair.method(for: only) {
                Button("Reparar…", systemImage: "bandage") { model.repair(only) }
            }
        }
        if !items.isEmpty {
            Divider()
            Button("Comprimir…", systemImage: "archivebox") { model.startCompress(items.map(\.url)) }
            Divider()
            Button(items.count == 1 ? "Copiar Caminho" : "Copiar Caminhos", systemImage: "doc.on.doc") {
                model.copyPaths(items.map(\.url))
            }
            Button("Mostrar no Finder", systemImage: "magnifyingglass") {
                NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
            }
            Button("Mover para o Lixo", systemImage: "trash", role: .destructive) {
                folder.selection = urls
                model.trashSelection()
            }
        }
    }
}

// MARK: - Archive contents

private struct ArchiveContentsView: View {
    @Environment(AppModel.self) private var model
    @Bindable var browser: BrowserModel
    let mode: ViewMode

    var body: some View {
        VStack(spacing: 0) {
            if let comment = browser.listing?.comment {
                CommentStrip(comment: comment)
                Divider()
            }
            contents
        }
    }

    @ViewBuilder private var contents: some View {
        Group {
            switch browser.state {
            case .loading:
                ProgressView("Lendo o índice…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .needsPassword:
                ContentUnavailableView("Arquivo protegido", systemImage: "lock.fill",
                                       description: Text("Os nomes dos arquivos são criptografados. Digite a senha para ver o conteúdo."))
            case .failed(let error):
                ContentUnavailableView {
                    Label(error.errorDescription ?? String(localized: "Erro"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.recoverySuggestion ?? "")
                } actions: {
                    Button("Tentar de Novo") { browser.load() }
                }
            case .ready:
                if mode == .grid { grid } else { table }
            }
        }
        .quickLookPreview($browser.previewURL)
        .overlay(alignment: .bottom) {
            if let message = browser.busyMessage {
                Label(message, systemImage: "hourglass")
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: .rect(cornerRadius: 8))
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.2), value: browser.busyMessage)
    }

    private var table: some View {
        Table(browser.visibleRoots, children: \.children, selection: $browser.selection) {
            TableColumn("Nome") { node in
                HStack(spacing: 8) {
                    FileIcon(name: node.name, isDirectory: node.isDirectory, size: 18)
                    Text(node.name).lineLimit(1).truncationMode(.middle)
                    if node.isEncrypted {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .draggable(containerItemID: node.id)
            }
            .width(min: 200, ideal: 320)
            TableColumn("Tamanho") { node in
                Text(Format.bytes(node.size)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 64, ideal: 80)
            TableColumn("Compactado") { node in
                Text(node.packedSize > 0 ? Format.bytes(node.packedSize) : "—").monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 64, ideal: 80)
            TableColumn("Tipo") { node in
                Text(node.kindDescription).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 80, ideal: 110)
            TableColumn("Modificado") { node in
                Text(Format.date(node.modified)).foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 140)
        }
        .dragContainer(for: ArchiveDragItem.self, itemID: \.id) { ids in dragItems(ids) }
        .dragContainerSelection(Array(browser.selection))
        .contextMenu(forSelectionType: String.self) { paths in
            menu(paths)
        } primaryAction: { paths in
            guard let first = paths.first else { return }
            if browser.entry(for: first)?.isDirectory == false { browser.open(first) }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112, maximum: 132), spacing: 8)], spacing: 10) {
                ForEach(browser.gridNodes) { node in
                    GridCell(title: (node.name as NSString).lastPathComponent,
                             subtitle: node.isDirectory ? nil : Format.bytes(node.size),
                             selected: browser.selection.contains(node.id)) {
                        FileIcon(name: node.name, isDirectory: node.isDirectory, size: 64)
                    }
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        if node.isDirectory { browser.enterGridFolder(node) } else { browser.open(node.id) }
                    })
                    .simultaneousGesture(TapGesture().onEnded { select(node.id) })
                    .contextMenu { menu(browser.selection.contains(node.id) ? browser.selection : [node.id]) }
                    .draggable(containerItemID: node.id)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .dragContainer(for: ArchiveDragItem.self, itemID: \.id) { ids in dragItems(ids) }
            .dragContainerSelection(Array(browser.selection))
            .padding(14)
            .animation(.smooth(duration: 0.25), value: browser.gridNodes.map(\.id))
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .controlBackgroundColor).onTapGesture { browser.selection.removeAll() })
    }

    /// Dragging to Finder: each entry is extracted only when dropped.
    private func dragItems(_ ids: [String]) -> [ArchiveDragItem] {
        model.markOwnDrag()
        return ids.map { ArchiveDragItem(id: $0, isDirectory: browser.entry(for: $0)?.isDirectory ?? true, browser: browser) }
    }

    private func select(_ id: String) {
        if NSEvent.modifierFlags.contains(.command) {
            if browser.selection.contains(id) { browser.selection.remove(id) } else { browser.selection.insert(id) }
        } else {
            browser.selection = [id]
        }
    }

    @ViewBuilder private func menu(_ paths: Set<String>) -> some View {
        if !paths.isEmpty {
            Button("Visualizar", systemImage: "eye") { browser.quickLook(paths.first) }
            Button("Abrir", systemImage: "arrow.up.forward.app") { if let first = paths.first { browser.open(first) } }
            Divider()
            Button("Extrair Aqui", systemImage: "arrow.down.doc") {
                model.enqueueExtraction(from: browser, selection: paths, destination: browser.archive.deletingLastPathComponent())
            }
            Button("Extrair Para…", systemImage: "folder.badge.plus") {
                browser.selection = paths
                browser.extract(selectionOnly: true, chooseDestination: true)
            }
            if browser.isEditable {
                Divider()
                Button("Excluir do Arquivo…", systemImage: "trash", role: .destructive) {
                    browser.selection = paths
                    model.deleteFromArchive()
                }
            }
        }
    }
}

/// Small "just created" dot that pops in and fades out.
private struct FreshBadge: View {
    let visible: Bool
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color(nsColor: .controlBackgroundColor), lineWidth: 1.5))
            .scaleEffect(visible ? 1 : 0.2)
            .opacity(visible ? 1 : 0)
            .animation(.spring(duration: 0.4, bounce: 0.5), value: visible)
            .allowsHitTesting(false)
    }
}

/// Small, quiet button next to the path; turns into a check for a moment after copying.
private struct CopyPathButton: View {
    @Environment(AppModel.self) private var model
    let url: URL
    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        Button {
            model.copyPath(url)
            withAnimation(.spring(duration: 0.3)) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.smooth) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption.weight(.medium))
                .foregroundStyle(copied ? Color.green : (hovering ? Color.primary : Color.secondary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 20, height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary).opacity(hovering ? 1 : 0))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Copiar caminho (⌥⌘C)")
    }
}

/// WinRAR-style archive comment, collapsed to one line until expanded.
private struct CommentStrip: View {
    let comment: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.smooth(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble.fill").foregroundStyle(.orange)
                    Text(expanded ? "Comentário do arquivo" : comment.components(separatedBy: .newlines).first ?? comment)
                        .lineLimit(1)
                        .foregroundStyle(expanded ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if expanded {
                // Short comments size to fit; long ones scroll inside a capped height.
                ViewThatFits(in: .vertical) {
                    commentText
                    ScrollView { commentText }
                }
                .frame(maxHeight: 160)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.07))
    }

    private var commentText: some View {
        Text(comment)
            .font(.callout.monospaced())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
