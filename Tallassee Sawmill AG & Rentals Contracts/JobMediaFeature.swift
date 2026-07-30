import SwiftUI
import AVKit
import AVFoundation
import PhotosUI

// MARK: - Job Media Models

/// One photo or video for a job, labeled Before or After
struct JobMediaItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var timestamp = Date()
    var label: MediaLabel = .before
    var type: MediaType = .photo
    /// Filename on disk (stored in job media directory)
    var filename: String = ""
    
    enum MediaLabel: String, Codable, CaseIterable {
        case before = "Before"
        case after = "After"
    }
    
    enum MediaType: String, Codable {
        case photo
        case video
    }
    
    /// Full URL to the media file
    func fileURL(jobID: UUID, jobType: JobType) -> URL {
        JobMediaStorage.mediaURL(jobID: jobID, jobType: jobType, filename: filename)
    }
    
    /// Full URL to the media file from the all-media browser's narrower job type.
    func fileURL(jobID: UUID, jobType: JobMediaType) -> URL {
        fileURL(jobID: jobID, jobType: jobType.jobType)
    }
}

/// Which job type this media belongs to
enum JobMediaType: String, Codable {
    case rental
    case agServices
    case milling
    case lumberOrder
    
    var displayName: String {
        switch self {
        case .rental: return "Rental"
        case .agServices: return "Ag Services"
        case .milling: return "Milling"
        case .lumberOrder: return "Lumber Order"
        }
    }
    
    var jobType: JobType {
        switch self {
        case .rental: return .rental
        case .agServices: return .agServices
        case .milling: return .milling
        case .lumberOrder: return .lumberOrder
        }
    }
}

// MARK: - Storage

/// Manages local file storage for job media (photos and videos)
enum JobMediaStorage {
    /// Base directory for all job media
    private static var baseDir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("job_media", isDirectory: true)
    }
    
    /// Directory for a specific job
    private static func jobDir(jobID: UUID, jobType: JobType) -> URL {
        baseDir.appendingPathComponent("\(jobType.rawValue)_\(jobID.uuidString)", isDirectory: true)
    }
    
    /// Full URL for a specific media file
    static func mediaURL(jobID: UUID, jobType: JobType, filename: String) -> URL {
        jobDir(jobID: jobID, jobType: jobType).appendingPathComponent(filename)
    }
    
    /// Load media items for a job
    static func loadMedia(jobID: UUID, jobType: JobType) -> [JobMediaItem] {
        let dir = jobDir(jobID: jobID, jobType: jobType)
        let metadataURL = dir.appendingPathComponent("metadata.json")
        
        guard let data = try? Data(contentsOf: metadataURL),
              let items = try? JSONDecoder().decode([JobMediaItem].self, from: data) else {
            return []
        }
        
        // Filter out items whose files no longer exist
        return items.filter { item in
            FileManager.default.fileExists(atPath: item.fileURL(jobID: jobID, jobType: jobType).path)
        }
    }
    
    /// Save media items list for a job
    static func saveMedia(_ items: [JobMediaItem], jobID: UUID, jobType: JobType) {
        let dir = jobDir(jobID: jobID, jobType: jobType)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let metadataURL = dir.appendingPathComponent("metadata.json")
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: metadataURL, options: [.atomic])
        applyFileProtection(metadataURL)
    }
    
    /// Save a new photo to disk
    static func savePhoto(_ imageData: Data, jobID: UUID, jobType: JobType, label: JobMediaItem.MediaLabel) -> JobMediaItem? {
        let dir = jobDir(jobID: jobID, jobType: jobType)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = dir.appendingPathComponent(filename)
        
        do {
            try imageData.write(to: fileURL, options: [.atomic])
            applyFileProtection(fileURL)
            
            return JobMediaItem(
                timestamp: Date(),
                label: label,
                type: .photo,
                filename: filename
            )
        } catch {
            return nil
        }
    }
    
    /// Save a new video to disk
    static func saveVideo(from sourceURL: URL, jobID: UUID, jobType: JobType, label: JobMediaItem.MediaLabel) -> JobMediaItem? {
        let dir = jobDir(jobID: jobID, jobType: jobType)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let filename = "\(UUID().uuidString).mov"
        let fileURL = dir.appendingPathComponent(filename)
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: fileURL)
            applyFileProtection(fileURL)
            
            return JobMediaItem(
                timestamp: Date(),
                label: label,
                type: .video,
                filename: filename
            )
        } catch {
            return nil
        }
    }
    
    /// Delete a media item and its file
    static func deleteMedia(_ item: JobMediaItem, jobID: UUID, jobType: JobType) {
        let fileURL = item.fileURL(jobID: jobID, jobType: jobType)
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    /// Delete all media for a job
    static func deleteAllMedia(jobID: UUID, jobType: JobType) {
        let dir = jobDir(jobID: jobID, jobType: jobType)
        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: - Media Picker

/// SwiftUI view for capturing or selecting photos/videos
struct JobMediaPicker: View {
    let jobID: UUID
    let jobType: JobType
    @Binding var mediaItems: [JobMediaItem]
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedLabel: JobMediaItem.MediaLabel = .before
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var showingVideoPicker = false
    @State private var capturedImageData: Data?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Media Label") {
                    Picker("Label", selection: $selectedLabel) {
                        ForEach(JobMediaItem.MediaLabel.allCases, id: \.self) { label in
                            Text(label.rawValue).tag(label)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Add Media") {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                    
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                    }
                    
                    Button {
                        showingVideoPicker = true
                    } label: {
                        Label("Choose Video", systemImage: "video")
                    }
                }
            }
            .navigationTitle("Add Job Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCamera) {
                ImageCapturePicker(imageData: $capturedImageData)
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoPickerView(jobID: jobID, jobType: jobType, label: selectedLabel, mediaItems: $mediaItems)
            }
            .sheet(isPresented: $showingVideoPicker) {
                VideoPickerView(jobID: jobID, jobType: jobType, label: selectedLabel, mediaItems: $mediaItems)
            }
            .onChange(of: capturedImageData) { _, newData in
                if let data = newData {
                    saveNewPhoto(data)
                    capturedImageData = nil
                }
            }
        }
    }
    
    private func saveNewPhoto(_ imageData: Data) {
        if let newItem = JobMediaStorage.savePhoto(imageData, jobID: jobID, jobType: jobType, label: selectedLabel) {
            mediaItems.append(newItem)
            JobMediaStorage.saveMedia(mediaItems, jobID: jobID, jobType: jobType)
        }
    }
}

