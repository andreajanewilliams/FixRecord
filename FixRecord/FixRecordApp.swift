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
    @State private var selection = 0
    var profile: BusinessProfile? { profiles.first }
    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView(jobs: jobs, newJob: $newJob, selectedJob: $selectedJob, selection: $selection)
                    .navigationDestination(item: $selectedJob) { JobDetailView(job: $0) }
            }.tabItem { Label("Jobs", systemImage: "house.fill") }.tag(0)
            NavigationStack { TemplatesView() }.tabItem { Label("Templates", systemImage: "doc.text") }.tag(1)
            NavigationStack { SettingsView(profile: profile) }.tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
        }
        .sheet(isPresented: $newJob) { NavigationStack { CreateJobView(profile: profile) { job in selectedJob = job } } }
        .fullScreenCover(isPresented: Binding(get: { !didCompleteOnboarding && !ProcessInfo.processInfo.arguments.contains("-skip-onboarding") }, set: { if !$0 { didCompleteOnboarding = true } })) {
            OnboardingView {
                didCompleteOnboarding = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { newJob = true }
            }
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
    @State private var filter: JobFilter = .all
    let jobs: [Job]
    @Binding var newJob: Bool
    @Binding var selectedJob: Job?
    @Binding var selection: Int
    private var visibleJobs: [Job] { jobs.filter { filter == .all || $0.status == filter.status } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 9) {
                    Image(systemName: "wrench.adjustable.fill").foregroundStyle(.white).padding(8).background(Brand.navy, in: RoundedRectangle(cornerRadius: 9))
                    Text("FixRecord").font(.headline).foregroundStyle(Brand.navy)
                    Spacer()
                    Button { selection = 2 } label: { Image(systemName: "gearshape").foregroundStyle(Brand.navy) }.accessibilityLabel("Settings")
                }
                HStack {
                    Text("My Jobs").font(.largeTitle.bold()).foregroundStyle(Brand.navy)
                    Spacer()
                    Button { newJob = true } label: { Label("New Job", systemImage: "plus").font(.subheadline.bold()) }.buttonStyle(.borderedProminent)
                }
                Picker("Jobs", selection: $filter) { ForEach(JobFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                if visibleJobs.isEmpty {
                    ContentUnavailableView(jobs.isEmpty ? "No jobs yet" : "No jobs here", systemImage: "doc.text.image", description: Text(jobs.isEmpty ? "Create a job or explore a sample." : "Try another filter."))
                    if jobs.isEmpty { Button("Load Sample Job") { context.insert(SampleJob.make()) }.buttonStyle(.bordered) }
                } else {
                    LazyVStack(spacing: 8) { ForEach(visibleJobs) { job in
                        Button { selectedJob = job } label: { JobRow(job: job) }.buttonStyle(.plain)
                            .contextMenu { Button("Delete job", role: .destructive) { jobToDelete = job } }
                    } }
                }
            }.padding(18)
        }.background(Brand.background).toolbar(.hidden, for: .navigationBar)
            .alert("Delete job?", isPresented: Binding(get: { jobToDelete != nil }, set: { if !$0 { jobToDelete = nil } })) {
                Button("Delete", role: .destructive) { if let job = jobToDelete { for photo in job.photos { PhotoStore.delete(photo.filename) }; for receipt in job.receipts { PhotoStore.delete(receipt.filename) }; context.delete(job) }; jobToDelete = nil }
                Button("Cancel", role: .cancel) { jobToDelete = nil }
            } message: { Text("This removes the local record and its photos.") }
    }
}

enum JobFilter: String, CaseIterable {
    case all = "All", inProgress = "In Progress", completed = "Completed"
    var status: JobStatus? { switch self { case .all: nil; case .inProgress: .inProgress; case .completed: .completed } }
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
    let profile: BusinessProfile?
    let onCreate: (Job) -> Void
    @State private var client = ""
    @State private var address = ""
    @State private var title = ""
    @State private var issue = ""
    @State private var technician = ""
    @State private var category = "Maintenance"
    @State private var date = Date()
    private let categories = ["Plumbing", "Electrical", "HVAC", "Carpentry", "Painting", "Installation", "Maintenance", "Inspection", "Other"]
    var body: some View {
        Form {
            Section("Job") { TextField("Job title", text: $title); TextField("Client name", text: $client); TextField("Property / Site (optional)", text: $address); DatePicker("Date", selection: $date, displayedComponents: .date) }
            Section("Work") { VoiceTextInput(title: "Reported Issue", placeholder: "What was reported?", text: $issue); TextField("Contractor / technician", text: $technician); Picker("Category", selection: $category) { ForEach(categories, id: \.self) { Text($0) } } }
            Section { PrimaryButton(title: "Save Job", icon: "checkmark") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.navigationTitle("New Job").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { technician = profile?.ownerName ?? "" }
    }
    private func save() {
        let prefix = profile?.invoicePrefix.isEmpty == false ? profile!.invoicePrefix : "FR"
        let number = "\(prefix)-\(Int(Date().timeIntervalSince1970))"
        let job = Job(number: number, title: title, clientName: client, siteAddress: address, category: category, issue: issue, technician: technician, businessName: profile?.businessName ?? "", currencyCode: profile?.currencyCode ?? "ZAR", taxRate: profile?.taxRate ?? "0")
        job.createdAt = date; context.insert(job); try? context.save(); dismiss(); onCreate(job)
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
                    if job.isSample { Label("SAMPLE DATA", systemImage: "info.circle.fill").font(.caption.bold()).foregroundStyle(Brand.blue) }
                }
                Picker("Status", selection: Binding(get: { job.status }, set: { job.status = $0 })) { ForEach(JobStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                NavigationLink { PhotoCaptureView(job: job, kind: .before) } label: { feature("Capture Before", subtitle: "Optional photo of the starting condition", icon: "camera") }
                NavigationLink { PhotoCaptureView(job: job, kind: .after) } label: { feature("Capture After · MatchShot", subtitle: "Optional photo of the finished work", icon: "square.on.square") }
                NavigationLink { PhotoReviewView(job: job) } label: { feature("Photos", subtitle: "Review before and after", icon: "photo.on.rectangle.angled") }
                NavigationLink { NotesView(job: job) } label: { feature("Work Details", subtitle: "Issue and work completed", icon: "text.alignleft") }
                NavigationLink { PricingView(job: job) } label: { feature("Materials & Pricing", subtitle: "Add items when you need an invoice", icon: "list.bullet.rectangle") }
                NavigationLink { ReceiptView(job: job) } label: { feature("Scan Receipt", subtitle: "Review suggestions before adding", icon: "doc.viewfinder") }
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
            Section("Invoice defaults") { TextField("Currency code", text: $profile.currencyCode).textInputAutocapitalization(.characters); TextField("Default Tax / VAT %", text: $profile.taxRate).keyboardType(.decimalPad); TextField("Invoice prefix", text: $profile.invoicePrefix); TextField("Payment instructions", text: $profile.paymentInstructions, axis: .vertical).lineLimit(2...5) }
        }.navigationTitle("Business Details")
            .sheet(isPresented: $showingUpgrade) { NavigationStack { UpgradeView() } }
            .task { await entitlements.refresh() }
            .onChange(of: selectedLogo) { _, item in Task { if entitlements.isPro, let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data), let name = try? PhotoStore.save(image) { profile.logoFilename = name } } }
    }
}
