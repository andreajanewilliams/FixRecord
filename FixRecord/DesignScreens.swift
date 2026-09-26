import SwiftUI
import SwiftData
import PhotosUI
import PDFKit
import Observation

enum OnboardingChoice {
    case exampleJob
    case createJob
}

struct OnboardingView: View {
    let finish: (OnboardingChoice) -> Void
    @State private var page = 0
    @State private var reportPreview: UIImage?
    @State private var invoicePreview: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            if page == 0 { welcome }
            else {
                HStack { Spacer(); Button("Skip") { finish(.createJob) }.font(.subheadline).padding() }
                Spacer(minLength: 16)
                if page == 1 { capture }
                else if page == 2 { documents }
                else { exampleJob }
                Spacer(minLength: 20)
                Button(page == 3 ? "Add Example Job" : "Next") {
                    if page == 3 { finish(.exampleJob) } else { page += 1 }
                }
                    .font(.headline).frame(maxWidth: .infinity).padding(15).foregroundStyle(.white)
                    .background(Brand.blue, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 24)
                if page == 3 {
                    Button("Create My Own Job") { finish(.createJob) }
                        .font(.headline).padding(.top, 14)
                }
                dots.padding(.top, 16).padding(.bottom, 24)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(page == 0 ? Brand.navy : .white)
    }

    private var welcome: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = PhotoStore.image("onboarding-workshop-v1") {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        .overlay(LinearGradient(colors: [Brand.navy.opacity(0.12), Brand.navy.opacity(0.28), Brand.navy.opacity(0.52)], startPoint: .top, endPoint: .bottom))
                }
                VStack(spacing: 0) {
                    Spacer(minLength: 35)
                    Image(systemName: "wrench.adjustable.fill").font(.system(size: 42))
                        .frame(width: 82, height: 82).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                    Text("FixRecord").font(.system(size: 37, weight: .bold)).padding(.top, 22)
                    Text("Turn your work into professional reports.").font(.title3).multilineTextAlignment(.center).padding(.top, 9).padding(.horizontal, 24)
                    Spacer(minLength: 30)
                    VStack(alignment: .leading, spacing: 17) {
                        benefit("Capture before & after")
                        benefit("Create reports & invoices")
                        benefit("Share with clients")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 42)
                    Spacer(minLength: 30)
                    Button("Get Started") { page = 1 }.font(.headline).frame(maxWidth: .infinity).padding(15)
                        .background(Brand.blue, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 24)
                    dots.padding(.top, 16).padding(.bottom, 24)
                }.foregroundStyle(.white)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
    }

    private func benefit(_ title: String) -> some View {
        HStack(spacing: 12) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 0.5, green: 0.86, blue: 0.77)); Text(title) }.font(.subheadline)
    }

    private var capture: some View {
        VStack(spacing: 20) {
            Text("Capture your work\nin seconds.").font(.system(size: 30, weight: .bold)).multilineTextAlignment(.center).foregroundStyle(Brand.navy)
            Text("Take before and after photos and keep every job clearly documented.").multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 35)
            HStack(spacing: -8) {
                photo("sample-before-repair-v2", "Before").rotationEffect(.degrees(-7))
                Image(systemName: "camera.viewfinder").font(.system(size: 45)).foregroundStyle(Brand.blue)
                    .frame(width: 105, height: 180).background(.white, in: RoundedRectangle(cornerRadius: 22)).shadow(radius: 12).zIndex(1)
                photo("sample-after-repair-v2", "After").rotationEffect(.degrees(7))
            }.padding(.top, 30)
        }
    }

    private func photo(_ name: String, _ label: String) -> some View {
        VStack(spacing: 5) {
            if let image = PhotoStore.image(name) { Image(uiImage: image).resizable().scaledToFill().frame(width: 100, height: 135).clipped().clipShape(RoundedRectangle(cornerRadius: 10)) }
            Text(label).font(.caption.bold()).foregroundStyle(Brand.navy)
        }.padding(5).background(.white, in: RoundedRectangle(cornerRadius: 13)).shadow(radius: 6)
    }

    private var documents: some View {
        VStack(spacing: 20) {
            Text("Professional documents,\nready to go.").font(.system(size: 30, weight: .bold)).multilineTextAlignment(.center).foregroundStyle(Brand.navy)
            Text("Turn job details into polished reports and invoices you can send to clients in minutes.").multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 35)
            ZStack {
                if let invoicePreview {
                    documentImage(invoicePreview)
                        .rotationEffect(.degrees(7)).offset(x: 52, y: 13)
                }
                if let reportPreview {
                    documentImage(reportPreview)
                        .rotationEffect(.degrees(-7)).offset(x: -52, y: -7)
                        .zIndex(1)
                }
                if reportPreview == nil && invoicePreview == nil { ProgressView().frame(height: 280) }
            }.frame(height: 300).padding(.top, 15)
        }.onAppear(perform: prepareDocumentPreviews)
    }

    private var exampleJob: some View {
        VStack(spacing: 18) {
            Text("Try an example job")
                .font(.system(size: 30, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Brand.navy)
            VStack(alignment: .leading, spacing: 15) {
                Text("Kitchen Sink Repair")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Brand.navy)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 12) {
                    photo("sample-before-repair-v2", "Before")
                    photo("sample-after-repair-v2", "After")
                }.frame(maxWidth: .infinity)
            }
            .padding(20)
            .background(Brand.background, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 24)
        }
    }

    private func documentImage(_ image: UIImage) -> some View {
        Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            .frame(width: 192, height: 272)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.06)))
            .shadow(color: Brand.navy.opacity(0.20), radius: 14, x: 0, y: 8)
    }

    private func prepareDocumentPreviews() {
        guard reportPreview == nil || invoicePreview == nil else { return }
        let sample = SampleJob.make()
        func thumbnail(_ kind: ExportKind) -> UIImage? {
            guard let data = try? PDFMaker.make(kind: kind, job: sample, profile: nil),
                  let page = PDFDocument(data: data)?.page(at: 0) else { return nil }
            return page.thumbnail(of: CGSize(width: 512, height: 725), for: .mediaBox)
        }
        reportPreview = thumbnail(.report)
        invoicePreview = thumbnail(.invoice)
    }

    private var dots: some View {
        HStack(spacing: 7) { ForEach(0..<4) { index in Circle().fill(index == page ? Brand.blue : Color.gray.opacity(0.35)).frame(width: 6, height: 6) } }
    }
}