// MARK: - Photo Picker

private struct PhotoPickerView: UIViewControllerRepresentable {
    let jobID: UUID
    let jobType: JobType
    let label: JobMediaItem.MediaLabel
    @Binding var mediaItems: [JobMediaItem]
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 0
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView
        
        init(_ parent: PhotoPickerView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            let providers = results.map(\.itemProvider).filter {
                $0.canLoadObject(ofClass: UIImage.self)
            }
            guard !providers.isEmpty else { return }
            
            for provider in providers {
                provider.loadObject(ofClass: UIImage.self) { image, error in
                    guard let uiImage = image as? UIImage,
                          let data = uiImage.jpegData(compressionQuality: 0.8) else { return }
                    
                    DispatchQueue.main.async {
                        if let newItem = JobMediaStorage.savePhoto(data, jobID: self.parent.jobID, jobType: self.parent.jobType, label: self.parent.label) {
                            self.parent.mediaItems.append(newItem)
                            JobMediaStorage.saveMedia(self.parent.mediaItems, jobID: self.parent.jobID, jobType: self.parent.jobType)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Video Picker

private struct VideoPickerView: UIViewControllerRepresentable {
    let jobID: UUID
    let jobType: JobType
    let label: JobMediaItem.MediaLabel
    @Binding var mediaItems: [JobMediaItem]
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPickerView
        
        init(_ parent: VideoPickerView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else { return }
            
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                guard let url = url else { return }
                
                DispatchQueue.main.async {
                    if let newItem = JobMediaStorage.saveVideo(from: url, jobID: self.parent.jobID, jobType: self.parent.jobType, label: self.parent.label) {
                        self.parent.mediaItems.append(newItem)
                        JobMediaStorage.saveMedia(self.parent.mediaItems, jobID: self.parent.jobID, jobType: self.parent.jobType)
                    }
                }
            }
        }
    }
}

// MARK: - Media Gallery View

/// Displays all media for a job with Before/After organization
struct JobMediaGalleryView: View {
    let jobID: UUID
    let jobType: JobType
    @Binding var mediaItems: [JobMediaItem]
    
    @State private var showingPicker = false
    @State private var selectedItem: JobMediaItem?
    
    private var beforeItems: [JobMediaItem] {
        mediaItems.filter { $0.label == .before }.sorted { $0.timestamp > $1.timestamp }
    }
    
    private var afterItems: [JobMediaItem] {
        mediaItems.filter { $0.label == .after }.sorted { $0.timestamp > $1.timestamp }
    }
    
    var body: some View {
        List {
            Section {
                Button {
                    showingPicker = true
                } label: {
                    Label("Add Photos or Videos", systemImage: "plus.circle.fill")
                }
            }
            
            if !beforeItems.isEmpty {
                Section("Before") {
                    ForEach(beforeItems) { item in
                        MediaRow(item: item, jobID: jobID, jobType: jobType)
                            .onTapGesture {
                                selectedItem = item
                            }
                    }
                    .onDelete { indexSet in
                        deleteItems(beforeItems, at: indexSet)
                    }
                }
            }
            
            if !afterItems.isEmpty {
                Section("After") {
                    ForEach(afterItems) { item in
                        MediaRow(item: item, jobID: jobID, jobType: jobType)
                            .onTapGesture {
                                selectedItem = item
                            }
                    }
                    .onDelete { indexSet in
                        deleteItems(afterItems, at: indexSet)
                    }
                }
            }
            
            if mediaItems.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Media Yet", systemImage: "photo.on.rectangle")
                    } description: {
                        Text("Add photos or videos to document this job.")
                    }
                }
            }
        }
        .navigationTitle("Job Media")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPicker) {
            JobMediaPicker(jobID: jobID, jobType: jobType, mediaItems: $mediaItems)
        }
        .sheet(item: $selectedItem) { item in
            MediaDetailView(item: item, jobID: jobID, jobType: jobType)
        }
    }
    
