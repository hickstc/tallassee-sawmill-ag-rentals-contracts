//
//  JobCalendarSync.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  Optional Apple Calendar (EventKit) sync for the unified scheduler.
//  Jobs become timed events; date-based maintenance items become all-day
//  events on their due date. Each object stores its event identifier so a
//  re-sync updates the existing event instead of creating duplicates.
//

import Foundation
import EventKit

@MainActor
enum JobCalendarSync {

    /// UserDefaults key for the opt-in sync toggle (off by default).
    static let enabledKey = "scheduleCalendarSyncEnabled"

    private static let store = EKEventStore()

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Asks for full calendar access if not yet determined. Full access is
    /// needed (rather than write-only) so existing events can be found by
    /// identifier and updated in place.
    static func ensureAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .notDetermined:
            return (try? await store.requestFullAccessToEvents()) ?? false
        default:
            return false
        }
    }

    // MARK: Jobs

    /// Creates or updates the calendar event for a job. No-op when sync is
    /// off or access is denied.
    static func sync(_ job: ScheduledJob) async {
        guard isEnabled, await ensureAccess() else { return }

        // Cancelled jobs shouldn't sit on the calendar.
        guard job.status != .cancelled else {
            await removeEvent(withIdentifier: job.calendarEventID)
            job.calendarEventID = ""
            return
        }

        let event = existingOrNewEvent(identifier: job.calendarEventID)
        event.title = "\(job.type.rawValue): \(job.customer.isEmpty ? job.jobID : job.customer)"
        event.startDate = job.date
        event.endDate = job.endDate
        event.isAllDay = false
        event.location = job.address.isEmpty ? nil : job.address
        event.notes = notes(for: job)

        try? store.save(event, span: .thisEvent)
        if let identifier = event.eventIdentifier {
            job.calendarEventID = identifier
        }
    }

    /// Customer details embedded in the event so the calendar alone is
    /// enough to work from in the field.
    private static func notes(for job: ScheduledJob) -> String {
        var lines = ["\(job.jobID) — \(job.type.rawValue)"]
        if !job.customer.isEmpty { lines.append("Customer: \(job.customer)") }
        if !job.phone.isEmpty { lines.append("Phone: \(job.phone)") }
        if !job.address.isEmpty { lines.append("Address: \(job.address)") }
        lines.append("Status: \(job.status.rawValue)")
        if !job.notes.isEmpty {
            lines.append("")
            lines.append(job.notes)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Maintenance

    /// Creates or updates an all-day event on a maintenance item's due date,
    /// or removes the event when the item no longer has one.
    static func syncMaintenance(_ task: MaintenanceTask) async {
        guard isEnabled, await ensureAccess() else { return }

        guard let due = task.nextDueDate else {
            await removeEvent(withIdentifier: task.calendarEventID)
            task.calendarEventID = ""
            return
        }

        let event = existingOrNewEvent(identifier: task.calendarEventID)
        let machine = task.equipment?.name ?? "Equipment"
        event.title = "Maintenance due: \(machine) — \(task.name)"
        event.startDate = Calendar.current.startOfDay(for: due)
        event.endDate = event.startDate
        event.isAllDay = true
        event.notes = task.dueSummary

        try? store.save(event, span: .thisEvent)
        if let identifier = event.eventIdentifier {
            task.calendarEventID = identifier
        }
    }

    // MARK: Shared

    static func removeEvent(withIdentifier identifier: String) async {
        guard !identifier.isEmpty, await ensureAccess() else { return }
        guard let event = store.event(withIdentifier: identifier) else { return }
        try? store.remove(event, span: .thisEvent)
    }

    /// Pushes every active job and dated maintenance item to the calendar —
    /// used when the toggle is first switched on.
    static func syncAll(jobs: [ScheduledJob], tasks: [MaintenanceTask]) async {
        guard isEnabled, await ensureAccess() else { return }
        for job in jobs where job.status.isActive {
            await sync(job)
        }
        for task in tasks where task.nextDueDate != nil {
            await syncMaintenance(task)
        }
    }

    private static func existingOrNewEvent(identifier: String) -> EKEvent {
        if !identifier.isEmpty, let existing = store.event(withIdentifier: identifier) {
            return existing
        }
        let event = EKEvent(eventStore: store)
        event.calendar = store.defaultCalendarForNewEvents
        return event
    }
}
