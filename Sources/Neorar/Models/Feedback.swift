import Foundation
import NeorarCore
import SwiftUI

/// Short-lived banner at the bottom of the window confirming what just happened.
struct Toast: Identifiable {
    enum Style { case success, info, error }

    let id = UUID()
    let style: Style
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var symbol: String {
        switch style {
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch style {
        case .success: .green
        case .info: .accentColor
        case .error: .orange
        }
    }
}

enum ConflictChoice {
    case keepBoth, replace, cancel
}

/// "Already exists" question shown before an extraction overwrites anything.
struct ConflictRequest: Identifiable {
    let id = UUID()
    let archiveName: String
    let names: [String]
    let destination: URL
    let othersPending: Bool
    let resolve: (ConflictChoice, Bool) -> Void
}

/// Outcome of "Testar", shown in a compact modal.
struct TestReport: Identifiable {
    let id = UUID()
    let archive: URL
    let archiveName: String
    let files: Int
    let elapsed: TimeInterval
    let error: ArchiveError?
}
