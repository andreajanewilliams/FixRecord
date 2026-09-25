import SwiftUI
import SwiftData
import PhotosUI

@main struct FixRecordApp: App {
    private let container: ModelContainer?
    private let storageError: String?
    init() {
        do { container = try ModelContainer(for: Job.self, BusinessProfile.self); storageError = nil }
        catch { container = nil; storageError = error.localizedDescription }
    }
    var body: some Scene {
        WindowGroup {
            if let container { RootView().tint(Brand.blue).modelContainer(container) }
            else { ContentUnavailableView("Unable to open local records", systemImage: "externaldrive.badge.exclamationmark", description: Text(storageError ?? "The local database is unavailable. Please try restarting the app.")) }
        }
    }
}

enum Brand {
    static let navy = Color(red: 0.07, green: 0.14, blue: 0.25)
    static let blue = Color(red: 0.04, green: 0.37, blue: 0.89)
    static let teal = Color(red: 0.07, green: 0.56, blue: 0.40)
    static let pale = Color(red: 0.92, green: 0.95, blue: 0.99)
    static let background = Color(red: 0.97, green: 0.98, blue: 0.995)
}

struct PrimaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).padding(14) }
            .buttonStyle(.plain).foregroundStyle(.white).background(Brand.blue, in: RoundedRectangle(cornerRadius: 13))
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Job.createdAt, order: .reverse) private var jobs: [Job]
    @Query private var profiles: [BusinessProfile]
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @State private var newJob = false
    @State private var selectedJob: Job?
    @State private var pendingJob: Job?
    @State private var exampleError: String?
    @State private var selection = 0
    @State private var homeFilter: JobFilter = .all
    var profile: BusinessProfile? { profiles.first }
    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView(jobs: jobs, newJob: $newJob, selectedJob: $selectedJob, filter: $homeFilter)
                    .navigationDestination(item: $selectedJob) { JobDetailView(job: $0) }
            }.tabItem { Label("Jobs", systemImage: "house.fill") }.tag(0)
            NavigationStack { TemplatesView() }.tabItem { Label("Templates", systemImage: "doc.text") }.tag(1)
            NavigationStack { SettingsView(profile: profile) }.tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
        }
        .fullScreenCover(isPresented: $newJob, onDismiss: {
            if let pendingJob { selectedJob = pendingJob; self.pendingJob = nil }
        }) { NavigationStack { CreateJobView(profile: profile) { job in pendingJob = job; newJob = false } } }
        .fullScreenCover(isPresented: Binding(get: { !didCompleteOnboarding && !ProcessInfo.processInfo.arguments.contains("-skip-onboarding") }, set: { if !$0 { didCompleteOnboarding = true } })) {
            OnboardingView { choice in
                switch choice {
                case .exampleJob:
                    if !jobs.contains(where: { $0.isSample }) {
                        context.insert(SampleJob.make())
                        do { try context.save() }
                        catch {
                            context.rollback()
                            exampleError = "The example job could not be saved. Please try again."
                            return
                        }
                    }
                    selectedJob = nil
                    homeFilter = .all
                    selection = 0
                    didCompleteOnboarding = true
                case .createJob:
                    selection = 0
                    didCompleteOnboarding = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { newJob = true }
                }
            }
            .alert("Could not add example", isPresented: Binding(get: { exampleError != nil }, set: { if !$0 { exampleError = nil } })) {
                Button("OK") { exampleError = nil }
            } message: { Text(exampleError ?? "") }
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-load-sample") && !jobs.contains(where: { $0.isSample }) {
                context.insert(SampleJob.make())
            }
        }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @State private var jobToDelete: Job?
    @State private var duplicateError: String?
    @State private var searchText = ""
    let jobs: [Job]
    @Binding var newJob: Bool
    @Binding var selectedJob: Job?
    @Binding var filter: JobFilter
    private var visibleJobs: [Job] { JobFilter.visible(jobs, status: filter, search: searchText) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 9) {
                    Image(systemName: "wrench.adjustable.fill").foregroundStyle(.white).padding(8).background(Brand.navy, in: RoundedRectangle(cornerRadius: 9))
                    Text("FixRecord").font(.headline).foregroundStyle(Brand.navy)
                    Spacer()
                }
                HStack {
                    Text("My Jobs").font(.largeTitle.bold()).foregroundStyle(Brand.navy)
                    Spacer()
                    Button { newJob = true } label: { Label("New Job", systemImage: "plus").font(.subheadline.bold()) }.buttonStyle(.borderedProminent)
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search jobs", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Search jobs")
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(JobFilter.allCases, id: \.self) { option in
                            Button { filter = option } label: {
                                Text(option.rawValue).font(.subheadline.weight(filter == option ? .semibold : .regular))
                                    .foregroundStyle(filter == option ? .white : Brand.navy)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(filter == option ? Brand.blue : .white, in: Capsule())
                            }
                            .accessibilityAddTraits(filter == option ? .isSelected : [])
                        }
                    }
                }
                if visibleJobs.isEmpty {
                    ContentUnavailableView(jobs.isEmpty ? "No jobs yet" : "No matching jobs", systemImage: searchText.isEmpty ? "doc.text.image" : "magnifyingglass", description: Text(jobs.isEmpty ? "Create a job or explore an example." : "Try a different search or status."))
                    if jobs.isEmpty { Button("Add Example Job") { context.insert(SampleJob.make()) }.buttonStyle(.bordered) }
                } else {
                    LazyVStack(spacing: 8) { ForEach(visibleJobs) { job in
                        Button { selectedJob = job } label: { JobRow(job: job) }.buttonStyle(.plain)
                            .contextMenu {
                                Button { duplicate(job) } label: { Label("Duplicate Job", systemImage: "plus.square.on.square") }
                                Button("Delete job", role: .destructive) { jobToDelete = job }
                            }
                    } }
                }
            }.padding(18)
        }.background(Brand.background).toolbar(.hidden, for: .navigationBar)
            .alert("Delete job?", isPresented: Binding(get: { jobToDelete != nil }, set: { if !$0 { jobToDelete = nil } })) {
                Button("Delete", role: .destructive) { if let job = jobToDelete { for photo in job.photos { PhotoStore.delete(photo.filename) }; for receipt in job.receipts { PhotoStore.delete(receipt.filename) }; context.delete(job) }; jobToDelete = nil }
                Button("Cancel", role: .cancel) { jobToDelete = nil }
            } message: { Text("This removes the local record and its photos.") }
            .alert("Could not duplicate job", isPresented: Binding(get: { duplicateError != nil }, set: { if !$0 { duplicateError = nil } })) {
                Button("OK") { duplicateError = nil }
            } message: { Text(duplicateError ?? "") }
    }
    private func duplicate(_ job: Job) {
        let prefix = job.number.split(separator: "-").first.map(String.init) ?? "FR"
        let number = "\(prefix)-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(4))"
        let copy = job.duplicated(number: number)
        context.insert(copy)
        do {
            try context.save()
            filter = .all
            searchText = ""
            selectedJob = copy
        } catch {
            context.delete(copy)
            duplicateError = "The duplicate could not be saved. Please try again."
        }
    }
}

