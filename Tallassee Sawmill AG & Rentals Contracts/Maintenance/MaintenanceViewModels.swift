//
//  MaintenanceViewModels.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  MVVM layer for the maintenance module: pure presentation logic that the
//  views bind their @Query results through, plus local-notification reminders.
//  Keeping this out of the views makes the bucketing rules unit-testable.
//

import Foundation
import SwiftData
import UserNotifications

// MARK: - Dashboard bucketing

/// A maintenance task paired with its evaluated status, ready for display.
struct DashboardEntry: Identifiable {
    let task: MaintenanceTask
    let status: MaintenanceStatus

    var id: PersistentIdentifier { task.persistentModelID }
    var equipmentName: String { task.equipment?.name ?? "Unassigned" }
}

/// Groups tasks into the dashboard's color-coded sections.
struct DashboardBuckets {
    var overdue: [DashboardEntry] = []
    var dueSoon: [DashboardEntry] = []
    var upToDate: [DashboardEntry] = []

    /// Buckets every scheduled task by urgency. Unscheduled tasks are omitted —
    /// they appear on their machine's detail screen instead.
    init(tasks: [MaintenanceTask], asOf now: Date = .now) {
        for task in tasks {
            let entry = DashboardEntry(task: task, status: task.status(asOf: now))
            switch entry.status {
            case .overdue: overdue.append(entry)
            case .dueSoon: dueSoon.append(entry)
            case .upToDate: upToDate.append(entry)
            case .notScheduled: break
            }
        }
        // Most urgent first within each bucket.
        overdue.sort { ($0.task.nextDueDate ?? .distantPast) < ($1.task.nextDueDate ?? .distantPast) }
        dueSoon.sort { ($0.task.nextDueDate ?? .distantFuture) < ($1.task.nextDueDate ?? .distantFuture) }
    }

    /// Service logs completed within the last `days`, newest first.
    static func recentLogs(_ logs: [MaintenanceLog], within days: Int = 30, asOf now: Date = .now) -> [MaintenanceLog] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return [] }
        return logs
            .filter { $0.date >= cutoff }
            .sorted { $0.date > $1.date }
    }
}

// MARK: - Reminder scheduling

/// Schedules local notifications for date-based maintenance reminders.
/// Notification identifiers are derived from the task's stable UUID so a
/// reschedule replaces the previous request.
enum ReminderScheduler {

    /// Asks for notification permission if not yet determined.
    /// Returns true when notifications are allowed.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        default:
            return false
        }
    }

    /// Schedules (or cancels) the reminder for a task based on its current
    /// state. Call after any change to the schedule or after completing a service.
    static func sync(task: MaintenanceTask) {
        let identifier = notificationIdentifier(for: task.uuid)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard task.reminderEnabled, let dueDate = task.nextDueDate else { return }

        // Fire at 9 AM, `reminderLeadDays` before the due date (or at the due
        // date itself if the lead time has already passed).
        var fireDate = Calendar.current.date(
            byAdding: .day, value: -task.reminderLeadDays, to: dueDate
        ) ?? dueDate
        if fireDate <= .now { fireDate = dueDate }
        guard fireDate > .now else { return } // already overdue; dashboard shows it in red

        var components = Calendar.current.dateComponents([.year, .month, .day], from: fireDate)
        components.hour = 9

        let content = UNMutableNotificationContent()
        content.title = "Maintenance due"
        let machine = task.equipment?.name ?? "Equipment"
        content.body = "\(machine): \(task.name) is due \(dueDate.formatted(date: .abbreviated, time: .omitted))."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    /// Cancels the pending reminder for a deleted task.
    static func cancel(taskUUID: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationIdentifier(for: taskUUID)])
    }

    private static func notificationIdentifier(for uuid: UUID) -> String {
        "maintenance-task-\(uuid.uuidString)"
    }
}
