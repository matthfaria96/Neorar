import SwiftUI

struct PasswordSheet: View {
    @Environment(AppModel.self) private var model
    let request: PasswordRequest
    @State private var password = ""
    @State private var reveal = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: request.wrong ? "lock.trianglebadge.exclamationmark.fill" : "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(request.wrong ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
                .symbolEffect(.wiggle, value: request.wrong)
                .frame(width: 76, height: 76)
                .glassEffect(.regular, in: .circle)

            VStack(spacing: 6) {
                Text(request.wrong ? "Senha incorreta" : "Arquivo protegido").font(.title3.weight(.semibold))
                Text("Digite a senha de “\(request.archiveName)”.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 6) {
                Group {
                    if reveal {
                        TextField("Senha", text: $password)
                    } else {
                        SecureField("Senha", text: $password)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(submit)
                Button(reveal ? "Ocultar" : "Mostrar", systemImage: reveal ? "eye.slash" : "eye") { reveal.toggle() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                if !model.recentPasswords.isEmpty {
                    Menu {
                        ForEach(Array(model.recentPasswords.enumerated()), id: \.offset) { index, value in
                            Button("Senha recente \(index + 1) (\(value.count) caracteres)") { password = value; submit() }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Senhas usadas nesta sessão")
                }
            }
            .frame(width: 320)

            HStack {
                Button("Cancelar", role: .cancel) { model.resolvePassword(request, with: nil) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Continuar") { submit() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
            .frame(width: 320)
        }
        .padding(28)
        .onAppear { focused = true }
        .onChange(of: reveal) { focused = true }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        model.resolvePassword(request, with: password)
    }
}
