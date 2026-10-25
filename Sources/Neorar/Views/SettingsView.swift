import FinderSync
import NeorarCore
import SwiftUI

enum SettingsTab: String {
    case general, extraction, compression, rar, about
}

struct SettingsView: View {
    @AppStorage(PrefKey.settingsTab) private var tab = SettingsTab.general.rawValue

    var body: some View {
        TabView(selection: $tab) {
            Tab("Geral", systemImage: "gearshape", value: SettingsTab.general.rawValue) { GeneralSettings() }
            Tab("Extração", systemImage: "arrow.down.doc", value: SettingsTab.extraction.rawValue) { ExtractionSettings() }
            Tab("Compressão", systemImage: "archivebox", value: SettingsTab.compression.rawValue) { CompressionSettings() }
            Tab("RAR", systemImage: "seal", value: SettingsTab.rar.rawValue) { RarSettings() }
            Tab("Sobre", systemImage: "info.circle", value: SettingsTab.about.rawValue) { AboutSettings() }
        }
        .frame(width: 600, height: 580)
        .scenePadding()
    }
}

private struct GeneralSettings: View {
    @AppStorage(PrefKey.openBehavior) private var openBehavior = OpenBehavior.extract.rawValue
    @AppStorage(PrefKey.revealAfter) private var revealAfter = false
    @AppStorage(PrefKey.maxConcurrent) private var maxConcurrent = 2
    @AppStorage(PrefKey.iconStyle) private var iconStyle = IconStyle.color.rawValue
    @AppStorage(PrefKey.theme) private var theme = AppTheme.system.rawValue
    @AppStorage(PrefKey.finderCompress) private var finderCompress = FinderCompressMode.sevenZip.rawValue
    @AppStorage(PrefKey.finderShowExtract) private var finderShowExtract = true
    @AppStorage(PrefKey.finderShowCompress) private var finderShowCompress = true
    @Environment(AppModel.self) private var model
    @State private var language = AppLanguage.current
    @State private var languageChanged = false

    var body: some View {
        Form {
            // First: whatever macOS still needs to allow, so problems are seen before anything else.
            Section {
                SetupChecklist(style: .settings)
            } header: {
                HStack {
                    Text("Sistema")
                    Spacer()
                    if model.setup.pendingCount == 0 {
                        Label("Tudo pronto", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else {
                        Label(model.setup.pendingCount == 1 ? "1 pendência" : "\(model.setup.pendingCount) pendências",
                              systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.callout)
            }

            Section("Aparência") {
                Picker("Tema", selection: $theme) {
                    Text("Sistema").tag(AppTheme.system.rawValue)
                    Text("Claro").tag(AppTheme.light.rawValue)
                    Text("Escuro").tag(AppTheme.dark.rawValue)
                }
                .pickerStyle(.segmented)
                .onChange(of: theme) { _, value in (AppTheme(rawValue: value) ?? .system).apply() }
                LabeledContent("Ícones da barra") {
                    HStack(spacing: 10) {
                        IconStyleOption(title: "Coloridos", glass: false, selected: iconStyle == IconStyle.color.rawValue) {
                            iconStyle = IconStyle.color.rawValue
                        }
                        IconStyleOption(title: "Vidro", glass: true, selected: iconStyle == IconStyle.glass.rawValue) {
                            iconStyle = IconStyle.glass.rawValue
                        }
                    }
                }
            }

            Section {
                Picker("Idioma", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: language) { _, value in
                    value.apply()
                    languageChanged = true
                }
                if languageChanged {
                    HStack {
                        Label("O novo idioma vale depois de reabrir o Neorar.", systemImage: "arrow.clockwise.circle")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reabrir Agora") { relaunch() }
                    }
                    .transition(.opacity)
                }
            } header: {
                Text("Idioma")
            }

            Section {
                Toggle(isOn: $finderShowExtract) {
                    Text("Mostrar “Extrair com Neorar”")
                    Text("Nunca espalha vários arquivos na pasta: eles vão para uma pasta com o nome do arquivo compactado. Um único item é extraído direto.")
                }
                Toggle("Mostrar “Comprimir com Neorar”", isOn: $finderShowCompress)
                Picker("Formato ao comprimir pelo Finder", selection: $finderCompress) {
                    ForEach(FinderCompressMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                        if mode == .ask { Divider() }
                    }
                }
                .disabled(!finderShowCompress)
            } header: {
                Text("Menu do Finder")
            } footer: {
                Text("Os itens aparecem no clique direito do Finder, junto com os de outros apps. O menu “Comprimir” do próprio macOS não pode ser removido.")
            }
            .onChange(of: finderShowExtract) { Preferences.broadcastFinderMenu() }
            .onChange(of: finderShowCompress) { Preferences.broadcastFinderMenu() }

            Section("Comportamento") {
                Picker("Ao abrir um arquivo compactado", selection: $openBehavior) {
                    ForEach(OpenBehavior.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Mostrar o resultado no Finder ao terminar", isOn: $revealAfter)
                Stepper("Extrações simultâneas: \(maxConcurrent)", value: $maxConcurrent, in: 1...6)
            }
        }
        .formStyle(.grouped)
        .animation(.smooth, value: languageChanged)
    }

    private func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// Small preview tile for choosing the action-bar icon style.
private struct IconStyleOption: View {
    let title: LocalizedStringKey
    let glass: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: -6) {
                    RibbonGlyphView(glyph: .compress, size: 28, glass: glass)
                    RibbonGlyphView(glyph: .extractTo, size: 28, glass: glass)
                    RibbonGlyphView(glyph: .preview, size: 28, glass: glass)
                }
                Text(title).font(.caption)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.15) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25),
                                                                    lineWidth: selected ? 2 : 1))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.2), value: selected)
    }
}

