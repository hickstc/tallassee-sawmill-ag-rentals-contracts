# Job Media Integration - Step-by-Step Guide

## 🎯 Overview

You'll integrate the Job Media feature into three job types:
1. Ag Services
2. Milling Jobs
3. Lumber Orders

Each integration follows the same pattern and takes about 15-30 minutes.

---

## 📝 PART 1: Ag Services Integration

### File: `AgriculturalServicesView.swift`

#### Step 1.1: Add Media Field to AgServicesData

Find the `AgServicesData` struct (search for `struct AgServicesData`) and add the media field:

```swift
struct AgServicesData: Codable, Equatable {
    var customerName = ""
    var mailingAddress = ""
    var startDate = Date()
    var services: [AgServiceLineItem] = []
    var notes = ""
    var signatureData: Data?
    var paymentMethodRaw: String?
    
    // ✅ ADD THIS LINE:
    var mediaItems: [JobMediaItem] = []
    
    var paymentMethod: PaymentMethod {
        // ... existing code ...
    }
    // ... rest of struct ...
}
```

#### Step 1.2: Add Media Section to Form

In the `AgriculturalServicesView` body, find the Form and add this section BEFORE the signature section:

```swift
// ✅ ADD THIS ENTIRE SECTION:
Section {
    NavigationLink {
        if let recordID = currentRecord?.id {
            JobMediaGalleryView(
                jobID: recordID,
                jobType: .agServices,
                mediaItems: Binding(
                    get: { data.mediaItems },
                    set: { data.mediaItems = $0 }
                )
            )
        }
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
    .disabled(currentRecord == nil)
} footer: {
    Text("Document this job with before and after photos or videos.")
}
```

### File: `AgServicesStorage.swift`

#### Step 1.3: Load Media When Loading Records

Find the `loadAll()` function and modify it:

```swift
static func loadAll() -> [AgServicesRecord] {
    ensureDir()
    guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
    var records: [AgServicesRecord] = []
    
    for url in urls where url.pathExtension.lowercased() == "json" {
        if let data = try? Data(contentsOf: url),
           var rec = try? JSONDecoder().decode(AgServicesRecord.self, from: data) {
            // ✅ ADD THESE TWO LINES:
            rec.data.mediaItems = JobMediaStorage.loadMedia(jobID: rec.id, jobType: .agServices)
            
            records.append(rec)
        }
    }
    // Newest first
    return records.sorted { ($0.updatedAt, $0.createdAt) > ($1.updatedAt, $1.createdAt) }
}
```

#### Step 1.4: Save Media When Saving Records

Find the `save(_ record:)` function and add media save at the end:

```swift
static func save(_ record: AgServicesRecord) {
    ensureDir()
    var rec = record
    rec.updatedAt = Date()
    let name = filename(for: rec)
    
    // Remove stale copies...
    if let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
        for url in urls where url.lastPathComponent.hasPrefix(rec.id.uuidString) && url.lastPathComponent != name {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    let fileURL = dir.appendingPathComponent(name)
    guard let data = try? JSONEncoder().encode(rec) else { return }
    
    do {
        try data.write(to: fileURL, options: [.atomic])
        applyFileProtection(fileURL)
        
        // ✅ ADD THESE TWO LINES:
        JobMediaStorage.saveMedia(rec.data.mediaItems, jobID: rec.id, jobType: .agServices)
    } catch {
        // ignore
    }
}
```

#### Step 1.5: Delete Media When Deleting Records

Find the `delete(id:)` function and add media cleanup:

```swift
static func delete(id: UUID) {
    ensureDir()
    let prefix = id.uuidString
    
    if let url = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        .first(where: { $0.lastPathComponent.hasPrefix(prefix) }) {
        try? FileManager.default.removeItem(at: url)
    }
    
    // ✅ ADD THIS LINE:
    JobMediaStorage.deleteAllMedia(jobID: id, jobType: .agServices)
}
```

---

## 📝 PART 2: Milling Jobs Integration

### File: `MillingJobs.swift`

#### Step 2.1: Add Media Field to MillingJob

Find the `MillingJob` struct and add the media field:

```swift
struct MillingJob: Identifiable, Codable, Hashable {
    static let mobilizationFee = 300.0

    var id = UUID()
    var jobNumber: Int = 0
    var customerName: String = ""
    var date: Date = Date()
    var notes: String = ""
    var completed: Bool = false
    var sawmillMobilization: Bool = false
    var skidSteerMobilization: Bool = false
    var lines: [MillingLine] = []
    
    // ✅ ADD THIS LINE:
    var mediaItems: [JobMediaItem] = []
    
    init(jobNumber: Int = 0) {
        self.jobNumber = jobNumber
        // ✅ ADD THIS LINE:
        self.mediaItems = []
    }
    
    // ... rest of struct ...
}
```