enum JobFilter: String, CaseIterable {
    case all = "All", draft = "Draft", inProgress = "In Progress", completed = "Completed"
    var status: JobStatus? { switch self { case .all: nil; case .draft: .draft; case .inProgress: .inProgress; case .completed: .completed } }

    static func visible(_ jobs: [Job], status: JobFilter, search: String) -> [Job] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return jobs.filter { job in
            guard status == .all || job.status == status.status else { return false }
            guard !query.isEmpty else { return true }
            return [job.title, job.clientName, job.siteAddress, job.category, job.number]
                .contains { $0.localizedStandardContains(query) }
        }
    }
}

struct JobRow: View {
    let job: Job
    var body: some View {
        HStack(spacing: 12) {
            if let filename = job.photos.first?.filename, let image = PhotoStore.image(filename) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: 62, height: 62).clipped().clipShape(RoundedRectangle(cornerRadius: 9))
            } else { Image(systemName: "hammer.fill").frame(width: 62, height: 62).background(Brand.pale, in: RoundedRectangle(cornerRadius: 9)) }
            VStack(alignment: .leading, spacing: 4) { Text(job.title).font(.subheadline.bold()).lineLimit(1); Text(job.clientName.isEmpty ? job.siteAddress : job.clientName).font(.caption).foregroundStyle(.secondary).lineLimit(1); Text(job.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary) }
            Spacer(minLength: 4)
            Text(job.status.rawValue).font(.caption2.bold()).foregroundStyle(job.status == .completed ? Brand.teal : Brand.blue).padding(6).background(job.status == .completed ? Color.green.opacity(0.12) : Brand.pale, in: Capsule())
        }.foregroundStyle(Brand.navy).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 13))
    }
}

