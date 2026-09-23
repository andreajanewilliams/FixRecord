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
            if let container { RootView().tint(Brand.teal).modelContainer(container) }
            else { ContentUnavailableView("Unable to open local records", systemImage: "externaldrive.badge.exclamationmark", description: Text(storageError ?? "The local database is unavailable. Please try restarting the app.")) }
        }
    }
}

enum Brand {
    static let navy = Color(red: 0.06, green: 0.17, blue: 0.28)
    static let teal = Color(red: 0.03, green: 0.48, blue: 0.43)
    static let pale = Color(red: 0.91, green: 0.97, blue: 0.96)
    static let background = Color(red: 0.97, green: 0.98, blue: 0.99)
}

struct PrimaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).padding(14) }
            .buttonStyle(.plain).foregroundStyle(.white).background(Brand.teal, in: RoundedRectangle(cornerRadius: 13))
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Job.createdAt, order: .reverse) private var jobs: [Job]
    @Query private var profiles: [BusinessProfile]
    @State private var newJob = false
    @State private var selection = 0
    var profile: BusinessProfile? { profiles.first }
    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeView(jobs: jobs, profile: profile, newJob: $newJob) }
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            NavigationStack { ReportsView(jobs: jobs) }
                .tabItem { Label("Reports", systemImage: "doc.text") }.tag(1)
            Text("New Job").tabItem { Label("New Job", systemImage: "plus.circle.fill") }.tag(2)
            NavigationStack { ToolsView(jobs: jobs) }
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }.tag(3)
            NavigationStack { ProfileView(profile: profile) }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(4)
        }
        .onChange(of: selection) { _, value in if value == 2 { selection = 0; newJob = true } }
        .sheet(isPresented: $newJob) { NavigationStack { CreateJobView(profile: profile) } }
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
    let jobs: [Job]
    let profile: BusinessProfile?
    @Binding var newJob: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 9) { Image(systemName: "house.badge.checkmark").font(.title); Text("FixRecord").font(.largeTitle.bold()) }
                        .foregroundStyle(Brand.navy)
                    Text("Proof the work was done.").foregroundStyle(.secondary)
                }
                Text("Good \(Calendar.current.component(.hour, from: .now) < 12 ? "morning" : "day")\(profile?.ownerName.isEmpty == false ? ", \(profile!.ownerName.components(separatedBy: " ").first ?? "")" : "").")
                    .font(.title2.bold()).foregroundStyle(Brand.navy)
                HStack(spacing: 10) {
                    stat("Completed", count: jobs.filter { $0.status == .completed }.count, icon: "checkmark.circle.fill")
                    stat("Drafts", count: jobs.filter { $0.status == .draft }.count, icon: "doc")
                    stat("In Progress", count: jobs.filter { $0.status == .inProgress }.count, icon: "clock")
                }
                PrimaryButton(title: "New Job", icon: "plus") { newJob = true }
                HStack { Text("Recent Jobs").font(.title3.bold()); Spacer(); Text("\(jobs.count) total").foregroundStyle(.secondary) }
                if jobs.isEmpty {
                    ContentUnavailableView("Your work starts here", systemImage: "doc.text.image", description: Text("Create a job or load a sample to explore the full workflow."))
                    Button("Load Sample Job") { context.insert(SampleJob.make()) }.buttonStyle(.bordered)
                } else {
                    ForEach(jobs) { job in
                        NavigationLink { JobDetailView(job: job) } label: { JobRow(job: job) }
                            .buttonStyle(.plain)
                            .contextMenu { Button("Delete job", role: .destructive) { jobToDelete = job } }
                    }
                }
            }.padding()
        }.background(Brand.background).navigationBarTitleDisplayMode(.inline)
            .alert("Delete job?", isPresented: Binding(get: { jobToDelete != nil }, set: { if !$0 { jobToDelete = nil } })) {
                Button("Delete", role: .destructive) { if let job = jobToDelete { for photo in job.photos { PhotoStore.delete(photo.filename) }; for receipt in job.receipts { PhotoStore.delete(receipt.filename) }; context.delete(job) }; jobToDelete = nil }
                Button("Cancel", role: .cancel) { jobToDelete = nil }
            } message: { Text("This removes the local record and its photos.") }
    }
    private func stat(_ title: String, count: Int, icon: String) -> some View {
        VStack(spacing: 7) { Image(systemName: icon).foregroundStyle(Brand.teal); Text("\(count)").font(.title2.bold()); Text(title).font(.caption).multilineTextAlignment(.center) }
            .frame(maxWidth: .infinity).padding(.vertical, 16).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct JobRow: View {
    let job: Job
    var body: some View {
        HStack(spacing: 12) {
            if let filename = job.photos.first?.filename, let image = PhotoStore.image(filename) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: 62, height: 62).clipped().clipShape(RoundedRectangle(cornerRadius: 9))
            } else { Image(systemName: "hammer.fill").frame(width: 62, height: 62).background(Brand.pale, in: RoundedRectangle(cornerRadius: 9)) }
            VStack(alignment: .leading, spacing: 5) { Text(job.title).font(.headline); Text(job.siteAddress).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) { Text(job.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary); Text(job.status.rawValue).font(.caption2.bold()).foregroundStyle(Brand.teal) }
        }.foregroundStyle(Brand.navy).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 13))
    }
}

