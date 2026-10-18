import NeorarCore
import SwiftUI

/// Compress dialog: a native grouped form with a summary header and a single action footer.
struct CompressSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var dropTargeted = false
    @AppStorage("compressShowAdvanced") private var showAdvanced = false

    var body: some View {
        @Bindable var compress = model.compress
        VStack(spacing: 0) {
            CompressHeader(compress: compress)
            Divider()
            CompressForm(compress: compress, rarAvailable: model.rarTool.isAvailable)
                .disabled(compress.isRunning)
            Divider()
            CompressFooter(compress: compress, rarAvailable: model.rarTool.isAvailable) { dismiss() }
        }
        // Compact by default; grows when "Avançados" is opened.
        .frame(minWidth: 520, idealWidth: 600, maxWidth: 760,
               minHeight: showAdvanced ? 600 : 470, idealHeight: showAdvanced ? 800 : 560, maxHeight: 940)
        .animation(.smooth(duration: 0.3), value: showAdvanced)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .background(Color.accentColor.opacity(0.06), in: .rect(cornerRadius: 10))
                    .padding(6)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        // The whole dialog accepts more items; no separate drop zone needed.
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty, !compress.isRunning else { return false }
            withAnimation(.smooth) { compress.add(files) }
            return true
        } isTargeted: { value in withAnimation(.easeOut(duration: 0.15)) { dropTargeted = value } }
        .onAppear {
            // RAR needs RARLAB's own tool; fall back to the open default when it is missing.
            if compress.options.format == .rar && !model.rarTool.isAvailable { compress.options.format = .sevenZip }
        }
    }
}

// MARK: - Header

private struct CompressHeader: View {
    @Bindable var compress: CompressModel
    @State private var showItems = false