#### Step 2.2: Update CodingKeys

Find the `CodingKeys` enum and add mediaItems:

```swift
enum CodingKeys: String, CodingKey {
    case id, jobNumber, customerName, date, notes, completed
    case sawmillMobilization, skidSteerMobilization, lines
    case mediaItems  // ✅ ADD THIS
}
```

#### Step 2.3: Update Custom Decoder

Find the `init(from decoder:)` and add media decoding:

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    jobNumber = try container.decodeIfPresent(Int.self, forKey: .jobNumber) ?? 0
    customerName = try container.decodeIfPresent(String.self, forKey: .customerName) ?? ""
    date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
    notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    completed = try container.decodeIfPresent(Bool.self, forKey: .completed) ?? false
    sawmillMobilization = try container.decodeIfPresent(Bool.self, forKey: .sawmillMobilization) ?? false
    skidSteerMobilization = try container.decodeIfPresent(Bool.self, forKey: .skidSteerMobilization) ?? false
    lines = try container.decodeIfPresent([MillingLine].self, forKey: .lines) ?? []
    
    // ✅ ADD THIS LINE:
    mediaItems = try container.decodeIfPresent([JobMediaItem].self, forKey: .mediaItems) ?? []
}
```

#### Step 2.4: Update MillingJobStorage - Load

Find `loadAll()` in `MillingJobStorage` and modify:

```swift
static func loadAll() -> [MillingJob] {
    ensureDir()
    guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
    var jobs: [MillingJob] = []
    
    for url in urls where url.pathExtension.lowercased() == "json" {
        if let data = try? Data(contentsOf: url),
           var job = try? JSONDecoder().decode(MillingJob.self, from: data) {
            // ✅ ADD THIS LINE:
            job.mediaItems = JobMediaStorage.loadMedia(jobID: job.id, jobType: .milling)
            
            jobs.append(job)
        }
    }
    return jobs.sorted { $0.date > $1.date }
}
```

#### Step 2.5: Update MillingJobStorage - Save

Find `save(_ job:)` and add media save:

```swift
static func save(_ job: MillingJob) {
    ensureDir()
    let fileURL = dir.appendingPathComponent(filename(for: job))
    guard let data = try? JSONEncoder().encode(job) else { return }
    
    do {
        try data.write(to: fileURL, options: [.atomic])
        applyFileProtection(fileURL)
        
        // ✅ ADD THIS LINE:
        JobMediaStorage.saveMedia(job.mediaItems, jobID: job.id, jobType: .milling)
    } catch {
        // ignore
    }
}
```

#### Step 2.6: Update MillingJobStorage - Delete

Find `delete(id:)` and add media cleanup:

```swift
static func delete(id: UUID) {
    ensureDir()
    if let url = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        .first(where: { $0.lastPathComponent.contains(id.uuidString) }) {
        try? FileManager.default.removeItem(at: url)
    }
    
    // ✅ ADD THIS LINE:
    JobMediaStorage.deleteAllMedia(jobID: id, jobType: .milling)
}
```

#### Step 2.7: Add Media Section to Milling Job Form

Find `MillingJobsView` and add this section to the Form (before the notes section is a good spot):

```swift
// ✅ ADD THIS ENTIRE SECTION:
Section {
    NavigationLink {
        JobMediaGalleryView(
            jobID: job.id,
            jobType: .milling,
            mediaItems: Binding(
                get: { job.mediaItems },
                set: { 
                    job.mediaItems = $0
                    MillingJobStorage.save(job)
                }
            )
        )
    } label: {
        HStack {
            Label("Job Photos & Videos", systemImage: "photo.on.rectangle")
            Spacer()
            if !job.mediaItems.isEmpty {
                Text("\(job.mediaItems.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
} footer: {
    Text("Document this milling job with before and after photos or videos.")
}
```

---

## 📝 PART 3: Lumber Orders Integration

### File: `LumberOrdersView.swift`

#### Step 3.1: Add Media Field to LumberOrder

Find the `LumberOrder` struct and add the media field:

```swift
struct LumberOrder: Identifiable, Codable, Hashable {
    var id = UUID()
    var customerName: String = ""
    var createdAt: Date = Date()
    var lines: [CutLine] = []
    
    // ✅ ADD THIS LINE:
    var mediaItems: [JobMediaItem] = []
    
    var subtotal: Double {
        lines.reduce(0) { $0 + SawmillPricing.evaluate($1).total }
    }
    // ... rest of struct ...
}
```

#### Step 3.2: Update OrderStorage - Load

Find `OrderStorage.load()` and modify:

```swift
static func load() -> [LumberOrder] {
    ensureDir()
    guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
    var orders: [LumberOrder] = []
    
    for url in urls where url.pathExtension.lowercased() == "json" {
        if let data = try? Data(contentsOf: url),
           var order = try? JSONDecoder().decode(LumberOrder.self, from: data) {
            // ✅ ADD THIS LINE:
            order.mediaItems = JobMediaStorage.loadMedia(jobID: order.id, jobType: .lumberOrder)
            
            orders.append(order)
        }
    }
    return orders.sorted { $0.createdAt > $1.createdAt }
}
```

#### Step 3.3: Update OrderStorage - Save

Find `save(_ order:)` and add media save:

```swift
static func save(_ order: LumberOrder) {
    ensureDir()
    let filename = "\(order.id.uuidString).json"
    let fileURL = dir.appendingPathComponent(filename)
    
    guard let data = try? JSONEncoder().encode(order) else { return }
    do {
        try data.write(to: fileURL, options: [.atomic])
        applyFileProtection(fileURL)
        
        // ✅ ADD THIS LINE:
        JobMediaStorage.saveMedia(order.mediaItems, jobID: order.id, jobType: .lumberOrder)
    } catch {
        // ignore
    }
}
```

#### Step 3.4: Update OrderStorage - Delete

Find `delete(id:)` and add media cleanup:

```swift
static func delete(id: UUID) {
    ensureDir()
    let filename = "\(id.uuidString).json"
    let fileURL = dir.appendingPathComponent(filename)
    try? FileManager.default.removeItem(at: fileURL)
    
    // ✅ ADD THIS LINE:
    JobMediaStorage.deleteAllMedia(jobID: id, jobType: .lumberOrder)
}
```

#### Step 3.5: Add Media Section to Order Detail

In the order detail view form, add this section:

```swift
// ✅ ADD THIS ENTIRE SECTION:
Section {
    NavigationLink {
        JobMediaGalleryView(
            jobID: order.id,
            jobType: .lumberOrder,
            mediaItems: Binding(
                get: { order.mediaItems },
                set: { 
                    order.mediaItems = $0
                    OrderStorage.save(order)
                }
            )
        )
    } label: {
        HStack {
            Label("Order Photos & Videos", systemImage: "photo.on.rectangle")
            Spacer()
            if !order.mediaItems.isEmpty {
                Text("\(order.mediaItems.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
} footer: {
    Text("Document this order with photos or videos.")
}
```

---

## ✅ Testing After Integration

### Test Each Job Type:

1. **Create a new job**
2. **Open the job details**
3. **Tap "Job Photos & Videos"**
4. **Tap "Add Photos or Videos"**
5. **Select "Before" or "After"**
6. **Choose "Take Photo" (if you have camera access)**
   - Take a photo
   - Should appear in the gallery
7. **Test "Choose Photo"**
   - Pick from library
   - Should save and appear
8. **Tap a photo to view full screen**
9. **Swipe to delete a photo**
10. **Close app and reopen**
    - Media should still be there
11. **Delete the job**
    - Media files should be cleaned up

### Common Issues:

**"Cannot find JobMediaGalleryView"**
- Make sure `JobMediaFeature.swift` is in your project

**"Cannot find JobMediaStorage"**
- Check that the file is included in your build target

**Photos don't save**
- Check Info.plist has camera/photo library permissions

**Videos don't play**
- Ensure AVKit is imported in JobMediaFeature.swift

---

## 📱 Required Info.plist Entries

Add these to your Info.plist if not already present:

```xml
<key>NSCameraUsageDescription</key>
<string>Take photos to document jobs</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>Choose photos and videos to document jobs</string>
```

---

## 🎯 Summary

You've now:
- ✅ Added media support to 3 job types
- ✅ Integrated photo/video capture
- ✅ Added Before/After organization
- ✅ Implemented local encrypted storage
- ✅ Added gallery views
- ✅ Enabled full-screen viewing
- ✅ Added swipe-to-delete
- ✅ Implemented persistence
- ✅ Added cleanup on job deletion

**Next Step**: Test thoroughly, then consider implementing the Wi-Fi sync feature using Multipeer Connectivity.

---

**Estimated Time**: 45-90 minutes for all three integrations  
**Build After**: Each integration to catch errors early  
**Test After**: Each integration before moving to the next
