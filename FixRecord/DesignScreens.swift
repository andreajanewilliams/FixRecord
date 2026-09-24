import SwiftUI
import SwiftData
import PhotosUI
import PDFKit

struct OnboardingView: View {
    let finish: () -> Void
    @State private var page = 0
    @State private var reportPreview: UIImage?
    @State private var invoicePreview: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            if page == 0 { welcome }
            else {
                HStack { Spacer(); Button("Skip") { finish() }.font(.subheadline).padding() }
                Spacer(minLength: 16)
                if page == 1 { capture } else { documents }
                Spacer(minLength: 20)
                Button(page == 1 ? "Next" : "Create First Job") { if page == 1 { page = 2 } else { finish() } }
                    .font(.headline).frame(maxWidth: .infinity).padding(15).foregroundStyle(.white)
                    .background(Brand.blue, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 24)
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
        HStack(spacing: 7) { ForEach(0..<3) { index in Circle().fill(index == page ? Brand.blue : Color.gray.opacity(0.35)).frame(width: 6, height: 6) } }
    }
}

struct JobEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var job: Job
    var body: some View {
        Form {
            Section("Job") { TextField("Job title", text: $job.title); TextField("Client name", text: $job.clientName); TextField("Property / Site", text: $job.siteAddress); DatePicker("Date", selection: $job.createdAt, displayedComponents: .date) }
            Section("Work") { VoiceTextInput(title: "Reported Issue", placeholder: "What was reported?", text: $job.issue); TextField("Contractor / technician", text: $job.technician); TextField("Category", text: $job.category) }
            Section("Client contact") { TextField("Email", text: $job.clientEmail).keyboardType(.emailAddress); TextField("Phone", text: $job.clientPhone).keyboardType(.phonePad) }
        }.navigationTitle("Edit Job").toolbar { Button("Done") { dismiss() } }
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
                NavigationLink { DocumentSettingsView() } label: { Label("Document Settings", systemImage: "slider.horizontal.3") }
                NavigationLink { TemplatesView() } label: { Label("Templates", systemImage: "doc.text") }
                NavigationLink { DataManagementView() } label: { Label("Data Management", systemImage: "externaldrive") }
            }
            Section {
                NavigationLink { UpgradeView() } label: { Label("Upgrade to Pro / Manage Plan", systemImage: "star") }
                NavigationLink { AboutView() } label: { Label("About", systemImage: "info.circle") }
            }
        }.navigationTitle("Settings")
            .sheet(item: $editingProfile) { value in NavigationStack { BusinessProfileView(profile: value) } }
    }
}

struct DataManagementView: View {
    @Environment(\.modelContext) private var context
    @Query private var jobs: [Job]
    var body: some View {
        List {
            Section("On this device") { Text("Jobs and photos are stored locally. Export PDFs before removing the app.") }
            Section("Demo") { Button("Load Sample Job") { if !jobs.contains(where: { $0.isSample }) { context.insert(SampleJob.make()) } }; Text("The sample is clearly labelled and can be removed from Jobs.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Data Management")
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Text("FixRecord"); Text("Capture. Create. Share.")
            Text("Your jobs and photos stay on this device. AI receives text facts only when you choose Improve with AI.").font(.subheadline)
            Link("Source licence", destination: URL(string: "https://www.gnu.org/licenses/agpl-3.0.html")!)
        }.navigationTitle("About")
    }
}

enum DocumentTemplate: String, CaseIterable, Codable { case modern = "Modern", minimal = "Minimal", classic = "Classic" }

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
