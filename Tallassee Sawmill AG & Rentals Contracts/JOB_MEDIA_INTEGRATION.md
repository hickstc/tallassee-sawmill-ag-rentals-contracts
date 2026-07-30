# Job Media Feature - Integration Guide

## ✅ Core Feature Complete

The `JobMediaFeature.swift` file contains all the infrastructure needed for job photos and videos with Before/After labels.

### What's Been Built

1. **`JobMediaItem`** - Model for individual photos/videos
2. **`JobMediaStorage`** - Local file storage with protection
3. **`JobMediaPicker`** - Camera/photo/video picker interface
4. **`JobMediaGalleryView`** - Display media organized by Before/After
5. **Video Playback** - Full-screen AVPlayer support
6. **File Protection** - Encrypted storage when device locked

## 🔧 Integration Steps

### Step 1: Add Media Field to Each Job Type

#### For Ag Services (`AgServicesData`)
```swift
struct AgServicesData: Codable, Equatable {
    // ... existing fields ...
    
    // Add this new field:
    var mediaItems: [JobMediaItem] = []
}
```

#### For Milling Jobs (`MillingJob`)
```swift
struct MillingJob: Identifiable, Codable, Hashable {
    // ... existing fields ...
    
    // Add this new field:
    var mediaItems: [JobMediaItem] = []
    
    // Update CodingKeys if needed
    enum CodingKeys: String, CodingKey {
        case id, jobNumber, customerName, date, notes, completed
        case sawmillMobilization, skidSteerMobilization, lines
        case mediaItems  // Add this
    }
    
    // Update custom decoder
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // ... existing decoding ...
        mediaItems = try container.decodeIfPresent([JobMediaItem].self, forKey: .mediaItems) ?? []
    }
}
```

#### For Lumber Orders (`LumberOrder`)
```swift
struct LumberOrder: Identifiable, Codable, Hashable {
    // ... existing fields ...
    
    // Add this new field:
    var mediaItems: [JobMediaItem] = []
}
```

### Step 2: Load Media on Job Load

When loading a job, also load its media:

```swift
// In the view's onAppear or when loading job
let loadedMedia = JobMediaStorage.loadMedia(jobID: job.id, jobType: .agServices)
job.mediaItems = loadedMedia
```

### Step 3: Save Media When Job Changes

When saving the job, also save media:

```swift
// After saving job data
JobMediaStorage.saveMedia(job.mediaItems, jobID: job.id, jobType: .agServices)
```

### Step 4: Add Media Section to Job Detail View

Add a navigation link to the media gallery in each job's form:

```swift
Section("Job Media") {
    NavigationLink {
        JobMediaGalleryView(
            jobID: job.id,
            jobType: .agServices,
            mediaItems: $job.mediaItems
        )
    } label: {
        HStack {
            Label("Photos & Videos", systemImage: "photo.on.rectangle")
            Spacer()
            if !job.mediaItems.isEmpty {
                Text("\(job.mediaItems.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

## 📐 Example: Ag Services Integration

Here's a complete example for Ag Services:

### 1. Update AgServicesData Model

```swift
// In AgriculturalServicesView.swift or separate file
struct AgServicesData: Codable, Equatable {
    var customerName = ""
    var mailingAddress = ""
    var startDate = Date()
    var services: [AgServiceLineItem] = []
    var notes = ""
    var signatureData: Data?
    var paymentMethodRaw: String?
    
    // ✅ ADD THIS:
    var mediaItems: [JobMediaItem] = []
    
    // ... rest of existing code ...
}
```

### 2. Update AgServicesRecord Save/Load

```swift
// When saving a record:
static func save(_ record: AgServicesRecord) {
    // ... existing save logic ...
    
    // ✅ ADD THIS after saving JSON:
    JobMediaStorage.saveMedia(
        record.data.mediaItems,
        jobID: record.id,
        jobType: .agServices
    )
}

