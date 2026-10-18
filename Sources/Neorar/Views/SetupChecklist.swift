import SwiftUI

/// The list of things Neorar needs from macOS, each with a live status and a one-click fix.
/// Used by the welcome screen (large) and Settings › Geral (compact).
struct SetupChecklist: View {
    enum Style { case onboarding, settings }

    @Environment(AppModel.self) private var model
    var style: Style = .settings

    var body: some View {
        let setup = model.setup
        VStack(spacing: style == .onboarding ? 10 : 0) {
            SetupRow(style: style, symbol: "contextualmenu.and.cursorarrow", tint: .blue,
                     title: "Menu do Finder",
                     detail: "Extrair com Neorar e Comprimir com Neorar no clique direito do Finder.",
                     done: setup.finderExtension, actionTitle: "Ativar…") { setup.enableFinderExtension() }
            divider
            SetupRow(style: style, symbol: "arrow.down.circle.fill", tint: .teal,
                     title: "Acesso à pasta Downloads",
                     detail: "O Neorar abre direto em Downloads para você começar.",
                     done: setup.downloadsAccess, actionTitle: "Permitir…") { setup.requestDownloads() }
            divider
            SetupRow(style: style, symbol: "doc.zipper", tint: .purple,
                     title: "Abrir RAR e 7Z com o Neorar",
                     detail: "Dois cliques num arquivo RAR ou 7Z no Finder abrem o Neorar.",
                     done: setup.defaultApp, busy: setup.settingDefault, actionTitle: "Definir") { setup.makeDefault() }
            divider
            SetupRow(style: style, symbol: "seal.fill", tint: .orange,
                     title: "Criar arquivos RAR (opcional)",
                     detail: "Usa o rar oficial da RARLAB, que tem licença própria.",
                     done: model.rarTool.isAvailable, optional: true, actionTitle: "Instalar…") { model.rarTool.install() }
        }
        .animation(.spring(duration: 0.4, bounce: 0.3), value: setup.finderExtension)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: setup.downloadsAccess)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: setup.defaultApp)
    }

    @ViewBuilder private var divider: some View {
        if style == .settings { Divider().padding(.leading, 40) }
    }
}

private struct SetupRow: View {
    let style: SetupChecklist.Style
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let done: Bool
    var busy = false
    var optional = false
    let actionTitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: style == .onboarding ? 17 : 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: style == .onboarding ? 36 : 28, height: style == .onboarding ? 36 : 28)
                .background(RoundedRectangle(cornerRadius: style == .onboarding ? 9 : 7).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(style == .onboarding ? .body.weight(.semibold) : .body)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            if done {
                Label(optional ? "Ativo" : "Pronto", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: done)
                    .transition(.scale.combined(with: .opacity))
            } else if busy {
                ProgressView().controlSize(.small)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.glass)
                    .controlSize(style == .onboarding ? .regular : .small)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, style == .onboarding ? 10 : 7)
        .padding(.horizontal, style == .onboarding ? 14 : 0)
        .background {
            if style == .onboarding {
                RoundedRectangle(cornerRadius: 12)
                    .fill(done ? Color.green.opacity(0.07) : Color.primary.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(done ? Color.green.opacity(0.25) : Color.primary.opacity(0.08)))
            }
        }
    }
}