struct CreateJobView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Job.createdAt, order: .reverse) private var jobs: [Job]
    let profile: BusinessProfile?
    let onCreate: (Job) -> Void
    @State private var defaults = JobDefaultsService.shared
    @State private var presets = PresetStore.shared
    @State private var chosenPreset: SavedPreset?
    @State private var client = ""
    @State private var address = ""
    @State private var title = ""
    @State private var issue = ""
    @State private var technician = ""
    @State private var category = ""
    @State private var currencyCode = "USD"
    @State private var date = Date()
    @State private var showingCategory = false
    @State private var createdJob: Job?
    @State private var saveError = ""
    @State private var didPrefill = false
    @FocusState private var technicianFocused: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !presets.presets.isEmpty {
                    JobFormHeading("Start with")
                    JobFormCard {
                        Menu {
                            Button("Custom / no preset") {
                                chosenPreset = nil
                                technician = defaults.technician(for: profile)
                                category = defaults.category()
                                currencyCode = profile?.currencyCode ?? "USD"
                            }
                            ForEach(presets.presets) { preset in
                                Button(preset.name) {
                                    chosenPreset = preset
                                    technician = preset.technician.isEmpty ? defaults.technician(for: profile) : preset.technician
                                    category = preset.category.isEmpty ? defaults.category() : preset.category
                                    currencyCode = preset.business.currencyCode
                                }
                            }
                        } label: {
                            HStack {
                                Text("Preset").foregroundStyle(Brand.navy)
                                Spacer()
                                Text(chosenPreset?.name ?? "Custom").foregroundStyle(Brand.blue)
                                Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                JobFormHeading("Job")
                JobFormCard {
                    JobTextField("Job title", placeholder: "e.g. Kitchen Sink Repair", text: $title)
                    JobFormDivider()
                    JobTextField("Client name", placeholder: "e.g. Sarah Mitchell", text: $client)
                    JobFormDivider()
                    JobTextField("Property / Site (optional)", placeholder: "e.g. 12 Oak Avenue", text: $address)
                    JobFormDivider()
                    DatePicker("Date", selection: $date, displayedComponents: .date).font(.subheadline).foregroundStyle(Brand.navy)
                    JobFormDivider()
                    CurrencyPickerRow(currencyCode: $currencyCode)
                }
                JobFormHeading("Work")
                JobFormCard {
                    VoiceTextInput(title: "Reported Issue", placeholder: "What was reported?", text: $issue, minEditorHeight: 58)
                    JobFormDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Contractor / technician").font(.subheadline).foregroundStyle(Brand.navy)
                        TextField("e.g. Alex Turner", text: $technician).focused($technicianFocused)
                            .textContentType(.name).font(.body).foregroundStyle(Brand.navy)
                        if technicianFocused {
                            let suggestions = defaults.state.recentTechnicians.filter { $0.caseInsensitiveCompare(technician) != .orderedSame }
                            if !suggestions.isEmpty {
                                Text("Recent").font(.caption).foregroundStyle(.secondary)
                                ForEach(suggestions, id: \.self) { name in
                                    Button(name) { technician = name; technicianFocused = false }.font(.subheadline)
                                }
                            }
                        }
                    }
                    JobFormDivider()
                    Button { showingCategory = true; technicianFocused = false } label: {
                        HStack {
                            Text("Category").foregroundStyle(Brand.navy)
                            Spacer()
                            Text(category.isEmpty ? "Select category" : category).foregroundStyle(Brand.blue)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.font(.subheadline)
                    }.buttonStyle(.plain)
                }
            }.padding(18)
        }.background(Brand.background).navigationTitle("New Job").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Continue to Photos", icon: "camera") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                    .padding(.horizontal, 18).padding(.vertical, 10).background(Brand.background)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showingCategory) { CategorySelectionSheet(value: category) { category = $0 } }
            .navigationDestination(item: $createdJob) { job in JobPhotoStep(job: job) { onCreate(job) } }
            .alert("Could not save job", isPresented: Binding(get: { !saveError.isEmpty }, set: { if !$0 { saveError = "" } })) { Button("OK", role: .cancel) { saveError = "" } } message: { Text(saveError) }
            .onAppear {
                guard !didPrefill else { return }
                defaults.bootstrap(from: jobs)
                technician = defaults.technician(for: profile)
                category = defaults.category()
                currencyCode = profile?.currencyCode ?? "USD"
                if let preset = presets.defaultPreset {
                    chosenPreset = preset
                    if !preset.technician.isEmpty { technician = preset.technician }
                    if !preset.category.isEmpty { category = preset.category }
                    currencyCode = preset.business.currencyCode
                }
                didPrefill = true
            }
    }
    private func save() {
        let selectedPrefix = chosenPreset?.business.invoicePrefix ?? profile?.invoicePrefix ?? ""
        let prefix = selectedPrefix.isEmpty ? "FR" : selectedPrefix
        let number = "\(prefix)-\(Int(Date().timeIntervalSince1970))"
        let job = Job(number: number, title: title.trimmingCharacters(in: .whitespacesAndNewlines), clientName: client.trimmingCharacters(in: .whitespacesAndNewlines), siteAddress: address.trimmingCharacters(in: .whitespacesAndNewlines), category: category, issue: issue.trimmingCharacters(in: .whitespacesAndNewlines), technician: technician.trimmingCharacters(in: .whitespacesAndNewlines), businessName: profile?.businessName ?? "", currencyCode: currencyCode, taxRate: profile?.taxRate ?? "0")
        job.createdAt = date
        var documentPreset = chosenPreset ?? SavedPreset.custom(profile: profile)
        if documentPreset.business.currencyCode != currencyCode {
            documentPreset.id = UUID()
            documentPreset.name = "Custom"
            documentPreset.business.currencyCode = currencyCode
        }
        job.applyPreset(documentPreset, includeJobDefaults: false)
        context.insert(job)
        do {
            try context.save()
            defaults.remember(technician: job.technician, category: job.category)
            createdJob = job
        } catch {
            context.delete(job)
            saveError = error.localizedDescription
        }
    }
}