struct JobEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var job: Job
    @State private var showingCategory = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                JobFormHeading("Job")
                JobFormCard {
                    JobTextField("Job title", placeholder: "e.g. Kitchen Sink Repair", text: $job.title)
                    JobFormDivider()
                    JobTextField("Client name", placeholder: "e.g. Sarah Mitchell", text: $job.clientName)
                    JobFormDivider()
                    JobTextField("Property / Site (optional)", placeholder: "e.g. 12 Oak Avenue", text: $job.siteAddress)
                    JobFormDivider()
                    DatePicker("Date", selection: $job.createdAt, displayedComponents: .date).font(.subheadline).foregroundStyle(Brand.navy)
                }
                JobFormHeading("Work")
                JobFormCard {
                    VoiceTextInput(title: "Reported Issue", placeholder: "What was reported?", text: $job.issue, minEditorHeight: 58)
                    JobFormDivider()
                    JobTextField("Contractor / technician", placeholder: "e.g. Alex Turner", text: $job.technician)
                    JobFormDivider()
                    Button { showingCategory = true } label: {
                        HStack { Text("Category").foregroundStyle(Brand.navy); Spacer(); Text(job.category.isEmpty ? "Select category" : job.category).foregroundStyle(Brand.blue); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.font(.subheadline)
                    }.buttonStyle(.plain)
                }
                JobFormHeading("Client contact")
                JobFormCard {
                    JobTextField("Email", placeholder: "Client email", text: $job.clientEmail)
                    JobFormDivider()
                    JobTextField("Phone", placeholder: "Client phone", text: $job.clientPhone)
                }
            }.padding(18)
        }.background(Brand.background).navigationTitle("Edit Job").toolbar { Button("Done") { dismiss() } }
            .sheet(isPresented: $showingCategory) { CategorySelectionSheet(value: job.category) { job.category = $0 } }
            .onDisappear { job.technicianConfirmed = false }
    }
}