struct CreateJobView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let profile: BusinessProfile?
    @State private var client = ""
    @State private var address = ""
    @State private var title = ""
    @State private var issue = ""
    @State private var technician = ""
    @State private var business = ""
    @State private var category = "Maintenance"
    @State private var date = Date()
    private let categories = ["Plumbing", "Electrical", "HVAC", "Carpentry", "Painting", "Installation", "Maintenance", "Inspection", "Other"]
    var body: some View {
        Form {
            Section("Customer & site") { TextField("Client / customer name", text: $client); TextField("Site address", text: $address) }
            Section("Work") { TextField("Job title", text: $title); TextField("Issue or work requested", text: $issue, axis: .vertical).lineLimit(3...5); Picker("Category", selection: $category) { ForEach(categories, id: \.self) { Text($0) } }; DatePicker("Date", selection: $date, displayedComponents: .date) }
            Section("Your business") { TextField("Contractor / technician", text: $technician); TextField("Business name", text: $business) }
            Section { PrimaryButton(title: "Create Job", icon: "checkmark") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || client.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.navigationTitle("Create Job").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { technician = profile?.ownerName ?? ""; business = profile?.businessName ?? "" }
    }
    private func save() {
        let prefix = profile?.invoicePrefix.isEmpty == false ? profile!.invoicePrefix : "FR"
        let number = "\(prefix)-\(Int(Date().timeIntervalSince1970))"
        let job = Job(number: number, title: title, clientName: client, siteAddress: address, category: category, issue: issue, technician: technician, businessName: business, currencyCode: profile?.currencyCode ?? "ZAR", taxRate: profile?.taxRate ?? "0")
        job.createdAt = date; context.insert(job); try? context.save(); dismiss()
    }
}

struct JobDetailView: View {
    @Bindable var job: Job
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(job.number).font(.caption.bold()).foregroundStyle(Brand.teal)
                    Text(job.title).font(.largeTitle.bold()).foregroundStyle(Brand.navy)
                    Text(job.clientName + " · " + job.siteAddress).foregroundStyle(.secondary)
                    if job.isSample { Label("Sample data", systemImage: "info.circle").font(.caption).foregroundStyle(Brand.teal) }
                }
                Picker("Status", selection: Binding(get: { job.status }, set: { job.status = $0 })) { ForEach(JobStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                NavigationLink { PhotoCaptureView(job: job, kind: .before) } label: { feature("Before photos", subtitle: "Document the starting condition", icon: "camera") }
                NavigationLink { PhotoCaptureView(job: job, kind: .after) } label: { feature("After photos · MatchShot", subtitle: "Match the angle with a ghost overlay", icon: "square.on.square") }
                NavigationLink { NotesView(job: job) } label: { feature("Job notes", subtitle: "Write clearly with optional AI help", icon: "text.alignleft") }
                NavigationLink { PricingView(job: job) } label: { feature("Materials & pricing", subtitle: "Itemise costs and calculate totals", icon: "list.bullet.rectangle") }
                NavigationLink { ReceiptView(job: job) } label: { feature("Receipt scan", subtitle: "Review on-device OCR before adding items", icon: "doc.viewfinder") }
                NavigationLink { ExportView(job: job) } label: { feature("Report & invoice", subtitle: "Preview and share professional PDFs", icon: "doc.richtext") }
                Toggle("I confirm the work recorded here", isOn: $job.technicianConfirmed).font(.subheadline)
            }.padding()
        }.background(Brand.background).navigationBarTitleDisplayMode(.inline)
    }
    private func feature(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 14) { Image(systemName: icon).font(.title3).foregroundStyle(Brand.teal).frame(width: 28); VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }
            .foregroundStyle(Brand.navy).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 13))
    }
}