// When loading records:
static func loadAll() -> [AgServicesRecord] {
    // ... existing load logic ...
    
    // ✅ ADD THIS for each loaded record:
    var records: [AgServicesRecord] = []
    for url in urls where url.pathExtension.lowercased() == "json" {
        if let data = try? Data(contentsOf: url),
           var rec = try? JSONDecoder().decode(AgServicesRecord.self, from: data) {
            // Load media for this record
            rec.data.mediaItems = JobMediaStorage.loadMedia(
                jobID: rec.id,
                jobType: .agServices
            )
            records.append(rec)
        }
    }
    return records
}
```

### 3. Add Media Section to Ag Services Form

In `AgriculturalServicesView`, add this section:

```swift
var body: some View {
    Form {
        // ... existing sections ...
        
        // ✅ ADD THIS SECTION:
        Section {
            NavigationLink {
                JobMediaGalleryView(
                    jobID: currentRecord?.id ?? UUID(),
                    jobType: .agServices,
                    mediaItems: Binding(
                        get: { data.mediaItems },
                        set: { data.mediaItems = $0 }
                    )
                )
            } label: {
                HStack {
                    Label("Job Photos & Videos", systemImage: "photo.on.rectangle")
                    Spacer()
                    if !data.mediaItems.isEmpty {
                        Text("\(data.mediaItems.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } footer: {
            Text("Document this job with before and after photos or videos.")
        }
    }
}
```

## 📊 Same Pattern for Milling and Lumber Orders

Follow the same three steps for:

1. **Milling Jobs** - Use `JobMediaType.milling`
2. **Lumber Orders** - Use `JobMediaType.lumberOrder`

The code structure is identical, just change:
- The job type enum value (`.milling`, `.lumberOrder`)
- The record type being edited
- The storage enum being called

## 🎯 Customer History Integration

To show media in customer history, update `CustomerHistoryItem`:

```swift
struct CustomerHistoryItem: Identifiable {
    let id: String
    let date: Date
    let title: String
    let detail: String
    let amount: Double
    let icon: String
    
    // ✅ ADD THIS:
    let jobID: UUID
    let jobType: JobMediaType
    let mediaCount: Int
}
```

Then in the history section, add a thumbnail preview:

```swift
ForEach(history) { item in
    NavigationLink {
        // Navigate to job media gallery
        let mediaItems = JobMediaStorage.loadMedia(
            jobID: item.jobID,
            jobType: item.jobType
        )
        JobMediaGalleryView(
            jobID: item.jobID,
            jobType: item.jobType,
            mediaItems: .constant(mediaItems)
        )
    } label: {
        HStack {
            // ... existing content ...
            if item.mediaCount > 0 {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(item.mediaCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

## 🧪 Testing Checklist

After integration, test:

- [ ] Take photo with camera → saves correctly
- [ ] Choose photo from library → saves correctly
- [ ] Choose video from library → saves correctly
- [ ] Label photos as Before/After → organizes correctly
- [ ] View full-screen photo → displays properly
- [ ] Play video → plays with controls
- [ ] Swipe to delete media → removes from storage
- [ ] Close and reopen app → media persists
- [ ] Media appears in customer history
- [ ] Media counts show correctly

## 🔐 Security & Privacy

The media feature includes:
- ✅ File protection (encrypted when device locked)
- ✅ Local storage only (no cloud upload)
- ✅ Automatic cleanup when job deleted
- ✅ Duplicate prevention (UUID filenames)
- ✅ Metadata separate from files

## 📦 File Storage Structure

```
Documents/
└── job_media/
    ├── agServices_{job-uuid}/
    │   ├── metadata.json
    │   ├── {media-uuid}.jpg
    │   ├── {media-uuid}.jpg
    │   └── {media-uuid}.mov
    ├── milling_{job-uuid}/
    │   ├── metadata.json
    │   └── {media-uuid}.jpg
    └── lumberOrder_{job-uuid}/
        ├── metadata.json
        └── {media-uuid}.mov
```

## 🚀 Next: Wi-Fi Sync Feature

After integrating and testing the local media feature, the Wi-Fi sync portion will:

1. Use **Multipeer Connectivity** for local device-to-device transfer
2. Show nearby devices on same Wi-Fi
3. Allow manual selection of jobs to sync
4. Transfer media files securely
5. Prevent duplicates
6. Show progress and completion
7. **Never** use public internet

This is a separate, substantial feature that should be implemented after the core media feature is working and tested.

---

**Status**: Core feature ready for integration  
**Build Status**: ✅ Compiles successfully  
**Required**: Update 3 job models (Ag Services, Milling, Lumber Orders)  
**Estimated Time**: 30-60 minutes per job type