    var body: some View {
        HStack(spacing: 14) {
            IconStack(urls: compress.items)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1).truncationMode(.middle)
                // Small note: what is being compressed, with a quick way to edit the list.
                HStack(spacing: 6) {
                    Text(note)
                        .contentTransition(.numericText())
                        .animation(.smooth, value: note)
                    if !compress.items.isEmpty {
                        Button("Editar itens") { showItems.toggle() }
                            .buttonStyle(.link)
                            .popover(isPresented: $showItems, arrowEdge: .bottom) { ItemsPopover(compress: compress) }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            RibbonGlyphView(glyph: .compress, size: 40,
                            glass: UserDefaults.standard.string(forKey: PrefKey.iconStyle) == IconStyle.glass.rawValue)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var title: String {
        switch compress.items.count {
        case 0: String(localized: "Comprimir")
        case 1: String(localized: "Comprimir “\(compress.items[0].lastPathComponent)”")
        default: String(localized: "Comprimir \(compress.items.count) itens")
        }
    }

    private var note: String {
        guard !compress.items.isEmpty else { return String(localized: "Arraste arquivos e pastas para esta janela") }
        let count = compress.items.count == 1 ? String(localized: "1 item") : String(localized: "\(compress.items.count) itens")
        let folder = compress.items[0].deletingLastPathComponent().lastPathComponent
        return String(localized: "\(count) · \(Format.bytes(compress.totalSize)) · em \(folder)")
    }
}

/// Compact list to remove or add items, opened from the header note.
private struct ItemsPopover: View {
    @Bindable var compress: CompressModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(compress.items, id: \.self) { url in
                        HStack(spacing: 8) {
                            FileIcon(url: url, size: 18)
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Remover", systemImage: "minus.circle.fill") {
                                withAnimation(.smooth) { compress.remove(url) }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .disabled(compress.items.count == 1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .transition(.opacity)
                    }
                }
            }
            .frame(maxHeight: 220)
            Divider()
            Button("Adicionar Itens…", systemImage: "plus") {
                let panel = NSOpenPanel()
                panel.message = "Escolha arquivos e pastas para comprimir"
                panel.prompt = "Adicionar"
                panel.allowsMultipleSelection = true
                panel.canChooseDirectories = true
                panel.directoryURL = compress.destination
                if panel.runModal() == .OK { withAnimation(.smooth) { compress.add(panel.urls) } }
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .frame(width: 300)
        .padding(.top, 6)
    }
}

/// Up to three Finder icons fanned out, like a stack of documents.
private struct IconStack: View {
    let urls: [URL]

    var body: some View {
        ZStack {
            if urls.isEmpty {
                Image(systemName: "doc.on.doc").font(.system(size: 30)).foregroundStyle(.tertiary)
            }
            ForEach(Array(urls.prefix(3).enumerated().reversed()), id: \.element) { index, url in
                FileIcon(url: url, size: 44)
                    .rotationEffect(.degrees(Double(index) * -8))
                    .offset(x: CGFloat(index) * -5, y: CGFloat(index) * -1)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 56, height: 52)
        .animation(.spring(duration: 0.35), value: urls)
    }
}

// MARK: - Form

private struct CompressForm: View {
    @Bindable var compress: CompressModel
    let rarAvailable: Bool
    @AppStorage("compressShowAdvanced") private var showAdvanced = false
    @State private var revealPassword = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Nome") {
                    HStack(spacing: 6) {
                        TextField("Nome", text: Binding(get: { compress.archiveName }, set: { compress.nameChanged($0) }))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: 320)
                        Text(".\(compress.options.format.fileExtension)")
                            .foregroundStyle(.secondary)
                            .monospaced()
                            .contentTransition(.interpolate)
                            .animation(.smooth, value: compress.options.format)
                    }
                }
                LabeledContent("Salvar em") {
                    DestinationMenu(compress: compress)
                }
                if let existing = compress.existingFile {
                    Picker(selection: $compress.replaceExisting) {
                        Text("Manter ambos (salvar como “\(compress.outputURL?.lastPathComponent ?? "")”)").tag(false)
                        Text("Substituir (o atual vai para o Lixo)").tag(true)
                    } label: {
                        Label("“\(existing.lastPathComponent)” já existe", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .pickerStyle(.radioGroup)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Section("Formato") {
                FormatChips(selection: $compress.options.format.animation(.spring(duration: 0.3)), rarAvailable: rarAvailable)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LevelSlider(level: $compress.options.level)
            }

            Section {
                Button {
                    withAnimation(.smooth(duration: 0.3)) { showAdvanced.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
                        Text("Avançados")
                        Spacer()
                        if !showAdvanced, !advancedSummary.isEmpty {
                            Text(advancedSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(showAdvanced ? "Ocultar opções avançadas" : "Senha, divisão em partes e outras opções")
            }

            if showAdvanced {
                securitySection
                    .transition(.opacity.combined(with: .move(edge: .top)))
                commentSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
                optionsSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .animation(.smooth(duration: 0.25), value: compress.options.format)
        .animation(.smooth(duration: 0.25), value: compress.existingFile)
    }

    /// What is switched on inside "Avançados", shown while it is collapsed.
    private var advancedSummary: String {
        var parts: [String] = []
        if compress.usePassword && compress.options.format.supportsPassword { parts.append(String(localized: "Senha")) }
        if compress.options.format.supportsVolumes, let preset = CompressModel.volumePresets.first(where: { $0.id == compress.volumePreset }),
           preset.bytes != nil { parts.append(String(localized: "Partes de \(preset.title)")) }
        if compress.options.recoveryRecord && compress.options.format.supportsRecovery { parts.append(String(localized: "Recuperação")) }
        if compress.options.trashSourcesAfter { parts.append(String(localized: "Originais para o Lixo")) }
        if compress.options.format.supportsComment, !compress.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(String(localized: "Comentário"))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var securitySection: some View {
        Section {
            Toggle(isOn: $compress.usePassword.animation(.smooth)) {
                Label("Proteger com senha", systemImage: "lock.fill")
            }
            .disabled(!compress.options.format.supportsPassword)
            if compress.usePassword && compress.options.format.supportsPassword {
                LabeledContent("Senha") {
                    HStack(spacing: 6) {
                        Group {
                            if revealPassword {
                                TextField("Senha", text: $compress.password)
                            } else {
                                SecureField("Senha", text: $compress.password)
                            }
                        }
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 320)
                        Button(revealPassword ? "Ocultar" : "Mostrar", systemImage: revealPassword ? "eye.slash" : "eye") {
                            revealPassword.toggle()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                .transition(.opacity)
                if compress.options.format.supportsEncryptedNames {
                    Toggle("Ocultar também os nomes dos arquivos", isOn: $compress.options.encryptNames)
                        .transition(.opacity)
                }
            }
        } header: {
            Text("Segurança")
        } footer: {
            if !compress.options.format.supportsPassword {
                Text("Arquivos TAR não suportam senha. Use 7Z ou ZIP para proteger o conteúdo.")
            } else if compress.usePassword && compress.options.format == .zip {
                Text("ZIP usa AES-256, mas os nomes dos arquivos continuam visíveis. Para escondê-los, use 7Z.")
            }
        }
    }

    @ViewBuilder private var commentSection: some View {
        Section {
            // Always editable: the text is kept while switching formats and only written by formats that support it.
            ZStack(alignment: .topLeading) {
                TextEditor(text: $compress.comment)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 72, maxHeight: 140)
                if compress.comment.isEmpty {
                    Text("Texto exibido para quem abrir o arquivo (opcional)")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .allowsHitTesting(false)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.separator, lineWidth: 0.5))

            if !compress.options.format.supportsComment {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
                    Text("O formato \(compress.options.format.title) não guarda comentários. Use ZIP ou RAR para gravá-lo.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Usar ZIP") {
                        withAnimation(.spring(duration: 0.3)) { compress.options.format = .zip }
                    }
                    .controlSize(.small)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            Text("Comentário")
        } footer: {
            if compress.options.format == .zip, compress.volumePreset != "none" {
                Text("Arquivos ZIP divididos em partes não guardam comentário.")
            }
        }
    }

    @ViewBuilder private var optionsSection: some View {
        Section("Opções") {
            if compress.options.format.supportsVolumes {
                Picker("Dividir em partes", selection: $compress.volumePreset) {
                    ForEach(CompressModel.volumePresets) { Text($0.title).tag($0.id) }
                }
            }
            if compress.options.format.supportsSolid {
                Toggle(isOn: $compress.options.solid) {
                    Text("Compressão sólida")
                    Text("Arquivo menor; extrair um único item fica mais lento.")
                }
            }
            if compress.options.format.supportsRecovery {
                Toggle("Registro de recuperação", isOn: $compress.options.recoveryRecord)
            }
            Toggle(isOn: $compress.options.excludeMacJunk) {
                Text("Ignorar arquivos ocultos do macOS")
                Text(".DS_Store, __MACOSX e ._*")
            }
            Toggle("Mover os originais para o Lixo ao terminar", isOn: $compress.options.trashSourcesAfter)
        }
    }
}

/// Destination as a Finder-style popup: the items' folder, common places, or another folder.
private struct DestinationMenu: View {
    @Bindable var compress: CompressModel

    var body: some View {
        let current = compress.destination ?? compress.items.first?.deletingLastPathComponent()
        Menu {
            if let source = compress.items.first?.deletingLastPathComponent() {
                Button { compress.destination = source } label: {
                    Label { Text("Mesma pasta dos itens (\(source.lastPathComponent))") } icon: { FileIcon(url: source, size: 16) }
                }
            }
            Divider()
            ForEach(places, id: \.self) { url in
                Button { compress.destination = url } label: {
                    Label { Text(FileManager.default.displayName(atPath: url.path)) } icon: { FileIcon(url: url, size: 16) }
                }
            }
            Divider()
            Button("Outra Pasta…") { compress.chooseDestination() }
        } label: {
            if let current {
                Label { Text(FileManager.default.displayName(atPath: current.path)) } icon: { FileIcon(url: current, size: 16) }
            } else {
                Text("Escolher…")
            }
        }
        .fixedSize()
        .help(current?.path(percentEncoded: false) ?? "")
    }

    private var places: [URL] {
        let fm = FileManager.default
        return [fm.urls(for: .desktopDirectory, in: .userDomainMask)[0],
                fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0],
                fm.urls(for: .documentDirectory, in: .userDomainMask)[0]]
    }
}

/// Six-step compression level slider with named stops.
private struct LevelSlider: View {
    @Binding var level: CompressionLevel

    var body: some View {
        LabeledContent("Compressão") {
            VStack(alignment: .trailing, spacing: 2) {
                Slider(
                    value: Binding(get: { Double(level.rawValue) },
                                   set: { level = CompressionLevel(rawValue: Int($0.rounded())) ?? .normal }),
                    in: 0...Double(CompressionLevel.allCases.count - 1),
                    step: 1
                ) {
                    Text("Compressão")
                } minimumValueLabel: {
                    Image(systemName: "hare").help("Mais rápida")
                } maximumValueLabel: {
                    Image(systemName: "tortoise").help("Menor arquivo")
                }
                .labelsHidden()
                .frame(maxWidth: 260)
                Text(level.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.smooth, value: level)
            }
        }
    }
}

// MARK: - Footer

private struct CompressFooter: View {
    @Bindable var compress: CompressModel
    let rarAvailable: Bool
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            switch compress.state {
            case .running(let progress):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Comprimindo em \(compress.options.format.title)… \(progress.formatted(.percent.precision(.fractionLength(0))))")
                        .font(.callout).monospacedDigit()
                    ProgressView(value: progress)
                        .animation(.smooth, value: progress)
                }
                .transition(.opacity)
                Button("Parar") { compress.cancel() }
                    .keyboardShortcut(.cancelAction)
            case .failed(let error):
                Label(error.errorDescription ?? String(localized: "Erro"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .lineLimit(2)
                Spacer()
                buttons
            default:
                if let output = compress.outputURL, !compress.items.isEmpty {
                    Text(output.lastPathComponent)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .help("Será criado como \(output.path(percentEncoded: false))")
                }
                Spacer()
                buttons
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .animation(.smooth(duration: 0.25), value: compress.isRunning)
    }

    @ViewBuilder private var buttons: some View {
        Button("Cancelar", action: close)
            .keyboardShortcut(.cancelAction)
        Button("Comprimir") { compress.start() }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canStart)
    }

    private var canStart: Bool {
        if compress.items.isEmpty { return false }
        if compress.options.format == .rar && !rarAvailable { return false }
        if compress.usePassword && compress.options.format.supportsPassword && compress.password.isEmpty { return false }
        return true
    }
}

// MARK: - Format chips

/// Native-looking segmented control. RAR sits last and stays disabled unless RARLAB's own rar is installed,
/// because creating RAR archives is reserved to RARLAB.
struct FormatChips: View {
    @Binding var selection: CompressionFormat
    let rarAvailable: Bool
    @Namespace private var highlight
    @State private var showRarInfo = false

    static let rarNotice = "RAR é um formato proprietário da RARLAB. Por direitos autorais, o Neorar não pode criar arquivos .rar, só abri-los e extraí-los. Use 7Z (recomendado) ou ZIP. Se você tiver o rar oficial licenciado, ative em Ajustes › RAR."

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CompressionFormat.allCases) { format in
                chip(format)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.7)))
        .popover(isPresented: $showRarInfo, arrowEdge: .bottom) {
            Text(Self.rarNotice)
                .font(.callout)
                .frame(width: 300)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
        }
    }

    private func chip(_ format: CompressionFormat) -> some View {
        let disabled = format == .rar && !rarAvailable
        let selected = selection == format
        return HStack(spacing: 4) {
            Text(format.title)
                .font(.callout.weight(selected ? .semibold : .regular))
            if disabled {
                Image(systemName: "info.circle").font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .foregroundStyle(selected ? Color.white : (disabled ? Color.secondary : Color.primary))
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.gradient)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                    .matchedGeometryEffect(id: "chip", in: highlight)
            }
        }
        .contentShape(.rect(cornerRadius: 5))
        .onTapGesture {
            if disabled { showRarInfo = true } else { selection = format }
        }
        .opacity(disabled ? 0.6 : 1)
        .help(disabled ? Self.rarNotice : (format == .sevenZip ? "7Z — recomendado: melhor compressão e senha com nomes ocultos" : format.title))
    }
}
