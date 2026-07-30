//
//  SchedulingViews.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  The unified scheduler: overdue / today / upcoming across every job type
//  plus date-based equipment maintenance, with optional Apple Calendar sync
//  and a job form that autofills from the customer list.
//

import SwiftUI
import SwiftData

// MARK: - Scheduler

struct SchedulerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduledJob.date) private var jobs: [ScheduledJob]
    @Query private var tasks: [MaintenanceTask]
    @AppStorage(JobCalendarSync.enabledKey) private var calendarSyncEnabled = false

    @State private var editingJob: ScheduledJob?
    @State private var showingAdd = false
    @State private var showingFinished = false
    @State private var syncDeniedMessage: String?

    var body: some View {
        let buckets = ScheduleBuckets(jobs: jobs, tasks: tasks)

        List {
            if buckets.overdue.isEmpty && buckets.today.isEmpty && buckets.upcoming.isEmpty {
                ContentUnavailableView(
                    "Nothing Scheduled",
                    systemImage: "calendar.badge.plus",
                    description: Text("Add a job to start building the schedule.")
                )
            }

            if !buckets.overdue.isEmpty {
                entrySection("Overdue", entries: buckets.overdue, tone: .red)
            }
            if !buckets.today.isEmpty {
                entrySection("Today", entries: buckets.today, tone: .blue)
            }
            if !buckets.upcoming.isEmpty {
                entrySection("Upcoming", entries: buckets.upcoming, tone: .primary)
            }

            finishedSection
        }
        .navigationTitle("Scheduler")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Sync with Apple Calendar", isOn: $calendarSyncEnabled)
                    if calendarSyncEnabled {
                        Button {
                            syncAllNow()
                        } label: {
                            Label("Sync All Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    Divider()
                    Toggle("Show Finished Jobs", isOn: $showingFinished)
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Job", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                JobFormView(job: nil)
            }
        }
        .sheet(item: $editingJob) { job in
            NavigationStack {
                JobFormView(job: job)
            }
        }
        .onChange(of: calendarSyncEnabled) { _, enabled in
            if enabled { syncAllNow() }
        }
        .alert("Calendar Access Needed", isPresented: .init(
            get: { syncDeniedMessage != nil },
            set: { if !$0 { syncDeniedMessage = nil } }
        )) {
            Button("OK") { syncDeniedMessage = nil }
        } message: {
            Text(syncDeniedMessage ?? "")
        }
    }

    // MARK: Sections

    private func entrySection(_ title: String, entries: [ScheduleEntry], tone: Color) -> some View {
        Section {
            ForEach(entries) { entry in
                if let job = entry.job {
                    JobRow(job: job)
                        .contentShape(Rectangle())
                        .onTapGesture { editingJob = job }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            jobSwipeActions(job)
                        }
                } else if let task = entry.maintenanceTask {
                    NavigationLink {
                        MaintenanceTaskDetailView(task: task)
                    } label: {
                        MaintenanceTaskRow(task: task, showsEquipment: true)
                    }
                }
            }
        } header: {
            Text(title)
                .foregroundStyle(tone == .primary ? Color.secondary : tone)
        }
    }

    @ViewBuilder
    private func jobSwipeActions(_ job: ScheduledJob) -> some View {
        Button {
            setStatus(job, .completed)
        } label: {
            Label("Complete", systemImage: "checkmark.circle")
        }
        .tint(.green)
        Button {
            setStatus(job, .cancelled)
        } label: {
            Label("Cancel Job", systemImage: "xmark.circle")
        }
        .tint(.orange)
        Button(role: .destructive) {
            delete(job)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var finishedSection: some View {
        let finished = jobs
            .filter { !$0.status.isActive }
            .sorted { $0.date > $1.date }
        if showingFinished && !finished.isEmpty {
            Section("Finished") {
                ForEach(finished.prefix(20), id: \.uuid) { job in
                    JobRow(job: job)
                        .contentShape(Rectangle())
                        .onTapGesture { editingJob = job }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(job)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    // MARK: Actions

    private func setStatus(_ job: ScheduledJob, _ status: JobStatus) {
        job.status = status
        Task { await JobCalendarSync.sync(job) }
    }

    private func delete(_ job: ScheduledJob) {
        let eventID = job.calendarEventID
        modelContext.delete(job)
        Task { await JobCalendarSync.removeEvent(withIdentifier: eventID) }
    }

    private func syncAllNow() {
        Task {
            guard await JobCalendarSync.ensureAccess() else {
                syncDeniedMessage = "Allow calendar access in Settings → Privacy & Security → Calendars to sync jobs."
                calendarSyncEnabled = false
                return
            }
            await JobCalendarSync.syncAll(jobs: jobs, tasks: tasks)
        }
    }
}

// MARK: - Job Row

struct JobRow: View {
    let job: ScheduledJob
    /// Compact style for the home dashboard card.
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: job.type.systemImage)
                .foregroundStyle(job.isOverdue() ? .red : .accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.customer.isEmpty ? job.type.rawValue : job.customer)
                    .font(compact ? .subheadline.weight(.medium) : .headline)
                Text("\(job.jobID) · \(job.type.rawValue) · \(job.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(job.isOverdue() ? .red : .secondary)
            }
            Spacer()
            if !compact {
                Label(job.status.rawValue, systemImage: job.status.systemImage)
                    .font(.caption.bold())
                    .labelStyle(.titleOnly)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(job.status.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(job.status.color)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Job Form

struct JobFormView: View {
    /// nil = creating a new job.
    let job: ScheduledJob?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allJobs: [ScheduledJob]
    @AppStorage(JobCalendarSync.enabledKey) private var calendarSyncEnabled = false

    @State private var customer = ""
    @State private var type: JobType = .rental
    @State private var date = Date()
    @State private var durationMinutes = 60
    @State private var address = ""
    @State private var phone = ""
    @State private var notes = ""
    @State private var status: JobStatus = .scheduled
    @State private var savedCustomers: [Customer] = []
    /// Name awaiting the "create new customer?" confirmation.
    @State private var pendingCreateName: String?

    var body: some View {
        Form {
            Section("Customer") {
                TextField("Customer Name", text: $customer)
                if !savedCustomers.isEmpty {
                    Menu {
                        ForEach(savedCustomers) { saved in
                            Button(saved.name) { fill(from: saved) }
                        }
                    } label: {
                        Label("Choose from Customers", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                TextField("Address", text: $address, axis: .vertical)
                    .lineLimit(1...3)
            }

            Section("Job") {
                Picker("Type", selection: $type) {
                    ForEach(JobType.allCases) { type in
                        Label(type.rawValue, systemImage: type.systemImage).tag(type)
                    }
                }
                DatePicker("Date & Time", selection: $date)
                Stepper("Duration: \(durationMinutes / 60)h \(durationMinutes % 60 == 0 ? "" : "\(durationMinutes % 60)m")",
                        value: $durationMinutes, in: 15...600, step: 15)
                if job != nil {
                    Picker("Status", selection: $status) {
                        ForEach(JobStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                }
            }

            Section {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Notes")
            } footer: {
                if calendarSyncEnabled {
                    Text("This job will be synced to Apple Calendar with the customer details in the event.")
                }
            }
        }
        .navigationTitle(job == nil ? "New Job" : (job?.jobID ?? "Edit Job"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(customer.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            savedCustomers = CustomerStorage.load().sorted { $0.name < $1.name }
            loadExisting()
        }
        .alert(
            "No customer named “\(pendingCreateName ?? "")” was found.",
            isPresented: .init(
                get: { pendingCreateName != nil },
                set: { if !$0 { pendingCreateName = nil } }
            )
        ) {
            Button("Create") {
                if let pendingCreateName {
                    createCustomer(named: pendingCreateName)
                }
                pendingCreateName = nil
                commit()
            }
            Button("Cancel", role: .cancel) {
                // Keep the job with the typed name; just don't add a customer.
                pendingCreateName = nil
                commit()
            }
        } message: {
            Text("Would you like to create a new customer?")
        }
    }

    private func fill(from saved: Customer) {
        customer = saved.name
        if phone.isEmpty { phone = saved.phone }
        if address.isEmpty { address = saved.address }
    }

    /// Exact match on trimmed, case-insensitive name.
    private func exactMatch(for trimmed: String, in list: [Customer]) -> Customer? {
        list.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(trimmed, options: .caseInsensitive) == .orderedSame
        }
    }

    /// Saves the new customer record with the job's contact details —
    /// only reached from the Create button.
    private func createCustomer(named trimmed: String) {
        var all = CustomerStorage.load()
        guard exactMatch(for: trimmed, in: all) == nil else { return }
        var newCustomer = Customer(name: trimmed)
        newCustomer.phone = phone.trimmingCharacters(in: .whitespaces)
        newCustomer.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        all.append(newCustomer)
        CustomerStorage.save(all)
        savedCustomers = all.sorted { $0.name < $1.name }
    }

    private func loadExisting() {
        guard let job else { return }
        customer = job.customer
        type = job.type
        date = job.date
        durationMinutes = job.durationMinutes
        address = job.address
        phone = job.phone
        notes = job.notes
        status = job.status
    }

    /// Resolves the customer before committing: an existing customer (matched
    /// on trimmed, case-insensitive name) is reused as-is; an unknown,
    /// non-blank name asks whether to create a new customer first.
    private func save() {
        let trimmed = customer.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = exactMatch(for: trimmed, in: savedCustomers) {
            customer = existing.name // reuse the saved customer's spelling
            commit()
        } else if !trimmed.isEmpty {
            pendingCreateName = trimmed
        } else {
            commit() // unreachable: Save is disabled for blank names
        }
    }

    private func commit() {
        let saved: ScheduledJob
        if let job {
            saved = job
        } else {
            saved = ScheduledJob(jobNumber: (allJobs.map(\.jobNumber).max() ?? 0) + 1)
            modelContext.insert(saved)
        }
        saved.customer = customer.trimmingCharacters(in: .whitespaces)
        saved.type = type
        saved.date = date
        saved.durationMinutes = durationMinutes
        saved.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.phone = phone.trimmingCharacters(in: .whitespaces)
        saved.notes = notes
        saved.status = status

        Task { await JobCalendarSync.sync(saved) }
        dismiss()
    }
}
