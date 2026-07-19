import Foundation
import CloudKit
import SwiftData

/// Reports whether iCloud sync for transcripts is actually working, for a
/// user-facing Settings row and for launch diagnostics.
@MainActor
@Observable
final class CloudSyncStatus {
    enum State: Equatable {
        case checking
        case syncing            // signed in and the store is CloudKit-backed
        case signedOut          // no iCloud account on the device
        case restricted         // iCloud restricted (parental controls / MDM)
        case localOnly(String)  // the store fell back to local (reason)
        case unavailable(String)

        var title: String {
            switch self {
            case .checking: "Checking iCloud…"
            case .syncing: "Syncing with iCloud"
            case .signedOut: "Not signed in to iCloud"
            case .restricted: "iCloud is restricted"
            case .localOnly: "Saved on this device only"
            case .unavailable: "iCloud sync unavailable"
            }
        }

        var systemImage: String {
            switch self {
            case .checking: "icloud"
            case .syncing: "checkmark.icloud.fill"
            case .signedOut, .restricted: "xmark.icloud"
            case .localOnly, .unavailable: "exclamationmark.icloud"
            }
        }

        var isHealthy: Bool { self == .syncing }
    }

    static let containerIdentifier = "iCloud.com.josumartinez.transcriber"

    /// Set once at launch: true if the SwiftData store opened with CloudKit
    /// mirroring, false if it fell back to a local-only store.
    nonisolated(unsafe) static var storeIsCloudKitBacked = true

    private(set) var state: State = .checking

    func refresh() async {
        guard Self.storeIsCloudKitBacked else {
            state = .localOnly("The store opened without CloudKit on this launch.")
            return
        }
        do {
            let status = try await CKContainer(identifier: Self.containerIdentifier).accountStatus()
            switch status {
            case .available: state = .syncing
            case .noAccount: state = .signedOut
            case .restricted: state = .restricted
            case .couldNotDetermine: state = .unavailable("Could not determine iCloud status.")
            case .temporarilyUnavailable: state = .unavailable("iCloud is temporarily unavailable.")
            @unknown default: state = .unavailable("Unknown iCloud status.")
            }
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }
}