struct JobFormHeading: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View { Text(title).font(.headline).foregroundStyle(.secondary).padding(.leading, 10).padding(.top, 8) }
}

struct JobFormCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { VStack(alignment: .leading, spacing: 14) { content }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 18)) }
}

struct JobFormDivider: View {
    var body: some View { Divider().overlay(Brand.pale) }
}

struct JobTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    init(_ title: String, placeholder: String, text: Binding<String>) { self.title = title; self.placeholder = placeholder; _text = text }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(Brand.navy)
            TextField(placeholder, text: $text).font(.body).foregroundStyle(Brand.navy)
        }
    }
}

struct CategorySelectionSheet: View {
    private enum Choice: Equatable { case none, category(String), addCustom }
    @Environment(\.dismiss) private var dismiss
    @State private var defaults = JobDefaultsService.shared
    @State private var selected: Choice = .none
    @State private var customName = ""
    @State private var error = ""
    let value: String
    let onSelect: (String) -> Void
    private var known: Bool { JobCategories.builtIn.contains(value) || defaults.state.customCategories.contains(value) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    categoryRow("No category", choice: .none)
                    ForEach(JobCategories.builtIn, id: \.self) { categoryRow($0, choice: .category($0)) }
                    if !defaults.state.customCategories.isEmpty {
                        Text("Custom Categories").font(.caption).foregroundStyle(.secondary).padding(.top, 20).padding(.bottom, 7)
                        ForEach(defaults.state.customCategories, id: \.self) { categoryRow($0, choice: .category($0)) }
                    }
                    if !value.isEmpty && !known { categoryRow(value == "Other" ? "Other (saved category)" : value, choice: .category(value)) }
                    categoryRow("Other", choice: .addCustom)
                    if selected == .addCustom {
                        TextField("Custom category", text: $customName).textInputAutocapitalization(.words)
                            .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 10)).padding(.top, 12)
                        Text("Add your own category if it’s not listed.").font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                    }
                }.padding(18)
            }.background(Brand.background).navigationTitle("Select Category").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) { PrimaryButton(title: "Done", icon: "checkmark") { finish() }.padding(18).background(Brand.background) }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.presentationDetents([.large])
            .onAppear { selected = value.isEmpty ? .none : .category(value) }
            .alert("Choose another name", isPresented: Binding(get: { !error.isEmpty }, set: { if !$0 { error = "" } })) { Button("OK", role: .cancel) { error = "" } } message: { Text(error) }
    }
    private func categoryRow(_ title: String, choice: Choice) -> some View {
        VStack(spacing: 0) {
            Button { selected = choice } label: {
                HStack { Text(title); Spacer(); if selected == choice { Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(Brand.blue) } }
                    .foregroundStyle(selected == choice ? Brand.blue : Brand.navy)
                    .padding(.horizontal, 12).padding(.vertical, 13)
                    .background(selected == choice ? Brand.pale : .white, in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain)
            Divider().padding(.leading, 12)
        }
    }
    private func finish() {
        switch selected {
        case .addCustom:
            guard let value = defaults.addCustomCategory(customName) else { error = "Enter a category name other than ‘Other’ or ‘No category’."; return }
            onSelect(value)
        case .none: onSelect("")
        case .category(let value): onSelect(value)
        }
        dismiss()
    }
}