struct PhotoReviewView: View {
    @Bindable var job: Job
    var body: some View {
        ScrollView { VStack(spacing: 18) { photoSection(.before); photoSection(.after) }.padding() }
            .background(Brand.background).navigationTitle("Photos")
    }
    private func photoSection(_ kind: PhotoKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kind == .before ? "Before" : "After").font(.title3.bold()).foregroundStyle(Brand.navy)
            ForEach(job.photos.filter { $0.kind == kind }) { photo in
                PhotoReviewItemView(job: job, photo: photo)
            }
            NavigationLink { PhotoCaptureView(job: job, kind: kind) } label: { Label("Add \(kind == .before ? "Before" : "After") Photo", systemImage: "camera") }.buttonStyle(.bordered)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 15))
    }
}

struct PhotoReviewItemView: View {
    @Bindable var job: Job
    let photo: JobPhoto
    @State private var replacement: PhotosPickerItem?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = PhotoStore.image(photo.filename) {
                Image(uiImage: image).resizable().scaledToFill().frame(height: 200).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                PhotosPicker(selection: $replacement, matching: .images) { Label("Replace", systemImage: "arrow.triangle.2.circlepath") }
                Spacer()
                Button(role: .destructive) { remove() } label: { Label("Delete", systemImage: "trash") }
            }.font(.subheadline)
        }
        .onChange(of: replacement) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data), let filename = try? PhotoStore.save(image) else { return }
                var photos = job.photos
                guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { PhotoStore.delete(filename); return }
                photos[index].filename = filename
                job.photos = photos
                job.technicianConfirmed = false
                PhotoStore.delete(photo.filename)
            }
        }
    }
    private func remove() {
        var photos = job.photos; photos.removeAll { $0.id == photo.id }; job.photos = photos; job.technicianConfirmed = false; PhotoStore.delete(photo.filename)
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var editingProfile: BusinessProfile?
    let profile: BusinessProfile?
    var body: some View {
        List {
            Section {
                if let profile { NavigationLink { BusinessProfileView(profile: profile) } label: { Label("Business Details", systemImage: "building.2") } }
                else { Button { let value = BusinessProfile(); context.insert(value); editingProfile = value } label: { Label("Business Details", systemImage: "building.2") } }
                NavigationLink { JobDefaultsView() } label: { Label("Job Defaults", systemImage: "slider.horizontal.3") }
                NavigationLink { DocumentSettingsView() } label: { Label("Document Settings", systemImage: "slider.horizontal.3") }
                NavigationLink { TemplatesView() } label: { Label("Templates", systemImage: "doc.text") }
                NavigationLink { PresetsView(profile: profile) } label: { Label("Saved Presets", systemImage: "square.on.square") }
                NavigationLink { DataManagementView() } label: { Label("Data Management", systemImage: "externaldrive") }
            }
            Section {
                NavigationLink { AIAccessCodeView() } label: { Label("AI Access Code", systemImage: "key") }
                NavigationLink { UpgradeView() } label: { Label("Upgrade to Pro / Manage Plan", systemImage: "star") }
                NavigationLink { AboutView() } label: { Label("About", systemImage: "info.circle") }
            }
        }.navigationTitle("Settings")
            .sheet(item: $editingProfile) { value in NavigationStack { BusinessProfileView(profile: value) } }
    }
}

struct AIAccessCodeView: View {
    @State private var code = ""
    @State private var saved = false
    @State private var message = ""
    var body: some View {
        Form {
            Section {
                SecureField("Access code", text: $code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save Code") {
                    saved = AIAccessCodeStore.save(code)
                    message = saved ? "Code saved on this device." : "Enter the full access code supplied for the demo."
                    if saved { code = "" }
                }.disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if saved { Button("Remove Code", role: .destructive) { AIAccessCodeStore.remove(); saved = false; message = "Code removed." } }
            } footer: {
                Text("Enter the judging code from the submission notes. Can’t find it? [Email Andrea](mailto:andreajanewilliams2@gmail.com)")
            }
            if !message.isEmpty { Section { Text(message).foregroundStyle(.secondary) } }
        }
        .navigationTitle("AI Access Code")
        .onAppear { saved = AIAccessCodeStore.load() != nil }
    }
}

