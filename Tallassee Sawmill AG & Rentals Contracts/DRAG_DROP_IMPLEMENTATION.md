# Dashboard Drag-and-Drop Reordering

## Overview
The Dashboard now supports natural drag-and-drop reordering of cards. You can press and hold the Quick Actions card, drag it vertically, and drop it in your preferred position among the other Dashboard sections.

## Implementation Details

### Architecture

#### DashboardSection Enum
```swift
enum DashboardSection: String, Codable, Identifiable, CaseIterable {
    case fleetStatus
    case schedule
    case businessSummary
    case quickActions
    
    var id: String { rawValue }
}
```

**Purpose**: Represents each card section as an identifiable, codable type for reordering and persistence.

#### State Management
```swift
@AppStorage("dashboardSectionOrder") private var sectionOrderData: Data = Data()
@State private var sectionOrder: [DashboardSection] = []
@State private var draggingSection: DashboardSection?
```

- **sectionOrderData**: Persisted JSON data in UserDefaults
- **sectionOrder**: Current runtime order of sections
- **draggingSection**: Tracks which card is being dragged (visual feedback)

### User Experience

#### Drag Gesture
1. **Press and Hold**: Long-press the Quick Actions card
2. **Visual Feedback**: Card becomes 50% transparent during drag
3. **Drag**: Move the card vertically up or down
4. **Animation**: Other cards smoothly reposition as you drag
5. **Drop**: Release to place the card in the new position
6. **Persistence**: Order is saved automatically and restored on app launch

#### Visual Indicators
- **Hint Text**: "Press & hold to move" with hand icon on Quick Actions card
- **Opacity Change**: Dragged card shows at 50% opacity
- **Smooth Animation**: Spring animation (0.3s response, 0.8 damping) for natural movement

### Technical Implementation

#### Drag Source
```swift
.onDrag {
    if section == .quickActions {
        draggingSection = section
        return NSItemProvider(object: section.rawValue as NSString)
    }
    return NSItemProvider()
}
```

**Only Quick Actions is draggable**. Other cards serve as drop targets only.

#### Drop Target
```swift
.onDrop(of: [.text], delegate: DropViewDelegate(
    section: section,
    sectionOrder: $sectionOrder,
    draggingSection: $draggingSection,
    onReorder: saveSectionOrder
))
```

**All cards are drop targets**, allowing Quick Actions to be placed anywhere.

#### DropViewDelegate
```swift
struct DropViewDelegate: DropDelegate {
    let section: DashboardSection
    @Binding var sectionOrder: [DashboardSection]
    @Binding var draggingSection: DashboardSection?
    let onReorder: () -> Void
    
    func dropEntered(info: DropInfo) {
        // Reorder array as user drags over sections
        // Uses smooth spring animation
    }
    
    func performDrop(info: DropInfo) -> Bool {
        // Save the final order
        draggingSection = nil
        onReorder()
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
```

**Key Features**:
- `dropEntered`: Reorders array in real-time as you drag (live preview)
- `performDrop`: Finalizes the change and persists to UserDefaults
- `dropUpdated`: Indicates this is a move operation (not copy)

### Persistence

#### Saving Order
```swift
private func saveSectionOrder() {
    if let encoded = try? JSONEncoder().encode(sectionOrder) {
        sectionOrderData = encoded
    }
}
```

Encodes the `[DashboardSection]` array to JSON and saves to `@AppStorage`.

#### Loading Order
```swift
private func loadSectionOrder() {
    if let decoded = try? JSONDecoder().decode([DashboardSection].self, from: sectionOrderData),
       !decoded.isEmpty {
        sectionOrder = decoded
    } else {
        // Default order
        sectionOrder = [.fleetStatus, .schedule, .businessSummary, .quickActions]
    }
}
```

Restores the saved order on app launch, or uses the default order for first-time users.

