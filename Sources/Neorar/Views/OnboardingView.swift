import SwiftUI

/// One-screen welcome shown on first launch: what Neorar is, and the few things to switch on.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PrefKey.onboardingDone) private var onboardingDone = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Hero
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.pink.opacity(0.35), Color.orange.opacity(0.18), .clear],
                                         center: .center, startRadius: 4, endRadius: 120))
                    .frame(width: 240, height: 240)
                    .blur(radius: 18)
                    .opacity(appeared ? 1 : 0)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                    .scaleEffect(appeared ? 1 : 0.7)
                    .rotationEffect(.degrees(appeared ? 0 : -8))
            }
            .frame(height: 150)
            .padding(.top, 18)

            Text("Bem-vindo ao Neorar")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 4)
            Text("Abra, extraia e comprima RAR, 7Z, ZIP e dezenas de outros formatos, direto do Finder. Falta pouco para tudo ficar pronto:")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
                .padding(.top, 6)

            SetupChecklist(style: .onboarding)
                .padding(.top, 20)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)

            HStack {
                Label("Você pode rever isso em Ajustes › Geral.", systemImage: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.setup.pendingCount == 0 ? "Começar" : "Continuar Depois") {
                    onboardingDone = true
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 24)
        .frame(width: 600)
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.35).delay(0.05)) { appeared = true }
        }
        .animation(.smooth, value: model.setup.pendingCount)
    }
}