struct JobDefaultsView: View {
    @State private var defaults = JobDefaultsService.shared
    var body: some View {
        List {
            Section {
                NavigationLink { DefaultTechnicianView() } label: {
                    settingRow("Default Technician", value: defaults.state.defaultTechnician.isEmpty ? "Automatic" : defaults.state.defaultTechnician)
                }
                NavigationLink { DefaultCategoryView() } label: {
                    let category = defaults.category()
                    settingRow("Default Category", value: defaults.state.categoryMode == .lastUsed ? "Last Used" : defaults.state.categoryMode == .none ? "None" : category)
                }
            } footer: { Text("Automatic technician uses Business Details first, then the most recently used name.") }
            Section("Categories") {
                NavigationLink { ManageCustomCategoriesView() } label: { Text("Manage Custom Categories") }
            }
        }.navigationTitle("Job Defaults")
    }
    private func settingRow(_ title: String, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary).lineLimit(1) }
    }
}

struct DefaultTechnicianView: View {
    @State private var defaults = JobDefaultsService.shared
    var body: some View {
        Form {
            Section {
                TextField("None / Automatic", text: $defaults.state.defaultTechnician).textContentType(.name)
                if !defaults.state.defaultTechnician.isEmpty { Button("Use Automatic") { defaults.state.defaultTechnician = "" } }
            } header: { Text("Default Technician") } footer: { Text("This stays fixed until you change it here. Individual jobs remain editable.") }
            if !defaults.state.recentTechnicians.isEmpty {
                Section("Recent") {
                    ForEach(defaults.state.recentTechnicians, id: \.self) { name in
                        Button(name) { defaults.state.defaultTechnician = name }.foregroundStyle(Brand.navy)
                    }
                }
            }
        }.navigationTitle("Default Technician")
    }
}

struct DefaultCategoryView: View {
    @State private var defaults = JobDefaultsService.shared
    var body: some View {
        List {
            Section {
                row("None", selected: defaults.state.categoryMode == .none) { defaults.state.categoryMode = .none }
                row("Last Used", selected: defaults.state.categoryMode == .lastUsed) { defaults.state.categoryMode = .lastUsed }
            }
            Section("Categories") {
                ForEach(JobCategories.builtIn, id: \.self) { name in
                    row(name, selected: defaults.state.categoryMode == .selected && defaults.state.selectedCategory == name) { choose(name) }
                }
            }
            if !defaults.state.customCategories.isEmpty {
                Section("Custom Categories") {
                    ForEach(defaults.state.customCategories, id: \.self) { name in
                        row(name, selected: defaults.state.categoryMode == .selected && defaults.state.selectedCategory == name) { choose(name) }
                    }
                }
            }
        }.navigationTitle("Default Category")
    }
    private func choose(_ name: String) { defaults.state.selectedCategory = name; defaults.state.categoryMode = .selected }
    private func row(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); if selected { Image(systemName: "checkmark").foregroundStyle(Brand.blue) } }
                .foregroundStyle(selected ? Brand.blue : Brand.navy)
        }.buttonStyle(.plain)
    }
}

struct ManageCustomCategoriesView: View {
    @State private var defaults = JobDefaultsService.shared
    @State private var nameToRename = ""
    @State private var proposedName = ""
    @State private var showingRename = false
    @State private var error = ""
    var body: some View {
        List {
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            if defaults.state.customCategories.isEmpty {
                ContentUnavailableView("No custom categories", systemImage: "tag", description: Text("Add one from a job’s category picker."))
            } else {
                ForEach(defaults.state.customCategories, id: \.self) { name in
                    HStack { Text(name); Spacer(); Button("Rename") { nameToRename = name; proposedName = name; showingRename = true }.font(.caption) }
                        .swipeActions { Button("Delete", role: .destructive) { defaults.deleteCustomCategory(name) } }
                }
            }
        }.navigationTitle("Custom Categories")
            .alert("Rename category", isPresented: $showingRename) {
                TextField("Category name", text: $proposedName)
                Button("Save") { if !defaults.renameCustomCategory(nameToRename, to: proposedName) { error = "Choose a unique category name." } }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Older jobs keep the category name they were saved with.") }
    }
}

struct DataManagementView: View {
    @Environment(\.modelContext) private var context
    @Query private var jobs: [Job]
    #if DEBUG
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    #endif
    var body: some View {
        List {
            Section("On this device") { Text("Jobs and photos are stored locally. Export PDFs before removing the app.") }
            Section("Example") { Button("Add Example Job") { if !jobs.contains(where: { $0.isSample }) { context.insert(SampleJob.make()) } }; Text("The example is clearly labelled and can be removed from Jobs.").font(.caption).foregroundStyle(.secondary) }
            #if DEBUG
            Section("Testing") { Button("Replay Onboarding") { didCompleteOnboarding = false } }
            #endif
        }.navigationTitle("Data Management")
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Text("FixRecord"); Text("Capture. Create. Share.")
            Text("Your jobs stay on this device. When you choose Improve with AI, the job text and up to one Before and one After photo are sent for the draft.").font(.subheadline)
            Link("Source licence", destination: URL(string: "https://www.gnu.org/licenses/agpl-3.0.html")!)
        }.navigationTitle("About")
    }
}

