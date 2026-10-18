import Foundation
import NeorarCore
import Observation

@Observable
final class ExtractionJob: Identifiable {
    enum State {
        case waiting
        case preparing
        case extracting
        case needsPassword(wrong: Bool)
        case finished(ExtractionResult)
        case verified(files: Int)
        case failed(ArchiveError)
        case cancelled
    }

    enum Mode { case extract, test }

    /// Where the request came from; Finder-originated work finishes in Finder, not in Neorar's window.
    enum Origin { case app, finderOpen, finderMenu }

    let id = UUID()
    let archive: URL
    var mode: Mode = .extract
    var origin: Origin = .app
    let volumeCount: Int
    var state: State = .waiting
    var progress: Double = 0
    var bytesDone: UInt64 = 0
    var bytesTotal: UInt64 = 0
    var speed: Double = 0
    var currentItem: String?
    var startedAt: Date?
    /// Progress panel state: shown after a short delay, hideable to the activity list.
    var hudVisible = false
    var hudDismissed = false
    var awaitingDecision = false
    var finishedAt: Date?

    // Inputs
    var password: String?
    var destination: URL?
    /// Overrides the folder preference, e.g. "Extrair para Nome/" already names the folder.
    var folderPolicy: FolderPolicy?
    var selection: Set<String>?
    var prepared: (listing: ArchiveListing, engine: any ArchiveEngine)?

    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored private var speedSample: (date: Date, bytes: UInt64)?

    init(volumes: VolumeSet) {
        archive = volumes.first
        volumeCount = volumes.members.count
    }

    var name: String { archive.lastPathComponent }

    var isActive: Bool {
        switch state {
        case .preparing, .extracting: true
        default: false
        }
    }

    var isWaiting: Bool { if case .waiting = state { true } else { false } }

    var isDone: Bool {
        switch state {
        case .finished, .verified, .failed, .cancelled: true
        default: false
        }
    }

    func apply(_ update: ExtractProgress) {
        progress = max(progress, update.fraction)
        bytesTotal = update.bytesTotal
        bytesDone = update.bytesDone
        if let item = update.currentItem { currentItem = item }
        let now = Date()
        if let sample = speedSample {
            let elapsed = now.timeIntervalSince(sample.date)
            if elapsed >= 0.5 {
                let instant = Double(update.bytesDone &- sample.bytes) / elapsed
                speed = speed == 0 ? instant : speed * 0.6 + instant * 0.4
                speedSample = (now, update.bytesDone)
            }
        } else {
            speedSample = (now, update.bytesDone)
        }
    }

    func resetProgress() {
        progress = 0
        bytesDone = 0
        speed = 0
        currentItem = nil
        speedSample = nil
    }
}

struct PasswordRequest: Identifiable {
    let id = UUID()
    let archiveName: String
    let wrong: Bool
    let submit: (String) -> Void
    let cancel: () -> Void
}
