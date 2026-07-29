//
//  SchedulingModels.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  Unified scheduling: one ScheduledJob model shared by every job type
//  (rentals, ag services, milling, lumber orders, deliveries, …), plus the
//  bucketing logic that merges date-based equipment maintenance into the
//  same schedule.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Job Type

enum JobType: String, CaseIterable, Identifiable {
    case rental = "Rental"
    case agServices = "Ag Services"
    case milling = "Milling"
    case lumberOrder = "Lumber Order"
    case delivery = "Delivery"
    case maintenance = "Maintenance"
    case other = "Other"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .rental: return "house.fill"
        case .agServices: return "leaf.fill"
        case .milling: return "tree.fill"
        case .lumberOrder: return "list.bullet.rectangle"
        case .delivery: return "box.truck.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .other: return "briefcase.fill"
        }
    }
}

// MARK: - Job Status

enum JobStatus: String, CaseIterable, Identifiable {
    case scheduled = "Scheduled"
    case inProgress = "In Progress"
    case completed = "Completed"
    case cancelled = "Cancelled"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .scheduled: return .blue
        case .inProgress: return .orange
        case .completed: return .green
        case .cancelled: return .gray
        }
    }

    var systemImage: String {
        switch self {
        case .scheduled: return "calendar"
        case .inProgress: return "play.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    /// Statuses that still occupy a slot on the schedule.
    var isActive: Bool { self == .scheduled || self == .inProgress }
}

// MARK: - Scheduled Job

/// One entry in the unified scheduler. CloudKit-safe like the rest of the
/// models: defaults everywhere, no unique constraints.
@Model
final class ScheduledJob {
    var uuid: UUID = UUID()
    /// Sequential number backing the human-readable job ID ("JOB-0042").
    var jobNumber: Int = 0
    var customer: String = ""
    var typeRaw: String = JobType.other.rawValue
    /// Scheduled start, including time of day.
    var date: Date = Date()
    var durationMinutes: Int = 60
    var address: String = ""
    var phone: String = ""
    var notes: String = ""
    var statusRaw: String = JobStatus.scheduled.rawValue
    /// EventKit identifier of the synced calendar event ("" = not synced).
    /// Used to update in place instead of creating duplicates.
    var calendarEventID: String = ""
    var createdAt: Date = Date()

    init(
        jobNumber: Int = 0,
        customer: String = "",
        type: JobType = .other,
        date: Date = Date(),
        durationMinutes: Int = 60,
        address: String = "",
        phone: String = "",
        notes: String = ""
    ) {
        self.jobNumber = jobNumber
        self.customer = customer
        self.typeRaw = type.rawValue
        self.date = date
        self.durationMinutes = durationMinutes
        self.address = address
        self.phone = phone
        self.notes = notes
    }

    var type: JobType {
        get { JobType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    var status: JobStatus {
        get { JobStatus(rawValue: statusRaw) ?? .scheduled }
        set { statusRaw = newValue.rawValue }
    }

    var jobID: String { String(format: "JOB-%04d", jobNumber) }

    var endDate: Date {
        date.addingTimeInterval(TimeInterval(max(durationMinutes, 15) * 60))
    }

    /// Still active but its day has passed.
    func isOverdue(asOf now: Date = .now) -> Bool {
        status.isActive && date < Calendar.current.startOfDay(for: now)
    }
}

// MARK: - Unified schedule entries

/// One row of the unified schedule: either a scheduled job or a date-based
/// maintenance item (meter-only maintenance can't sit on a calendar, so it
/// stays on the maintenance dashboard instead).
struct ScheduleEntry: Identifiable {
    let id: String
    let date: Date
    let job: ScheduledJob?
    let maintenanceTask: MaintenanceTask?

    init(job: ScheduledJob) {
        self.id = "job-\(job.uuid)"
        self.date = job.date
        self.job = job
        self.maintenanceTask = nil
    }

    init(task: MaintenanceTask, dueDate: Date) {
        self.id = "task-\(task.uuid)"
        self.date = dueDate
        self.job = nil
        self.maintenanceTask = task
    }
}

/// Overdue / today / upcoming buckets combining jobs and maintenance.
struct ScheduleBuckets {
    var overdue: [ScheduleEntry] = []
    var today: [ScheduleEntry] = []
    var upcoming: [ScheduleEntry] = []

    init(jobs: [ScheduledJob], tasks: [MaintenanceTask], asOf now: Date = .now) {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        var entries = jobs
            .filter { $0.status.isActive }
            .map { ScheduleEntry(job: $0) }
        entries += tasks.compactMap { task in
            guard let due = task.nextDueDate else { return nil }
            return ScheduleEntry(task: task, dueDate: due)
        }

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            if calendar.isDateInToday(entry.date) {
                today.append(entry)
            } else if entry.date < startOfToday {
                overdue.append(entry)
            } else {
                upcoming.append(entry)
            }
        }
    }
}