enum DocumentTemplate: String, CaseIterable, Codable { case modern = "Modern", minimal = "Minimal", classic = "Classic" }

struct BusinessSnapshot: Codable, Equatable {
    var businessName = ""
    var ownerName = ""
    var email = ""
    var phone = ""
    var address = ""
    var taxNumber = ""
    var paymentInstructions = ""
    var currencyCode = "USD"
    var taxRate = "0"
    var invoicePrefix = "FR"
    var logoFilename = ""

    init(profile: BusinessProfile?) {
        guard let profile else { return }
        businessName = profile.businessName; ownerName = profile.ownerName
        email = profile.email; phone = profile.phone; address = profile.address
        taxNumber = profile.taxNumber; paymentInstructions = profile.paymentInstructions
        currencyCode = profile.currencyCode; taxRate = profile.taxRate
        invoicePrefix = profile.invoicePrefix; logoFilename = profile.logoFilename
    }

    func asProfile() -> BusinessProfile {
        let value = BusinessProfile()
        value.businessName = businessName; value.ownerName = ownerName
        value.email = email; value.phone = phone; value.address = address
        value.taxNumber = taxNumber; value.paymentInstructions = paymentInstructions
        value.currencyCode = currencyCode; value.taxRate = taxRate
        value.invoicePrefix = invoicePrefix; value.logoFilename = logoFilename
        return value
    }
}

enum CurrencyCatalog {
    static let common = ["USD", "EUR", "GBP", "ZAR", "CAD", "AUD", "INR", "JPY"]
    static let codes = Locale.commonISOCurrencyCodes.sorted()

    static func name(for code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? "Custom currency"
    }

    static func matches(_ code: String, query: String) -> Bool {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty || code.localizedStandardContains(search) || name(for: code).localizedStandardContains(search)
    }

    static func customCode(_ input: String) -> String? {
        let code = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return code.range(of: "^[A-Z]{3}$", options: .regularExpression) == nil ? nil : code
    }
}

struct CurrencyPickerRow: View {
    @Binding var currencyCode: String
    @State private var showingCurrencies = false

