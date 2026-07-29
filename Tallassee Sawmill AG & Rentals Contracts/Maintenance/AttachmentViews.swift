//
//  AttachmentViews.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  Reusable attachment UI: a list section that lets the user attach photos,
//  receipt photos, and PDFs to either a machine or a service log, plus a viewer.
//

import SwiftUI
import SwiftData
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - Attachment Section

/// A `Section` for a `List`/`Form` showing attachments of one parent object.
/// Pass exactly one of `equipment` or `log`.
struct AttachmentSection: View {
    var equipment: Equipment? = nil
    var log: MaintenanceLog? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var photoKind: AttachmentKind = .photo
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var showingPDFImporter = false

    private var attachments: [MaintenanceAttachment] {
        let list = equipment?.attachments ?? log?.attachments ?? []
        return list.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Section("Attachments") {
            ForEach(attachments, id: \.uuid) { attachment in
                NavigationLink {
                    AttachmentViewer(attachment: attachment)
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(attachment.fileName.isEmpty ? attachment.kind.rawValue : attachment.fileName)
                            Text(attachment.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: attachment.kind.systemImage)
                            .foregroundStyle(.tint)
                    }
                }
            }
            .onDelete(perform: deleteAttachments)

            Menu {
                Button {
                    photoKind = .photo
                    showingPhotoPicker = true
                } label: {
                    Label("Add Photo", systemImage: "photo")
                }
                Button {
                    photoKind = .receipt
                    showingPhotoPicker = true
                } label: {
                    Label("Add Receipt Photo", systemImage: "receipt")
                }
                Button {
                    showingPDFImporter = true
                } label: {
                    Label("Add PDF", systemImage: "doc")
                }
            } label: {
                Label("Add Attachment", systemImage: "paperclip")
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            Task { await importPhoto(newItem) }
        }
        .fileImporter(
            isPresented: $showingPDFImporter,
            allowedContentTypes: [.pdf]
        ) { result in
            importPDF(result)
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let name = "\(photoKind.rawValue) \(Date.now.formatted(date: .abbreviated, time: .shortened))"
        insert(MaintenanceAttachment(kind: photoKind, fileName: name, data: data))
        selectedPhoto = nil
    }

    private func importPDF(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        // Security-scoped access is required for files picked outside the sandbox.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        insert(MaintenanceAttachment(kind: .pdf, fileName: url.lastPathComponent, data: data))
    }

    private func insert(_ attachment: MaintenanceAttachment) {
        attachment.equipment = equipment
        attachment.log = log
        modelContext.insert(attachment)
    }

    private func deleteAttachments(at offsets: IndexSet) {
        let items = attachments
        for index in offsets {
            modelContext.delete(items[index])
        }
    }
}

// MARK: - Attachment Viewer

/// Full-screen viewer for a single attachment: zoomable PDF or image.
struct AttachmentViewer: View {
    let attachment: MaintenanceAttachment

    var body: some View {
        Group {
            if attachment.kind == .pdf {
                PDFDocumentView(data: attachment.data)
            } else if let uiImage = UIImage(data: attachment.data) {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .containerRelativeFrame([.horizontal, .vertical])
                }
            } else {
                ContentUnavailableView(
                    "Can't Display Attachment",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The attachment data could not be read.")
                )
            }
        }
        .navigationTitle(attachment.fileName.isEmpty ? attachment.kind.rawValue : attachment.fileName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// PDFKit wrapper for displaying stored PDF data.
private struct PDFDocumentView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // Data is immutable for a stored attachment; nothing to update.
    }
}