struct ReportsView: View {
    let jobs: [Job]
    var body: some View {
        List { ForEach(jobs) { job in NavigationLink { ExportView(job: job) } label: { JobRow(job: job) } } }
            .overlay { if jobs.isEmpty { ContentUnavailableView("No reports yet", systemImage: "doc.text", description: Text("Create a job to prepare a work report and invoice.")) } }
            .navigationTitle("Reports")
    }
}

struct ToolsView: View {
    @Environment(\.modelContext) private var context
    let jobs: [Job]
    var body: some View {
        List {
            Section("Demo") { Button { context.insert(SampleJob.make()) } label: { Label("Load Sample Job", systemImage: "doc.badge.plus") }; Text("Sample records are clearly marked and stay on this device.").font(.caption).foregroundStyle(.secondary) }
            Section("Field tools") { Label("MatchShot ghost overlay", systemImage: "square.on.square"); Label("Receipt text recognition", systemImage: "text.viewfinder"); Label("PDF report and invoice", systemImage: "doc.richtext") }
        }.navigationTitle("Tools")
    }
}

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    let profile: BusinessProfile?
    var body: some View {
        List {
            Section("Business") { if let profile { NavigationLink("Business Profile") { BusinessProfileView(profile: profile) } } else { Button("Set up Business Profile") { context.insert(BusinessProfile()) } } }
            Section("Plan") { NavigationLink("Upgrade / RevenueCat Test Store") { UpgradeView() } }
            Section("About") { Text("FixRecord · Proof the work was done."); Text("Job photos and records are stored on this device. AI sends text facts only when you tap Improve with AI.").font(.caption); Link("Source and AGPL-3.0 licence", destination: URL(string: "https://www.gnu.org/licenses/agpl-3.0.html")!) }
        }.navigationTitle("Profile")
    }
}

struct BusinessProfileView: View {
    @Bindable var profile: BusinessProfile
    @State private var selectedLogo: PhotosPickerItem?
    var body: some View {
        Form {
            Section("Business") { if let logo = PhotoStore.image(profile.logoFilename) { Image(uiImage: logo).resizable().scaledToFit().frame(height: 70) }; PhotosPicker("Choose business logo", selection: $selectedLogo, matching: .images); TextField("Business name", text: $profile.businessName); TextField("Contractor / owner", text: $profile.ownerName); TextField("Email", text: $profile.email).keyboardType(.emailAddress); TextField("Phone", text: $profile.phone).keyboardType(.phonePad); TextField("Address", text: $profile.address, axis: .vertical); TextField("Tax / VAT number", text: $profile.taxNumber) }
            Section("Invoice defaults") { TextField("Currency code (e.g. ZAR)", text: $profile.currencyCode).textInputAutocapitalization(.characters); TextField("Default Tax / VAT %", text: $profile.taxRate).keyboardType(.decimalPad); TextField("Invoice prefix", text: $profile.invoicePrefix); TextField("Payment instructions", text: $profile.paymentInstructions, axis: .vertical).lineLimit(3...6) }
        }.navigationTitle("Business Profile")
            .onChange(of: selectedLogo) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data), let name = try? PhotoStore.save(image) { profile.logoFilename = name } } }
    }
}