    var body: some View {
        Button { showingCurrencies = true } label: {
            HStack {
                Text("Currency").foregroundStyle(.primary)
                Spacer()
                Text(currencyCode.isEmpty ? "USD" : currencyCode.uppercased()).foregroundStyle(Brand.blue)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Currency, \(currencyCode). Choose currency")
        .sheet(isPresented: $showingCurrencies) {
            NavigationStack { CurrencySelectionView(currencyCode: $currencyCode) }
        }
    }
}

struct CurrencySelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var currencyCode: String
    @State private var search = ""
    @State private var manualCode = ""

    private var common: [String] { CurrencyCatalog.common.filter { CurrencyCatalog.matches($0, query: search) } }
    private var other: [String] { CurrencyCatalog.codes.filter { !CurrencyCatalog.common.contains($0) && CurrencyCatalog.matches($0, query: search) } }

    var body: some View {
        List {
            Section("Custom code") {
                HStack {
                    TextField("e.g. USD or BTC", text: $manualCode)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button("Use") {
                        if let code = CurrencyCatalog.customCode(manualCode) { select(code) }
                    }.disabled(CurrencyCatalog.customCode(manualCode) == nil)
                }
                Text("Enter a three-letter code if your currency is not listed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !common.isEmpty {
                Section("Common currencies") { ForEach(common, id: \.self) { currencyRow($0) } }
            }
            if !other.isEmpty {
                Section("All currencies") { ForEach(other, id: \.self) { currencyRow($0) } }
            }
            if common.isEmpty && other.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, prompt: "Search currency or code")
        .navigationTitle("Currency").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Done") { dismiss() } }
    }

    private func currencyRow(_ code: String) -> some View {
        Button { select(code) } label: {
            HStack {
                Text(code).font(.subheadline.weight(.semibold)).frame(width: 48, alignment: .leading)
                Text(CurrencyCatalog.name(for: code)).foregroundStyle(.secondary)
                Spacer()
                if currencyCode.caseInsensitiveCompare(code) == .orderedSame {
                    Image(systemName: "checkmark").foregroundStyle(Brand.blue)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func select(_ code: String) {
        currencyCode = code
        dismiss()
    }
}

struct DocumentOptions: Codable, Equatable {
    var template: DocumentTemplate = .modern
    var showLogo = true
    var showBusinessDetails = true
    var showFixRecordBranding = true
    var showReportedIssue = true
    var showMaterials = true
    var showTechnicianConfirmation = true
    var showClientAcknowledgement = false
    var showAdditionalNotes = false
    var showPricesInReport = false
    var showDueDate = true
    var showTax = true
    var showPaymentInstructions = true
    var showTerms = true
    var showDiscount = true

    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "documentOptions"), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save() { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "documentOptions") } }
    func effective(isPro: Bool) -> Self {
        var value = self
        if !isPro { value.template = .modern; value.showLogo = false; value.showFixRecordBranding = true }
        return value
    }
}

struct SavedPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var business: BusinessSnapshot
    var options: DocumentOptions
    var includePhotos: Bool
    var technician = ""
    var category = ""

    static func custom(profile: BusinessProfile?) -> Self {
        Self(name: "Custom", business: BusinessSnapshot(profile: profile), options: .load(),
             includePhotos: UserDefaults.standard.object(forKey: "showPhotosInWorkReport") as? Bool ?? true)
    }
}

@Observable final class PresetStore {
    static let shared = PresetStore()
    private let storage: UserDefaults
    private let storageKey = "fixrecord.savedPresets.v1"
    var presets: [SavedPreset] { didSet { persist() } }
    var defaultID: UUID? { didSet { persist() } }

    private struct Stored: Codable { var presets: [SavedPreset]; var defaultID: UUID? }

    init(storage: UserDefaults = .standard) {
        self.storage = storage
        let saved = storage.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        presets = saved?.presets ?? []
        defaultID = saved?.defaultID
    }

    var defaultPreset: SavedPreset? { presets.first { $0.id == defaultID } }

    func save(_ preset: SavedPreset) {
        let name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var value = preset; value.name = name
        if let index = presets.firstIndex(where: { $0.id == value.id }) { presets[index] = value }
        else { presets.append(value) }
    }

    func delete(_ id: UUID) {
        presets.removeAll { $0.id == id }
        if defaultID == id { defaultID = nil }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(Stored(presets: presets, defaultID: defaultID)) else { return }
        storage.set(data, forKey: storageKey)
    }
}

struct PresetsView: View {
    let profile: BusinessProfile?
    @State private var store = PresetStore.shared
    @State private var editing: SavedPreset?

    var body: some View {
        List {
            Section("New jobs") {
                Picker("Default preset", selection: $store.defaultID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(store.presets) { preset in Text(preset.name).tag(Optional(preset.id)) }
                }
            }
            Section {
                ForEach(store.presets) { preset in
                    Button { editing = preset } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.name).foregroundStyle(Brand.navy)
                                Text(preset.business.businessName.isEmpty ? preset.options.template.rawValue : "\(preset.business.businessName) · \(preset.options.template.rawValue)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.defaultID == preset.id { Text("DEFAULT").font(.caption2.bold()).foregroundStyle(Brand.blue) }
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { store.delete(preset.id) }
                    }
                }
            } header: { Text("Presets") }
              footer: { Text("Swipe to delete. Jobs already using a preset keep their saved settings.") }
            Section {
                Button { var preset = SavedPreset.custom(profile: profile); preset.name = ""; editing = preset } label: {
                    Label("Create Preset", systemImage: "plus.circle.fill")
                }
            }
        }.navigationTitle("Saved Presets")
            .sheet(item: $editing) { preset in NavigationStack { PresetEditorView(preset: preset) { store.save($0) } } }
    }
}

struct PresetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var preset: SavedPreset
    @StateObject private var entitlements = EntitlementService.shared
    @State private var selectedLogo: PhotosPickerItem?
    @State private var showingUpgrade = false
    @State private var loadingLogo = false
    @State private var logoError = ""

