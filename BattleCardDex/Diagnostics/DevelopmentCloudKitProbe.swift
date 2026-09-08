#if DEBUG
import CloudKit
import SwiftUI

@MainActor
enum DevelopmentCloudKitProbe {
    static let launchEnvironmentKey = "BATTLE_CARD_DEX_CLOUDKIT_PROBE"
    static let readMode = "read"
    static let mutationDenialMode = "mutation-denial"
    static let statusIdentifier = "cloudkit-development-probe-status"

    static func readManifest() async -> String {
        do {
            let configuration = try AppConfiguration.configuration(for: .debug)
            guard configuration.cloudCatalog.service == .developmentPublicDatabase else {
                return "READ_FAILED: development database was not selected"
            }

            let recordName = "catalog-manifest-v\(configuration.cloudCatalog.schemaVersion)"
            let database = CKContainer(identifier: configuration.cloudCatalog.containerIdentifier).publicCloudDatabase
            let record = try await database.record(for: CKRecord.ID(recordName: recordName))
            let decoded = try CatalogManifestRecordCodec.decode(CloudCatalogRecordSnapshot(record: record))

            guard record.recordType == configuration.cloudCatalog.manifestRecordType,
                  record.recordID.recordName == recordName,
                  decoded.value.schemaVersion == configuration.cloudCatalog.schemaVersion else {
                return "READ_FAILED: unexpected manifest record"
            }

            return "READ_OK: \(record.recordType)/\(record.recordID.recordName) revision=\(decoded.value.revision)"
        } catch let error as CKError {
            return "READ_FAILED: CKError \(error.code.rawValue) \(error.localizedDescription)"
        } catch {
            return "READ_FAILED: \(String(describing: error))"
        }
    }

    static func verifyMutationDenials() async -> String {
        do {
            let configuration = try AppConfiguration.configuration(for: .debug)
            guard configuration.cloudCatalog.service == .developmentPublicDatabase else {
                return "WRITE_DENIAL_FAILED: development database was not selected"
            }

            let database = CKContainer(identifier: configuration.cloudCatalog.containerIdentifier).publicCloudDatabase
            let createID = CKRecord.ID(recordName: "security-probe-create-v1")
            let existingID = CKRecord.ID(recordName: "security-probe-existing-v1")

            let create = await denialResult {
                let record = CKRecord(recordType: configuration.cloudCatalog.manifestRecordType, recordID: createID)
                record["contentHash"] = "unexpected-client-create" as CKRecordValue
                _ = try await database.save(record)
            }
            let change = await denialResult {
                let record = try await database.record(for: existingID)
                record["contentHash"] = "unexpected-client-change" as CKRecordValue
                _ = try await database.save(record)
            }
            let delete = await denialResult {
                _ = try await database.deleteRecord(withID: existingID)
            }

            let summary = "create=\(create) change=\(change) delete=\(delete)"
            return [create, change, delete].allSatisfy { $0.hasPrefix("denied(") }
                ? "WRITE_DENIAL_OK: \(summary)"
                : "WRITE_DENIAL_FAILED: \(summary)"
        } catch {
            return "WRITE_DENIAL_FAILED: setup \(String(describing: error))"
        }
    }

    private static func denialResult(_ operation: () async throws -> Void) async -> String {
        do {
            try await operation()
            return "unexpectedlyAllowed"
        } catch let error as CKError {
            let denialCodes: Set<CKError.Code> = [
                .permissionFailure,
                .notAuthenticated,
                .accountTemporarilyUnavailable,
            ]
            return denialCodes.contains(error.code)
                ? "denied(\(error.code.rawValue))"
                : "CKError\(error.code.rawValue)"
        } catch {
            return "unexpectedError"
        }
    }
}

struct DevelopmentCloudKitProbeView: View {
    let mode: String
    @State private var status = "READ_PENDING"

    var body: some View {
        Text(status)
            .font(.body.monospaced())
            .multilineTextAlignment(.center)
            .padding()
            .accessibilityIdentifier(DevelopmentCloudKitProbe.statusIdentifier)
            .task {
                status = if mode == DevelopmentCloudKitProbe.mutationDenialMode {
                    await DevelopmentCloudKitProbe.verifyMutationDenials()
                } else {
                    await DevelopmentCloudKitProbe.readManifest()
                }
                print("BattleCardDex CloudKit probe: \(status)")
            }
    }
}
#endif