struct JobPhotoStep: View {
    let job: Job
    let onDone: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(Brand.blue).padding(18).background(Brand.pale, in: RoundedRectangle(cornerRadius: 18))
                Text("Add photos when useful").font(.title2.bold()).foregroundStyle(Brand.navy)
                Text("Your job is saved. You can capture before and after photos now, or continue without them.").foregroundStyle(.secondary)
                NavigationLink { PhotoCaptureView(job: job, kind: .before) } label: { Label("Capture Before", systemImage: "camera").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.bordered)
                NavigationLink { PhotoCaptureView(job: job, kind: .after) } label: { Label("Capture After", systemImage: "camera.fill").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.bordered)
            }.padding(22)
        }.background(Brand.background).navigationTitle("Photos").navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) { PrimaryButton(title: job.photos.isEmpty ? "Continue without Photos" : "Finish Job", icon: "checkmark") { onDone() }.padding(18).background(Brand.background) }
    }
}

struct JobDetailView: View {
    @Bindable var job: Job
    @State private var editing = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(job.title).font(.title.bold()).foregroundStyle(Brand.navy)
                    Text(job.clientName).font(.subheadline)
                    if !job.siteAddress.isEmpty { Label(job.siteAddress, systemImage: "mappin").font(.caption).foregroundStyle(.secondary) }
                    Text(job.number).font(.caption).foregroundStyle(.secondary)
                    if job.isSample { Label("EXAMPLE JOB", systemImage: "info.circle.fill").font(.caption.bold()).foregroundStyle(Brand.blue) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Job progress").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Menu {
                        ForEach(JobStatus.allCases, id: \.self) { status in
                            Button { job.status = status } label: {
                                if job.status == status { Label(status.rawValue, systemImage: "checkmark") }
                                else { Text(status.rawValue) }
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: job.status == .completed ? "checkmark.circle.fill" : "circle.inset.filled")
                                .font(.title3).foregroundStyle(job.status == .completed ? Brand.teal : Brand.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.status.rawValue).font(.headline).foregroundStyle(Brand.navy)
                                Text(job.status == .draft ? "Ready to start" : job.status == .inProgress ? "Work underway" : "Work finished")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Change").font(.subheadline).foregroundStyle(Brand.blue)
                            Image(systemName: "chevron.down").font(.caption).foregroundStyle(Brand.blue)
                        }
                        .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .accessibilityLabel("Job progress, \(job.status.rawValue). Change status")
                }
                NavigationLink { PhotoReviewView(job: job) } label: { feature("Photos", subtitle: "Add or review before and after", icon: "photo.on.rectangle.angled") }
                NavigationLink { NotesView(job: job) } label: { feature("Work Details", subtitle: "Issue and work completed", icon: "text.alignleft") }
                NavigationLink { PricingView(job: job) } label: { feature("Materials & Pricing", subtitle: "Add items when you need an invoice", icon: "list.bullet.rectangle") }
                NavigationLink { ExportView(job: job) } label: { feature("Preview & Export", subtitle: "Work report, invoice or client pack", icon: "doc.richtext") }
                if job.status == .completed { Toggle("I confirm this work record", isOn: $job.technicianConfirmed).font(.subheadline) }
            }.padding()
        }.background(Brand.background).navigationTitle("Job Details").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Edit") { editing = true } }
            .sheet(isPresented: $editing) { NavigationStack { JobEditView(job: job) } }
    }
    private func feature(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 14) { Image(systemName: icon).font(.title3).foregroundStyle(Brand.blue).frame(width: 28); VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline.bold()); Text(subtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }
            .foregroundStyle(Brand.navy).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 13))
    }
}