    private let editName: Bool
    private let onSave: (SavedPreset) -> Void

    init(preset: SavedPreset, editName: Bool = true, onSave: @escaping (SavedPreset) -> Void) {
        _preset = State(initialValue: preset)
        self.editName = editName
        self.onSave = onSave
    }

    var body: some View {
        Form {
            if editName { Section("Preset name") { TextField("e.g. Standard repair", text: $preset.name) } }
            Section("Business and logo") {
                if let image = PhotoStore.image(preset.business.logoFilename) {
                    Image(uiImage: image).resizable().scaledToFit().frame(height: 64)
                }
                if entitlements.isPro {
                    PhotosPicker("Choose logo", selection: $selectedLogo, matching: .images).disabled(loadingLogo)
                    if !preset.business.logoFilename.isEmpty { Button("Remove logo") { preset.business.logoFilename = "" } }
                } else { Button("Choose logo · Pro") { showingUpgrade = true } }
                if loadingLogo { ProgressView("Loading logo…") }
                if !logoError.isEmpty { Text(logoError).font(.caption).foregroundStyle(.red) }
                TextField("Business name", text: $preset.business.businessName)
                TextField("Owner / contractor", text: $preset.business.ownerName)
                TextField("Email", text: $preset.business.email).keyboardType(.emailAddress)
                TextField("Phone", text: $preset.business.phone).keyboardType(.phonePad)
                TextField("Address", text: $preset.business.address, axis: .vertical)
                TextField("Tax / VAT number", text: $preset.business.taxNumber)
                TextField("Payment instructions", text: $preset.business.paymentInstructions, axis: .vertical)
                CurrencyPickerRow(currencyCode: $preset.business.currencyCode)
                TextField("Tax / VAT %", text: $preset.business.taxRate).keyboardType(.decimalPad)
                TextField("Invoice prefix", text: $preset.business.invoicePrefix)
            }
            if editName {
                Section("Job defaults") {
                    TextField("Technician (optional)", text: $preset.technician)
                    TextField("Category (optional)", text: $preset.category)
                }
            }
            Section("Document layout") {
                Picker("Layout", selection: $preset.options.template) {
                    ForEach(DocumentTemplate.allCases, id: \.self) { layout in Text(layout.rawValue).tag(layout) }
                }.onChange(of: preset.options.template) { _, layout in
                    if !entitlements.isPro && layout != .modern { preset.options.template = .modern; showingUpgrade = true }
                }
                Toggle("Show business logo", isOn: $preset.options.showLogo).disabled(!entitlements.isPro)
                Toggle("Show business details", isOn: $preset.options.showBusinessDetails)
                Toggle("Show FixRecord branding", isOn: $preset.options.showFixRecordBranding).disabled(!entitlements.isPro)
            }
            Section("Work report") {
                Toggle("Show before & after photos", isOn: $preset.includePhotos)
                Toggle("Show reported issue", isOn: $preset.options.showReportedIssue)
                Toggle("Show materials used", isOn: $preset.options.showMaterials)
                Toggle("Show technician confirmation", isOn: $preset.options.showTechnicianConfirmation)
                Toggle("Show client acknowledgement", isOn: $preset.options.showClientAcknowledgement)
                Toggle("Show additional notes", isOn: $preset.options.showAdditionalNotes)
                Toggle("Show prices", isOn: $preset.options.showPricesInReport)
            }
            Section("Invoice") {
                Toggle("Show due date", isOn: $preset.options.showDueDate)
                Toggle("Show Tax / VAT", isOn: $preset.options.showTax)
                Toggle("Show payment instructions", isOn: $preset.options.showPaymentInstructions)
                Toggle("Show terms & notes", isOn: $preset.options.showTerms)
                Toggle("Show discount", isOn: $preset.options.showDiscount)
            }
        }.navigationTitle(editName ? (preset.name.isEmpty ? "New Preset" : "Edit Preset") : "Customise Job")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(preset); dismiss() }
                        .disabled(loadingLogo || (editName && preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
            .sheet(isPresented: $showingUpgrade) { NavigationStack { UpgradeView() } }
            .task { await entitlements.refresh() }
            .onChange(of: selectedLogo) { _, item in
                guard let item else { return }
                loadingLogo = true
                logoError = ""
                Task {
                    defer { loadingLogo = false }
                    do {
                        guard entitlements.isPro,
                              let data = try await item.loadTransferable(type: Data.self),
                              let image = UIImage(data: data) else {
                            logoError = "The selected image could not be loaded. Try another photo."
                            return
                        }
                        preset.business.logoFilename = try PhotoStore.save(image)
                    } catch {
                        logoError = "The selected image could not be saved. Try another photo."
                    }
                }
            }
    }
}

struct TemplatesView: View {
    @State private var options = DocumentOptions.load()
    @StateObject private var entitlements = EntitlementService.shared
    @State private var showingUpgrade = false
    var body: some View {
        List {
            ForEach(DocumentTemplate.allCases, id: \.self) { template in
                Button {
                    if entitlements.isPro || template == .modern { options.template = template; options.save() }
                    else { showingUpgrade = true }
                } label: {
                    HStack(spacing: 15) {
                        Image(systemName: "doc.text.image").font(.title2).frame(width: 48, height: 62).background(Brand.pale, in: RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading) { Text(template.rawValue).font(.headline); Text(template == .modern ? "Clean and professional" : template == .minimal ? "Simple and spacious" : "Traditional layout").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if options.template == template { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.blue) }
                        else if !entitlements.isPro { Text("PRO").font(.caption2.bold()).foregroundStyle(Brand.blue) }
                    }
                }.foregroundStyle(Brand.navy)
            }
        }.navigationTitle("Templates")
            .sheet(isPresented: $showingUpgrade) { NavigationStack { UpgradeView() } }
            .task { await entitlements.refresh() }
    }
}

struct DocumentSettingsView: View {
    @State private var options = DocumentOptions.load()
    @AppStorage("showPhotosInWorkReport") private var showPhotosInWorkReport = true
    @StateObject private var entitlements = EntitlementService.shared
    @State private var showingUpgrade = false
    var body: some View {
        Form {
            Section("Branding") {
                proToggle("Show business logo", value: $options.showLogo)
                Toggle("Show business details", isOn: $options.showBusinessDetails)
                proToggle("Show FixRecord branding", value: $options.showFixRecordBranding, reversedGate: true)
            }
            Section("Work Report") {
                Toggle("Show before & after photos", isOn: $showPhotosInWorkReport)
                Toggle("Show reported issue", isOn: $options.showReportedIssue)
                Toggle("Show materials used", isOn: $options.showMaterials)
                Toggle("Show technician confirmation", isOn: $options.showTechnicianConfirmation)
                Toggle("Show client acknowledgement", isOn: $options.showClientAcknowledgement)
                Toggle("Show additional notes", isOn: $options.showAdditionalNotes)
                Toggle("Show prices", isOn: $options.showPricesInReport)
            }
            Section("Invoice") {
                Toggle("Show due date", isOn: $options.showDueDate)
                Toggle("Show Tax / VAT", isOn: $options.showTax)
                Toggle("Show payment instructions", isOn: $options.showPaymentInstructions)
                Toggle("Show terms & notes", isOn: $options.showTerms)
                Toggle("Show discount", isOn: $options.showDiscount)
            }
        }.navigationTitle("Document Settings")
            .onChange(of: options) { _, value in value.save() }
            .sheet(isPresented: $showingUpgrade) { NavigationStack { UpgradeView() } }
            .task { await entitlements.refresh() }
    }
    private func proToggle(_ title: String, value: Binding<Bool>, reversedGate: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            if !entitlements.isPro { Text("PRO").font(.caption2.bold()).foregroundStyle(Brand.blue) }
            Toggle(title, isOn: Binding(get: { !entitlements.isPro && reversedGate ? true : !entitlements.isPro ? false : value.wrappedValue }, set: { newValue in if entitlements.isPro { value.wrappedValue = newValue } else { showingUpgrade = true } })).labelsHidden()
        }
    }
}