    private func deleteItems(_ items: [JobMediaItem], at indexSet: IndexSet) {
        for index in indexSet {
            let item = items[index]
            JobMediaStorage.deleteMedia(item, jobID: jobID, jobType: jobType)
            mediaItems.removeAll { $0.id == item.id }
        }
        JobMediaStorage.saveMedia(mediaItems, jobID: jobID, jobType: jobType)
    }
}

// MARK: - Media Row

private struct MediaRow: View {
    let item: JobMediaItem
    let jobID: UUID
    let jobType: JobType
    
    var body: some View {
        HStack(spacing: 12) {
            if item.type == .photo {
                if let image = loadImage() {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    placeholderThumbnail
                }
            } else {
                videoThumbnail
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.label.rawValue)
                        .font(.headline)
                    if item.type == .video {
                        Image(systemName: "video.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
    
    private func loadImage() -> UIImage? {
        let url = item.fileURL(jobID: jobID, jobType: jobType)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    
    private var placeholderThumbnail: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 60, height: 60)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }
    
    private var videoThumbnail: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 60, height: 60)
            .overlay {
                Image(systemName: "video.fill")
                    .foregroundStyle(.secondary)
            }
    }
}

// MARK: - Media Detail View

private struct MediaDetailView: View {
    let item: JobMediaItem
    let jobID: UUID
    let jobType: JobType
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if item.type == .photo {
                    if let image = loadImage() {
                        ZoomableMediaImage(image: image)
                    }
                } else {
                    VideoPlayerView(url: item.fileURL(jobID: jobID, jobType: jobType))
                }
            }
            .navigationTitle(item.label.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    
    private func loadImage() -> UIImage? {
        let url = item.fileURL(jobID: jobID, jobType: jobType)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Zoomable Image

struct ZoomableMediaImage: View {
    let image: UIImage
    
    @State private var scale = 1.0
    @State private var lastScale = 1.0
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    
    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(lastScale * value, 1), 5)
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale == 1 {
                                resetZoom()
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    if scale > 1 {
                        resetZoom()
                    } else {
                        scale = 2
                        lastScale = 2
                    }
                }
        }
    }
    
    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}

// MARK: - Video Player

struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: url)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