struct BusinessProfileView: View {
    @Bindable var profile: BusinessProfile
    @StateObject private var entitlements = EntitlementService.shared
    @State private var selectedLogo: PhotosPickerItem?
    @State private var showingUpgrade = false
    var body: some View {
        Form {
            Section("Business") {
                if entitlements.isPro, let logo = PhotoStore.image(profile.logoFilename) { Image(uiImage: logo).resizable().scaledToFit().frame(height: 70) }
                if entitlements.isPro { PhotosPicker("Choose business logo", selection: $selectedLogo, matching: .images) }
                else { Button("Add a custom logo · Pro") { showingUpgrade = true } }
                TextField("Business name", text: $profile.businessName); TextField("Contractor / owner", text: $profile.ownerName)
                TextField("Email", text: $profile.email).keyboardType(.emailAddress); TextField("Phone", text: $profile.phone).keyboardType(.phonePad)
                TextField("Address", text: $profile.address, axis: .vertical); TextField("Tax / VAT number (optional)", text: $profile.taxNumber)
            }
            Section("Invoice defaults") { CurrencyPickerRow(currencyCode: $profile.currencyCode); TextField("Default Tax / VAT %", text: $profile.taxRate).keyboardType(.decimalPad); TextField("Invoice prefix", text: $profile.invoicePrefix); TextField("Payment instructions", text: $profile.paymentInstructions, axis: .vertical).lineLimit(2...5) }
        }.navigationTitle("Business Details")
            .sheet(isPresented: $showingUpgrade) { NavigationStack { UpgradeView() } }
            .task { await entitlements.refresh() }
            .onChange(of: selectedLogo) { _, item in Task { if entitlements.isPro, let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data), let name = try? PhotoStore.save(image) { profile.logoFilename = name } } }
    }
}
