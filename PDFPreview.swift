import SwiftUI
import PDFKit

/// Displays a PDF file using PDFKit.
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}

/// A full-screen, scrollable preview of a generated contract, with a share action.
struct PDFPreviewSheet: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
        }
    }
}

/// Full-screen review of a contract with the option to sign on the same page.
/// `render` rebuilds the PDF for a given signature so the preview updates live.
struct ContractReviewView: View {
    let title: String
    @Binding var signature: Data?
    let render: (Data?) -> URL?

    @Environment(\.dismiss) private var dismiss
    @State private var url: URL?
    @State private var showingSign = false

    private var isSigned: Bool { !(signature?.isEmpty ?? true) }

    var body: some View {
        NavigationStack {
            Group {
                if let url {
                    PDFKitView(url: url)
                } else {
                    ProgressView()
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSign = true
                    } label: {
                        Label(isSigned ? "Re-sign" : "Sign", systemImage: "signature")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if let url {
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSign) {
                ContractSignSheet(signature: $signature)
            }
            .onAppear {
                if url == nil { regenerate(signature) }
            }
            .onChange(of: signature) { _, newValue in
                regenerate(newValue)
            }
        }
    }

    /// Rebuilds the PDF and copies it to a unique URL so the viewer reloads it.
    private func regenerate(_ signature: Data?) {
        guard let produced = render(signature) else { return }
        let unique = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-\(UUID().uuidString).pdf")
        try? FileManager.default.copyItem(at: produced, to: unique)
        url = FileManager.default.fileExists(atPath: unique.path) ? unique : produced
    }
}

/// A modal signing sheet that commits a captured signature on Save.
struct ContractSignSheet: View {
    @Binding var signature: Data?
    @Environment(\.dismiss) private var dismiss
    @State private var working: Data?

    var body: some View {
        NavigationStack {
            Form {
                Section("Sign below") {
                    SignaturePad(imageData: $working)
                }
            }
            .navigationTitle("Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        signature = working
                        dismiss()
                    }
                }
            }
            .onAppear { working = signature }
        }
    }
}
