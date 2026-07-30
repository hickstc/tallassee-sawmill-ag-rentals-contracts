import SwiftUI
import UIKit

// MARK: - All Jobs Photo Browser

/// Browses ALL photos and videos across all job types, organized by job
struct AllJobsMediaBrowser: View {
    @State private var allMedia: [JobMediaCollection] = []
    @State private var selectedItem: MediaItemWithContext?
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var isSelecting = false
    @State private var shareItem: ShareableMedia?
    
    private var allItems: [MediaItemWithContext] {
        allMedia.flatMap(\.items)
    }
    
    private var selectedItems: [MediaItemWithContext] {
        allItems.filter { selectedItemIDs.contains($0.id) }
    }
    
    var body: some View {
        Group {
            if allMedia.isEmpty {
                ContentUnavailableView {
                    Label("No Job Photos Yet", systemImage: "photo.on.rectangle")
                } description: {
                    Text("Photos and videos you add to jobs will appear here.")
                }
            } else {
                List {
                    ForEach(allMedia) { collection in
                        Section {
                            ForEach(collection.items) { item in
                                MediaBrowserRow(
                                    item: item,
                                    isSelecting: isSelecting,
                                    isSelected: selectedItemIDs.contains(item.id),
                                    onTap: {
                                        if isSelecting {
                                            toggleSelection(for: item)
                                        } else {
                                            selectedItem = item
                                        }
                                    },
                                    onShare: { shareItem = ShareableMedia(item: item) }
                                )
                            }
                        } header: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(collection.jobName)
                                    .font(.headline)
                                Text("\(collection.jobType.displayName) · \(collection.items.count) item\(collection.items.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .textCase(.none)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("All Job Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        endSelection()
                    }
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                if !allMedia.isEmpty {
                    if isSelecting {
                        Button {
                            shareSelectedMedia()
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .disabled(selectedItemIDs.isEmpty)
                    } else {
                        Menu {
                            Button {
                                beginSelection()
                            } label: {
                                Label("Select Photos", systemImage: "checkmark.circle")
                            }
                            Button {
                                shareAllPhotos()
                            } label: {
                                Label("Share All Photos", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                let count = allItems.count
                                UIPasteboard.general.string = "Total: \(count) photos and videos across all jobs"
                            } label: {
                                Label("Copy Count", systemImage: "doc.on.doc")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedItem) { item in
            MediaDetailViewWithShare(item: item)
        }
        .sheet(item: $shareItem) { shareableMedia in
            ActivityViewController(items: shareableMedia.activityItems)
        }
        .onAppear {
            loadAllMedia()
        }
        .refreshable {
            loadAllMedia()
        }
    }
    
    private func beginSelection() {
        isSelecting = true
        selectedItemIDs.removeAll()
    }
    
    private func endSelection() {
        isSelecting = false
        selectedItemIDs.removeAll()
    }
    
    private func toggleSelection(for item: MediaItemWithContext) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }
    
    private func loadAllMedia() {
        var collections: [JobMediaCollection] = []
        
        // Load Ag Services
        for record in AgServicesStorage.loadAll() {
            let items = record.data.mediaItems.map { mediaItem in
                MediaItemWithContext(
                    mediaItem: mediaItem,
                    jobID: record.id,
                    jobType: .agServices,
                    jobName: record.customerName.isEmpty ? "Ag Services Job" : record.customerName,
                    jobDate: record.data.startDate
                )
            }
            if !items.isEmpty {
                collections.append(JobMediaCollection(
                    jobID: record.id,
                    jobName: record.customerName.isEmpty ? "Ag Services Job" : record.customerName,
                    jobType: .agServices,
                    items: items
                ))
            }
        }
        
        // Load Milling Jobs
        for job in MillingJobStorage.loadAll() {
            let items = job.mediaItems.map { mediaItem in
                MediaItemWithContext(
                    mediaItem: mediaItem,
                    jobID: job.id,
                    jobType: .milling,
                    jobName: job.customerName.isEmpty ? job.jobID : job.customerName,
                    jobDate: job.date
                )
            }
            if !items.isEmpty {
                collections.append(JobMediaCollection(
                    jobID: job.id,
                    jobName: job.customerName.isEmpty ? job.jobID : job.customerName,
                    jobType: .milling,
                    items: items
                ))
            }
        }
        
        // Sort by most recent first
        allMedia = collections.sorted { $0.mostRecentDate > $1.mostRecentDate }
    }
    
    private func shareAllPhotos() {
        shareItem = ShareableMedia(items: allItems, caption: "Job Photos from Tallassee Sawmill")
    }
    
    private func shareSelectedMedia() {
        shareItem = ShareableMedia(items: selectedItems, caption: "Selected Job Photos from Tallassee Sawmill")
        endSelection()
    }
}

// MARK: - Supporting Types

struct JobMediaCollection: Identifiable {
    let jobID: UUID
    let jobName: String
    let jobType: JobMediaType
    let items: [MediaItemWithContext]
    
    var id: UUID { jobID }
    
    var mostRecentDate: Date {
        items.map(\.mediaItem.timestamp).max() ?? Date.distantPast
    }
}

struct MediaItemWithContext: Identifiable {
    let mediaItem: JobMediaItem
    let jobID: UUID
    let jobType: JobMediaType
    let jobName: String
    let jobDate: Date
    
    var id: UUID { mediaItem.id }
}

struct ShareableMedia: Identifiable {
    let id = UUID()
    var activityItems: [Any]
    
    init(item: MediaItemWithContext) {
        let caption = "\(item.jobName) - \(item.mediaItem.label.rawValue) - \(item.mediaItem.timestamp.formatted(date: .abbreviated, time: .omitted))"
        self.activityItems = Self.activityItems(for: [item], caption: caption)
    }
    
    init(items: [MediaItemWithContext], caption: String) {
        self.activityItems = Self.activityItems(for: items, caption: caption)
    }
    
    private static func activityItems(for items: [MediaItemWithContext], caption: String) -> [Any] {
        let media = items.compactMap { item -> Any? in
            mediaPayload(for: item)
        }
        return media.isEmpty ? [] : media + [caption]
    }
    
    private static func mediaPayload(for item: MediaItemWithContext) -> Any? {
        let url = item.mediaItem.fileURL(jobID: item.jobID, jobType: item.jobType)
        if item.mediaItem.type == .photo {
            if let data = try? Data(contentsOf: url) {
                return UIImage(data: data)
            }
            return nil
        } else {
            return url
        }
    }
}

// MARK: - Media Browser Row

private struct MediaBrowserRow: View {
    let item: MediaItemWithContext
    let isSelecting: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onShare: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Thumbnail
                if item.mediaItem.type == .photo {
                    if let image = loadImage() {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        placeholderThumbnail
                    }
                } else {
                    videoThumbnail
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.mediaItem.label.rawValue)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if item.mediaItem.type == .video {
                            Image(systemName: "video.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text(item.mediaItem.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(item.jobDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
                
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                } else {
                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private func loadImage() -> UIImage? {
        let url = item.mediaItem.fileURL(jobID: item.jobID, jobType: item.jobType)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    
    private var placeholderThumbnail: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 80, height: 80)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }
    
    private var videoThumbnail: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 80, height: 80)
            .overlay {
                Image(systemName: "video.fill")
                    .foregroundStyle(.secondary)
            }
    }
}

// MARK: - Media Detail with Share

private struct MediaDetailViewWithShare: View {
    let item: MediaItemWithContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingShare = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if item.mediaItem.type == .photo {
                    if let image = loadImage() {
                        ZoomableMediaImage(image: image)
                    }
                } else {
                    VideoPlayerView(url: item.mediaItem.fileURL(jobID: item.jobID, jobType: item.jobType))
                }
            }
            .navigationTitle(item.mediaItem.label.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showingShare) {
                if let image = loadImage() {
                    ActivityViewController(items: [
                        image,
                        "\(item.jobName) - \(item.mediaItem.label.rawValue) - \(item.mediaItem.timestamp.formatted(date: .abbreviated, time: .omitted))"
                    ])
                } else if item.mediaItem.type == .video {
                    ActivityViewController(items: [
                        item.mediaItem.fileURL(jobID: item.jobID, jobType: item.jobType),
                        "\(item.jobName) - \(item.mediaItem.label.rawValue) - \(item.mediaItem.timestamp.formatted(date: .abbreviated, time: .omitted))"
                    ])
                }
            }
        }
    }
    
    private func loadImage() -> UIImage? {
        let url = item.mediaItem.fileURL(jobID: item.jobID, jobType: item.jobType)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Activity View Controller (for sharing)

struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
