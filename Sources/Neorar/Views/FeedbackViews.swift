import NeorarCore
import SwiftUI

// MARK: - Toasts

struct ToastStack: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.toasts) { toast in
                ToastView(toast: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.bottom, 16)
        .frame(maxWidth: 460)
    }
}

private struct ToastView: View {
    @Environment(AppModel.self) private var model
    let toast: Toast
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .font(.title3)
                .foregroundStyle(toast.color)
                .symbolEffect(.bounce, value: appeared)
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                if let subtitle = toast.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let title = toast.actionTitle, let action = toast.action {
                Button(title) {
                    action()
                    model.dismissToast(toast.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Button {
                model.dismissToast(toast.id)
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .onAppear { appeared = true }
    }
}

// MARK: - Progress panel

/// Centered panel for operations that take longer than a moment; can be sent to the background.
struct ProgressHUD: View {
    @Environment(AppModel.self) private var model
    let job: ExtractionJob

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                FileIcon(url: job.archive, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.mode == .test ? "Testando" : "Extraindo").font(.caption).foregroundStyle(.secondary)
                    Text(job.name).font(.headline).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(job.progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.title2.weight(.semibold)).monospacedDigit()
                    .contentTransition(.numericText(value: job.progress))
                    .animation(.smooth, value: job.progress)
            }
            ProgressView(value: job.progress)
                .progressViewStyle(.linear)
                .animation(.smooth(duration: 0.25), value: job.progress)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack {
                    Text(detail(now: context.date)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                }
            }
            HStack {
                Button("Ocultar") {
                    withAnimation(.smooth(duration: 0.25)) { job.hudDismissed = true }
                }
                .help("Continuar em segundo plano")
                Spacer()
                Button("Cancelar", role: .cancel) { model.cancel(job) }
            }
            .controlSize(.regular)
        }
        .padding(18)
        .frame(width: 400)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
    }

    private func detail(now: Date) -> String {
        if case .preparing = job.state { return String(localized: "Lendo o índice…") }
        var parts: [String] = []
        if job.bytesTotal > 0 { parts.append(String(localized: "\(Format.bytes(job.bytesDone)) de \(Format.bytes(job.bytesTotal))")) }
        if job.speed > 0 {
            parts.append(Format.speed(job.speed))
            if job.bytesTotal > job.bytesDone {
                parts.append(String(localized: "faltam \(Format.duration(Double(job.bytesTotal - job.bytesDone) / job.speed))"))
            }
        }
        if let item = job.currentItem { parts.append((item as NSString).lastPathComponent) }
        if parts.isEmpty, let started = job.startedAt {
            return String(localized: "Processando… \(Format.duration(now.timeIntervalSince(started))) decorridos")
        }
        return parts.isEmpty ? String(localized: "Processando…") : parts.joined(separator: " · ")
    }
}

// MARK: - Conflict

struct ConflictSheet: View {
    @Environment(AppModel.self) private var model
    let request: ConflictRequest
    @State private var applyToAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text("Ao extrair “\(request.archiveName)” em \(request.destination.lastPathComponent).")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if request.names.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(request.names.prefix(6), id: \.self) { name in
                        Label(name, systemImage: "doc").font(.callout).lineLimit(1)
                    }
                    if request.names.count > 6 {
                        Text("e mais \(request.names.count - 6)…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quinary))
            }
            if request.othersPending {
                Toggle("Fazer o mesmo para os próximos arquivos", isOn: $applyToAll)
            }
            HStack {
                Button("Cancelar", role: .cancel) { answer(.cancel) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Substituir", role: .destructive) { answer(.replace) }
                    .help("Os itens atuais vão para o Lixo")
                Button("Manter Ambos") { answer(.keepBoth) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .help("Os novos itens recebem “2” no nome")
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var title: String {
        request.names.count == 1
            ? String(localized: "“\(request.names[0])” já existe")
            : String(localized: "\(request.names.count) itens já existem")
    }

    private func answer(_ choice: ConflictChoice) {
        model.answerConflict(request, choice, applyToAll: applyToAll)
    }
}

// MARK: - Test result

struct TestReportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let report: TestReport
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: report.error == nil ? "checkmark.shield.fill" : "xmark.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(report.error == nil ? .green : .red)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: appeared)
            Text(report.error == nil ? "Arquivo íntegro" : "Arquivo com problemas")
                .font(.headline)
            Text(report.archiveName)
                .font(.callout).lineLimit(1).truncationMode(.middle)
            Text(detail)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if report.error != nil, case .success = ArchiveRepair.method(for: report.archive) {
                    Button("Reparar") {
                        dismiss()
                        model.repair(report.archive)
                    }
                    .help("Cria uma cópia reparada ao lado do original")
                }
                Button("OK") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(width: 300)
        .onAppear { appeared = true }
    }

    private var detail: String {
        if let error = report.error { return error.errorDescription ?? String(localized: "Erro desconhecido.") }
        let files = report.files == 1 ? String(localized: "1 arquivo verificado") : String(localized: "\(report.files) arquivos verificados")
        return String(localized: "\(files) em \(Format.duration(report.elapsed)), nenhum erro encontrado.")
    }
}