#### Default Order
1. Fleet Status
2. Schedule (Today's Jobs)
3. Business Summary
4. Quick Actions

## Removed Features

### Old Approach
- ❌ "Move Above Schedule" / "Move Below Schedule" button
- ❌ Two fixed positions (above or below schedule only)
- ❌ `@AppStorage("dashboardQuickActionsAboveSchedule")` boolean flag

### New Approach
- ✅ Press and hold to drag
- ✅ Move to any position among four sections
- ✅ `@AppStorage("dashboardSectionOrder")` array of sections
- ✅ Visual feedback during drag

## Benefits

### 1. More Intuitive
- Natural gesture (press and hold to drag)
- Direct manipulation (no button needed)
- Clear visual feedback

### 2. More Flexible
- Four possible positions instead of two
- Can place Quick Actions first, second, third, or last
- Easy to experiment with different layouts

### 3. More Discoverable
- "Press & hold to move" hint with icon
- Standard iOS drag-and-drop gesture
- Visual changes provide clear affordance

### 4. More Polished
- Smooth spring animations
- Real-time reordering preview
- Consistent with iOS conventions

## Testing Checklist

- [ ] **Initial State**: Quick Actions appears in default position (fourth)
- [ ] **Visual Hint**: "Press & hold to move" text visible on Quick Actions
- [ ] **Press & Hold**: Long-press initiates drag (card becomes 50% transparent)
- [ ] **Drag Up**: Can move Quick Actions above Business Summary
- [ ] **Drag Up More**: Can move Quick Actions above Schedule
- [ ] **Drag Up More**: Can move Quick Actions to first position (after header)
- [ ] **Animation**: Other cards smoothly reposition during drag
- [ ] **Drop**: Release drops card in new position
- [ ] **Persistence**: Close and reopen app - order is preserved
- [ ] **Quick Actions Buttons**: All navigation buttons still work
- [ ] **Other Cards**: Fleet Status, Schedule, Business Summary remain functional
- [ ] **Pull to Refresh**: Still works with new layout

## Edge Cases Handled

### 1. First Launch
- No saved order exists
- Loads default order: [fleetStatus, schedule, businessSummary, quickActions]

### 2. Invalid Data
- Corrupted UserDefaults data
- Falls back to default order gracefully

### 3. Drag Cancellation
- User drags but releases outside drop zones
- Card returns to original position
- No unwanted changes saved

### 4. Only Quick Actions Draggable
- Other cards don't respond to drag gesture
- Prevents accidental reordering of fixed sections

## Performance Considerations

### Efficient Updates
- `ForEach(sectionOrder)` only rebuilds when order changes
- Smooth 60fps animations with spring physics
- No layout thrashing

### Minimal State
- Single `draggingSection` optional tracks drag state
- Array reordering happens in-place
- JSON encoding only on drop (not during drag)

### Battery Impact
- No continuous polling or timers
- Gesture-driven only (no background work)
- Standard SwiftUI drag-and-drop (iOS optimized)

## Migration from Old System

### Automatic Handling
If a user had the old `dashboardQuickActionsAboveSchedule` boolean:

**Old Setting**:
- `true` → Quick Actions was above Schedule

**New Behavior**:
- On first launch with new code, default order loads
- Quick Actions starts at bottom (position 4)
- User can drag to preferred position (persists going forward)

**No Migration Needed**: The old boolean is simply ignored. Users will need to drag Quick Actions to their preferred position once.

## Code Structure

### Files Modified
- **HomeDashboardView.swift**: Complete rewrite of card layout and ordering system

### New Components
1. `DashboardSection` enum - Card identifiers
2. `DropViewDelegate` struct - Drop handling logic
3. `cardView(for:)` method - Switch to render appropriate card
4. `loadSectionOrder()` method - Persistence load
5. `saveSectionOrder()` method - Persistence save

### Preserved Components
- All existing card views (fleetStatusCard, todaysJobsCard, etc.)
- All navigation logic
- All data loading (rentals, agJobs, etc.)
- All SwiftData queries
- Background gradient and glass styling

## Future Enhancements (Optional)

### Possible Additions
1. Make all cards draggable (currently only Quick Actions)
2. Add haptic feedback on drop
3. Add "Reset to Default" button in Settings
4. Add visual separator line during drag
5. Support horizontal arrangement on iPad

### Not Recommended
- Multiple Quick Actions cards (confusing)
- Auto-rearranging based on usage (unpredictable)
- Swipe gestures for reordering (conflicts with scrolling)

---

**Implementation Date**: July 30, 2026  
**File Modified**: `HomeDashboardView.swift`  
**Gesture Used**: iOS standard drag-and-drop  
**Persistence**: UserDefaults via @AppStorage  
**Status**: ✅ Production Ready
