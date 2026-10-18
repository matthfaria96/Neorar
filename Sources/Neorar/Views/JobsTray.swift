import NeorarCore
import SwiftUI

/// Bottom panel listing extractions, shown only while there is something to show.
struct JobsTray: View {
    @Environment(AppModel.self) private var model
    @State private var expanded = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.smooth(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                        .frame(width: 16)
                }
                .buttonStyle(.borderless)
                Text(title).font(.subheadline.weight(.semibold))
                if !model.activeJobs.isEmpty {
                    ProgressView(value: overall).frame(width: 120)
                }
                Spacer()
                Button("Limpar Concluídos") { model.clearFinished() }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                    .disabled(!model.jobs.contains(where: \.isDone))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if expanded {
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.trayJobs) { job in
                            JobRow(job: job)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            if job.id != model.trayJobs.last?.id { Divider().padding(.leading, 48) }
                        }
                    }
                    .animation(.smooth(duration: 0.3), value: model.trayJobs.map(\.id))
                }
                .frame(maxHeight: min(CGFloat(model.trayJobs.count) * 54, 220))
            }
        }
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var title: String {
        let active = model.trayJobs.filter { $0.isActive || $0.isWaiting }.count
        return active > 0 ? String(localized: "Processando \(active) de \(model.trayJobs.count)") : String(localized: "Atividades (\(model.trayJobs.count))")
    }

    private var overall: Double {
        let active = model.activeJobs
        return active.map(\.progress).reduce(0, +) / Double(max(1, active.count))
    }
}

private struct JobRow: View {
    @Environment(AppModel.self) private var model
    let job: ExtractionJob

    var body: some View {
        HStack(spacing: 10) {
            FileIcon(url: job.archive, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if job.mode == .test {
                    Image(systemName: "checkmark.shield").font(.caption).foregroundStyle(.secondary)
                }
                Text(job.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    if job.volumeCount > 1 {
                        Text("\(job.volumeCount) volumes").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                status
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    @ViewBuilder private var status: some View {
        switch job.state {
        case .waiting:
            Text("Na fila").font(.caption).foregroundStyle(.secondary)
        case .preparing:
            Text(job.awaitingDecision ? "Aguardando sua escolha…" : job.mode == .test ? "Preparando o teste…" : "Lendo o índice…").font(.caption).foregroundStyle(.secondary)
        case .extracting:
            HStack(spacing: 8) {
                GlassProgressBar(value: job.progress, height: 5).frame(maxWidth: 260)
                Text(detail).font(.caption).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            }
        case .needsPassword(let wrong):
            Label(wrong ? "Senha incorreta" : "Aguardando a senha", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.orange)
        case .finished(let result):
            Label(finishedText(result), systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.secondary)
                .symbolRenderingMode(.multicolor)
        case .verified(let files):
            Label("Teste concluído: nenhum erro em \(files) arquivos", systemImage: "checkmark.shield.fill")
                .font(.caption).foregroundStyle(.green)
        case .failed(let error):
            Label((error.errorDescription ?? String(localized: "Erro")) + (error.recoverySuggestion.map { " \($0)" } ?? ""),
                  systemImage: "xmark.octagon.fill")
                .font(.caption).foregroundStyle(.red).lineLimit(2)
        case .cancelled:
            Text("Cancelado").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        var parts = [job.progress.formatted(.percent.precision(.fractionLength(0)))]
        if job.bytesTotal > 0 { parts.append(String(localized: "\(Format.bytes(job.bytesDone)) de \(Format.bytes(job.bytesTotal))")) }
        if job.speed > 0 { parts.append(Format.speed(job.speed)) }
        return parts.joined(separator: " · ")
    }

    private func finishedText(_ result: ExtractionResult) -> String {
        guard let target = result.revealTarget else { return String(localized: "Arquivo vazio") }
        let elapsed = (job.finishedAt ?? Date()).timeIntervalSince(job.startedAt ?? Date())
        return String(localized: "Extraído em “\(target.deletingLastPathComponent().lastPathComponent)” · \(Format.duration(elapsed))")
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 2) {
            switch job.state {
            case .waiting, .preparing, .extracting, .needsPassword:
                Button("Cancelar", systemImage: "xmark.circle.fill") { model.cancel(job) }
            case .finished(let result):
                if let target = result.revealTarget {
                    Button("Mostrar", systemImage: "magnifyingglass.circle.fill") {
                        if model.folder.location.standardizedFileURL != target.deletingLastPathComponent().standardizedFileURL {
                            model.navigate(to: target.deletingLastPathComponent())
                        } else {
                            model.browser = nil
                        }
                        model.folder.selection = [target]
                    }
                    .help("Mostrar na lista")
                }
                Button("Remover", systemImage: "minus.circle.fill") { model.remove(job) }
            case .verified:
                Button("Remover", systemImage: "minus.circle.fill") { model.remove(job) }
            case .failed(let error):
                if case .cannotWrite = error {
                    Button("Outro Destino", systemImage: "folder.circle.fill") {
                        if let folder = Preferences.askForFolder(title: String(localized: "Extrair “\(job.name)” para"), near: job.archive) {
                            model.retry(job, destination: folder)
                        }
                    }
                }
                Button("Tentar de Novo", systemImage: "arrow.clockwise.circle.fill") { model.retry(job) }
                Button("Remover", systemImage: "minus.circle.fill") { model.remove(job) }
            case .cancelled:
                Button("Tentar de Novo", systemImage: "arrow.clockwise.circle.fill") { model.retry(job) }
                Button("Remover", systemImage: "minus.circle.fill") { model.remove(job) }
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.title3)
        .foregroundStyle(.secondary)
    }
}