private struct ExtractionSettings: View {
    @AppStorage(PrefKey.destinationMode) private var destinationMode = DestinationMode.sameFolder.rawValue
    @AppStorage(PrefKey.customDestination) private var customDestination = ""
    @AppStorage(PrefKey.folderPolicy) private var folderPolicy = FolderPolicy.smart.rawValue
    @AppStorage(PrefKey.conflictPolicy) private var conflictPolicy = ConflictPolicy.rename.rawValue
    @AppStorage(PrefKey.folderDate) private var folderDate = DateChoice.now.rawValue
    @AppStorage(PrefKey.fileDates) private var fileDates = DateChoice.original.rawValue
    @AppStorage(PrefKey.trashArchive) private var trashArchive = false
    @AppStorage(PrefKey.removeJunk) private var removeJunk = true
    @AppStorage(PrefKey.codePage) private var codePage = 0

    var body: some View {
        Form {
            Section("Destino") {
                Picker("Extrair para", selection: $destinationMode) {
                    ForEach(DestinationMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if destinationMode == DestinationMode.custom.rawValue {
                    LabeledContent("Pasta") {
                        HStack {
                            Text(customDestination.isEmpty ? "Nenhuma" : (customDestination as NSString).abbreviatingWithTildeInPath)
                                .lineLimit(1).truncationMode(.head).foregroundStyle(.secondary)
                            Button("Escolher…") {
                                if let url = Preferences.askForFolder(title: String(localized: "Pasta padrão para extrair"), near: nil) {
                                    customDestination = url.path
                                }
                            }
                        }
                    }
                }
                Picker("Criar pasta com o nome do arquivo", selection: $folderPolicy) {
                    // "Nunca" is not offered: extracting must never scatter many files in a folder.
                    Text(FolderPolicy.smart.title).tag(FolderPolicy.smart.rawValue)
                    Text(FolderPolicy.always.title).tag(FolderPolicy.always.rawValue)
                }
                Picker("Se já existir", selection: $conflictPolicy) {
                    ForEach(ConflictPolicy.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }
            Section("Datas") {
                Picker("Data da pasta criada", selection: $folderDate) {
                    Text("Data atual").tag(DateChoice.now.rawValue)
                    Text("Data do arquivo compactado").tag(DateChoice.original.rawValue)
                }
                Picker("Data dos arquivos extraídos", selection: $fileDates) {
                    Text("Manter a original").tag(DateChoice.original.rawValue)
                    Text("Usar a data atual").tag(DateChoice.now.rawValue)
                }
            }
            Section("Depois de extrair") {
                Toggle("Mover o arquivo compactado (e todos os volumes) para o Lixo", isOn: $trashArchive)
                Toggle("Remover __MACOSX e .DS_Store", isOn: $removeJunk)
            }
            Section("Nomes de arquivos em ZIP") {
                Picker("Codificação", selection: $codePage) {
                    Text("Detectar automaticamente").tag(0)
                    Divider()
                    ForEach(ZipEncodingDetector.choices) { Text($0.name).tag($0.codePage) }
                }
                Text("Use quando ZIPs criados no Windows em japonês, chinês, russo etc. mostrarem nomes estranhos.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CompressionSettings: View {
    @AppStorage(PrefKey.compressFormat) private var format = CompressionFormat.sevenZip.rawValue
    @AppStorage(PrefKey.compressLevel) private var level = CompressionLevel.normal.rawValue
    @AppStorage(PrefKey.compressExcludeJunk) private var excludeJunk = true
    @AppStorage(PrefKey.compressSolid) private var solid = true

    var body: some View {
        Form {
            Picker("Formato padrão", selection: $format) {
                ForEach(CompressionFormat.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Picker("Compressão padrão", selection: $level) {
                ForEach(CompressionLevel.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Toggle("Arquivos sólidos (RAR e 7Z)", isOn: $solid)
            Toggle("Ignorar arquivos do macOS (.DS_Store, __MACOSX, ._*)", isOn: $excludeJunk)
            Text("Os padrões valem para novas compactações.").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct RarSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    switch model.rarTool.status {
                    case .checking: ProgressView().controlSize(.small)
                    case .available(_, let version): Label(version, systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    case .missing: Label("Não instalado", systemImage: "xmark.seal").foregroundStyle(.orange)
                    case .installing: Label("Instalando…", systemImage: "arrow.down.circle")
                    case .failed(let message): Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
                if case .available(let path, _) = model.rarTool.status {
                    LabeledContent("Local") {
                        Text((path.path as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.head)
                            .foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                HStack {
                    Button(model.rarTool.isAvailable ? "Reinstalar a Versão Mais Recente…" : "Instalar rar da RARLAB…") {
                        model.rarTool.install()
                    }
                    Button("Localizar…") { model.rarTool.locate() }
                    Button("Detectar Automaticamente") { model.rarTool.resetToAutomatic() }
                }
            } header: {
                Text("Ferramenta rar (criação de arquivos RAR)")
            } footer: {
                Text("A extração de RAR é feita pelo próprio Neorar com o código-fonte oficial do UnRAR e não depende desta ferramenta. Criar RAR exige o rar da RARLAB: shareware, gratuito por 40 dias e depois com licença paga em rarlab.com. Uma chave rarreg.key colocada junto do executável ativa a licença.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

/// Centered and quiet, like About This Mac, with every third-party notice one click away.
private struct AboutSettings: View {
    @State private var showLicenses = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return String(localized: "Versão \(short) (\(build))")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                    .padding(.bottom, 18)
                Text(verbatim: "NeoRAR")
                    .font(.system(size: 24, weight: .semibold))
                Text(version)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 4)

                Text("O NeoRAR abre, extrai e comprime arquivos no Mac: RAR (inclusive volumes e senha), 7Z, ZIP, TAR e dezenas de outros formatos. Também testa, repara e edita arquivos compactados, sem sair do Finder.")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 460)
                    .padding(.top, 26)

                Text("O NeoRAR é software livre sob a GNU GPL v3.0. Ele se apoia nos projetos de código aberto listados nas licenças.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .padding(.top, 14)

                HStack(spacing: 18) {
                    Link("witchmymac.com", destination: URL(string: "http://witchmymac.com")!)
                        .font(.system(size: 12))
                    Button("Licenças de código aberto") { showLicenses = true }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
                .padding(.top, 10)

                CheckForUpdatesButton()
                    .controlSize(.small)
                    .padding(.top, 14)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.never)
        .sheet(isPresented: $showLicenses) { LicensesSheet() }
    }
}

/// Full notices of the third-party code that ships inside Neorar, as their licenses require.
private struct LicensesSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Entry: Identifiable {
        let id: String
        let name: String
        let license: String
        let text: String
    }

    private var entries: [Entry] {
        [
            Entry(id: "neorar", name: "NeoRAR", license: "GNU General Public License v3.0", text: Self.neorar),
            Entry(id: "unrar", name: "UnRAR 7.30", license: "UnRAR License",
                  text: bundled("UnRAR-license") ?? "UnRAR source code may be used in any software to handle RAR archives without limitations free of charge, but cannot be used to develop RAR (WinRAR) compatible archiver and to re-create RAR compression algorithm, which is proprietary."),
            Entry(id: "7zip", name: "7-Zip 26.04", license: "GNU LGPL 2.1 · BSD 3-Clause · unRAR restriction",
                  text: bundled("7-Zip-License") ?? "7-Zip Copyright (C) 1999-2026 Igor Pavlov. Licensed under the GNU LGPL. https://www.7-zip.org/license.txt"),
            Entry(id: "libarchive", name: "libarchive", license: "BSD 2-Clause", text: Self.libarchive),
            Entry(id: "sparkle", name: "Sparkle", license: "MIT License", text: Self.sparkle),
            Entry(id: "rar", name: "rar (RARLAB)", license: "Shareware — não incluído", text: Self.rarNote),
            Entry(id: "unar", name: "unar / lsar (The Unarchiver)", license: "GNU LGPL 2.1 — não incluído", text: Self.unarNote),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Licenças de código aberto").font(.title3.weight(.semibold))
                Spacer()
                Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("O NeoRAR inclui ou usa os componentes abaixo. Os avisos de copyright e as licenças ficam aqui, como essas licenças exigem.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.name).font(.headline)
                                Text(entry.license).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Spacer()
                            }
                            Text(entry.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 640, height: 560)
    }

    private func bundled(_ name: String) -> String? {
        Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Licenses")
            .flatMap { url in
                (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1))
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static let neorar = """
    Copyright (C) 2026 Matheus Faria
    Source code: https://github.com/matthfaria96/Neorar

    NeoRAR is free software: you can redistribute it and/or modify it under \
    the terms of the GNU General Public License as published by the Free \
    Software Foundation, either version 3 of the License, or (at your option) any \
    later version. It is distributed WITHOUT ANY WARRANTY; without even the implied \
    warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

    The rar command-line tool is not covered by this license: it is RARLAB's own \
    software and is not bundled with NeoRAR.

    Full license text: https://www.gnu.org/licenses/gpl-3.0.html
    """

    private static let libarchive = """
    Copyright (c) 2003-2018 Tim Kientzle and contributors
    All rights reserved.

    Redistribution and use in source and binary forms, with or without modification,     are permitted provided that the following conditions are met:

    1. Redistributions of source code must retain the above copyright notice, this     list of conditions and the following disclaimer in this position and unchanged.
    2. Redistributions in binary form must reproduce the above copyright notice,     this list of conditions and the following disclaimer in the documentation     and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) ``AS IS'' AND ANY EXPRESS OR IMPLIED     WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF     MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT     SHALL THE AUTHOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,     EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT     OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS     INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,     STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY     OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

    Neorar uses the copy of libarchive that ships with macOS (/usr/lib/libarchive.2.dylib).
    """

    private static let sparkle = """
    Copyright (c) 2006-2013 Andy Matuschak. Copyright (c) 2009-2013 Elgato Systems GmbH. \
    Copyright (c) 2011-2014 Kornel Lesiński. Copyright (c) 2015-2017 Mayur Pawashe. \
    Copyright (c) 2014 C.W. Betts. Copyright (c) 2014 Petroules Corporation. \
    Copyright (c) 2014 Big Nerd Ranch. All rights reserved.
    Source code: https://github.com/sparkle-project/Sparkle

    Permission is hereby granted, free of charge, to any person obtaining a copy \
    of this software and associated documentation files (the "Software"), to deal \
    in the Software without restriction, including without limitation the rights \
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
    copies of the Software, and to permit persons to whom the Software is \
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all \
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
    SOFTWARE.
    """

    private static let rarNote = """
    The rar command-line tool is RARLAB's proprietary software and is not bundled with Neorar.     When the user asks, Neorar downloads the official build from rarlab.com into     ~/Library/Application Support/Neorar/RAR. Its use is governed by RARLAB's own license     (40-day trial, then a paid license). https://www.rarlab.com
    """

    private static let unarNote = """
    The Unarchiver's command-line tools (unar, lsar) are not bundled. If installed separately     (for example with Homebrew), Neorar can use them for legacy formats. They are distributed     under the GNU Lesser General Public License v2.1. https://theunarchiver.com
    """
}
