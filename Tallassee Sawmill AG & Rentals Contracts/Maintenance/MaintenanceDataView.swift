//
//  MaintenanceDataView.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  Backup, restore, and iCloud sync controls for the maintenance database.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MaintenanceDataView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(MaintenanceStore.cloudSyncKey) private var cloudSyncEnabled = false

    @Query private var equipment: [Equipment]
    @Query private var parts: [Part]
    @Query private var logs: [MaintenanceLog]

    @State private var backupURL: URL?
    @State private var showingRestoreConfirmation = false
    @State private var showingImporter = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("iCloud Sync", isOn: $cloudSyncEnabled)
            } header: {
                Text("Sync")
            } footer: {
                Text("Syncs maintenance data to your private iCloud database across devices. Takes effect the next time you launch the app, and requires the iCloud (CloudKit) capability to be enabled for the app. If iCloud isn't available, the app keeps using local storage.")
            }

            Section {
                Button {
                    createBackup()
                } label: {
                    Label("Create Backup", systemImage: "externaldrive.badge.plus")
                }
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Label("Share \(backupURL.lastPathComponent)", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("The backup is one file containing \(equipment.count) machines, \(parts.count) parts, \(logs.count) service records, and all photos and attachments. Save it to Files, iCloud Drive, or share it anywhere.")
            }

            Section {
                Button(role: .destructive) {
                    showingRestoreConfirmation = true
                } label: {
                    Label("Restore from Backup…", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("Restore")
            } footer: {
                Text("Restoring replaces all current maintenance data with the backup's contents.")
            }
        }
        .navigationTitle("Backup & Sync")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Replace all maintenance data?",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Choose Backup File", role: .destructive) {
                showingImporter = true
            }
        } message: {
            Text("Your current machines, parts, kits, history, and attachments will be replaced by the backup. Consider creating a backup first.")
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json]
        ) { result in
            restore(result)
        }
        .alert("Restore Complete", isPresented: .init(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("OK") { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
        .alert("Something Went Wrong", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func createBackup() {
        do {
            backupURL = try MaintenanceBackupManager.export(context: modelContext)
        } catch {
            errorMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    private func restore(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                resultMessage = try MaintenanceBackupManager.restore(from: url, context: modelContext)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
