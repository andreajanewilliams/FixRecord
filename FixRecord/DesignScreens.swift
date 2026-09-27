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
    private struct Details: Equatable {
        let number, title, clientName, siteAddress, issue, technician, category, clientEmail, clientPhone: String
        let createdAt: Date
        init(_ job: Job) {
            number = job.number; title = job.title; clientName = job.clientName; siteAddress = job.siteAddress
            issue = job.issue; technician = job.technician; category = job.category
            clientEmail = job.clientEmail; clientPhone = job.clientPhone; createdAt = job.createdAt
        }
    }
    @Environment(\.dismiss) private var dismiss
    @Bindable var job: Job
    @Query private var jobs: [Job]
    @State private var reference = ""
    private var referenceError: String? { JobReference.validation(reference, existing: jobs.filter { $0.id != job.id }.map(\.number)) }
    private func saveReference() { if referenceError == nil { job.number = reference.trimmingCharacters(in: .whitespacesAndNewlines) } }
    @State private var showingCategory = false
    @State private var initialDetails: Details?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                JobFormHeading("Job")
                JobFormCard {
                    JobTextField("Job reference", placeholder: "e.g. JOB-001", text: $reference)
                    if let referenceError { Text(referenceError).font(.caption).foregroundStyle(.red) }
                    JobFormDivider()
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
        }.background(Brand.background).navigationTitle("Edit Job").toolbar { Button("Done") { saveReference(); dismiss() }.disabled(referenceError != nil) }
            .sheet(isPresented: $showingCategory) { CategorySelectionSheet(value: job.category) { job.category = $0 } }
            .onAppear { if initialDetails == nil { initialDetails = Details(job); reference = job.number } }
            .onDisappear { saveReference(); if let initialDetails, initialDetails != Details(job) { job.technicianConfirmed = false } }
    }
}

struct PhotoReviewView: View {
    @Bindable var job: Job
    var body: some View {
        ScrollView { VStack(spacing: 18) { photoSection(.before); photoSection(.after) }.padding() }
            .background(Brand.background).navigationTitle("Photos")
    }
    private func photoSection(_ kind: PhotoKind) -> some View {
        JobPhotoSection(job: job, kind: kind)
    }
}

private struct JobPhotoSection: View {
    @Bindable var job: Job
    let kind: PhotoKind
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingAddOptions = false
    @State private var importing = false
    @State private var importError: String?
    @State private var selectedBeforeID: UUID?
    @State private var initialisedMatch = false
    private var photos: [JobPhoto] { job.photos.filter { $0.kind == kind } }
    private var beforePhotos: [JobPhoto] { job.photos.filter { $0.kind == .before } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(kind == .before ? "Before" : "After").font(.title3.bold()).foregroundStyle(Brand.navy)
                Spacer()
                if !photos.isEmpty {
                    Button { showingAddOptions.toggle() } label: {
                        Image(systemName: showingAddOptions ? "minus.circle.fill" : "plus.circle.fill")
                            .font(.title2).frame(width: 44, height: 44)
                    }.accessibilityLabel(showingAddOptions ? "Hide photo options" : "Add more \(kind.rawValue) photos")
                }
            }
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                VStack(alignment: .leading, spacing: 6) {
                    if photos.count > 1 {
                        Text("\(kind == .before ? "Before" : "After") \(index + 1)")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    PhotoReviewItemView(job: job, photo: photo)
                }
            }
            if photos.isEmpty || showingAddOptions {
                if kind == .after && !beforePhotos.isEmpty {
                    Picker("Match to", selection: $selectedBeforeID) {
                        Text("No matching Before").tag(nil as UUID?)
                        ForEach(Array(beforePhotos.enumerated()), id: \.element.id) { index, photo in
                            Text("Before \(index + 1)").tag(Optional(photo.id))
                        }
                    }.pickerStyle(.menu).font(.subheadline)
                    Text("Choose which before photo this after photo matches.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    NavigationLink {
                        PhotoCaptureView(job: job, kind: kind, initialBeforeID: selectedBeforeID)
                    } label: {
                        Label("Camera", systemImage: "camera").frame(maxWidth: .infinity, minHeight: 32)
                    }
                    PhotosPicker(selection: $selectedItems, selectionBehavior: .ordered, matching: .images) {
                        Label("Upload", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity, minHeight: 32)
                    }
                }.buttonStyle(.bordered).disabled(importing)
            }
            if importing { ProgressView("Adding photos…").font(.caption) }
            if let importError { Text(importError).font(.caption).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 15))
        .onAppear {
            if !initialisedMatch { selectedBeforeID = beforePhotos.first?.id; initialisedMatch = true }
        }
        .onChange(of: beforePhotos.map(\.id)) { oldIDs, newIDs in
            if oldIDs.isEmpty { selectedBeforeID = newIDs.first }
            else if let selectedBeforeID, !newIDs.contains(selectedBeforeID) { self.selectedBeforeID = nil }
        }
        .onChange(of: photos.count) { oldCount, newCount in
            if newCount > oldCount { showingAddOptions = false }
        }
        .onChange(of: selectedItems) { _, items in
            guard !items.isEmpty, !importing else { return }
            importing = true
            let matchedBeforeID = kind == .after ? selectedBeforeID : nil
            Task { await importPhotos(items, matchedBeforeID: matchedBeforeID) }
        }
    }

    @MainActor private func importPhotos(_ items: [PhotosPickerItem], matchedBeforeID: UUID?) async {
        importError = nil
        var failed = 0
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    failed += 1; continue
                }
                let filename = try PhotoStore.save(image)
                // Only pair with a Before photo that still exists after the import.
                let match = beforePhotos.contains(where: { $0.id == matchedBeforeID }) ? matchedBeforeID : nil
                var updated = job.photos
                updated.append(JobPhoto(kind: kind, filename: filename, pairedBeforeID: match))
                job.photos = updated
                job.technicianConfirmed = false
            } catch { failed += 1 }
        }
        if failed > 0 { importError = "\(failed) photo\(failed == 1 ? "" : "s") could not be added. Please try again." }
        selectedItems = []
        importing = false
    }
}

struct PhotoReviewItemView: View {
    @Bindable var job: Job
    let photo: JobPhoto
    @State private var replacement: PhotosPickerItem?
    @State private var qualityWarning: String?
    @State private var alignmentGuidance: String?
    private var matchedBefore: JobPhoto? {
        job.photos.first { $0.kind == .before && $0.id == photo.pairedBeforeID }
    }
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
            Toggle("Include in report", isOn: Binding(
                get: { job.photos.first(where: { $0.id == photo.id })?.includeInReport ?? true },
                set: { included in
                    var photos = job.photos
                    guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
                    photos[index].includeInReport = included
                    job.photos = photos
                    job.technicianConfirmed = false
                }
            )).font(.subheadline).tint(Brand.blue)
            if photo.kind == .after, let index = job.photos.filter({ $0.kind == .before }).firstIndex(where: { $0.id == photo.pairedBeforeID }) {
                Text("Matched to Before \(index + 1)").font(.caption).foregroundStyle(.secondary)
            }
            if let alignmentGuidance {
                Label(alignmentGuidance, systemImage: "viewfinder").font(.caption).foregroundStyle(Brand.teal)
            }
            if let qualityWarning {
                Label(qualityWarning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .task(id: photo.filename + "|" + (matchedBefore?.filename ?? "")) {
            qualityWarning = PhotoStore.image(photo.filename).flatMap { ImageQuality.warning(for: $0) }
            alignmentGuidance = nil
            if photo.kind == .after,
               let before = matchedBefore,
               let original = PhotoStore.image(before.filename), let image = PhotoStore.image(photo.filename) {
                let result = MatchShotBridge.compare(before: original, after: image)
                alignmentGuidance = result.wellAligned ? nil : result.guidance
            }
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
    @StateObject private var entitlements = EntitlementService.shared
    @Environment(\.modelContext) private var context
    @State private var editingProfile: BusinessProfile?
    let profile: BusinessProfile?
    var body: some View {
        List {
            Section {
                NavigationLink { UpgradeView() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "star.fill")
                            .font(.title3).foregroundStyle(Brand.blue)
                            .frame(width: 44, height: 44)
                            .background(Brand.pale, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FixRecord Pro").font(.headline).foregroundStyle(Brand.navy)
                            Text(entitlements.isPro ? "Manage subscription" : "View plans")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if entitlements.isPro {
                            Text("Active").font(.caption.weight(.semibold)).foregroundStyle(Brand.teal)
                        }
                    }.padding(.vertical, 4)
                }
            }
            Section {
                if let profile { NavigationLink { BusinessProfileView(profile: profile) } label: { Label("Business Details", systemImage: "building.2") } }
                else { Button { let value = BusinessProfile(); context.insert(value); editingProfile = value } label: { Label("Business Details", systemImage: "building.2") } }
                NavigationLink { JobDefaultsView() } label: { Label("Job Defaults", systemImage: "slider.horizontal.3") }
                NavigationLink { DocumentSettingsView() } label: { Label("Document Settings", systemImage: "slider.horizontal.3") }
                NavigationLink { PresetsView(profile: profile) } label: { Label("Saved Presets", systemImage: "square.on.square") }
                NavigationLink { DataManagementView() } label: { Label("Data Management", systemImage: "externaldrive") }
            }
            Section {
                NavigationLink { AboutView() } label: { Label("About", systemImage: "info.circle") }
            }
        }.navigationTitle("Settings")
            .task { await entitlements.refresh() }
            .sheet(item: $editingProfile) { value in NavigationStack { BusinessProfileView(profile: value) } }
    }
}

struct AIAccessCodeView: View {
    var onSaved: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    @State private var code = ""
    @State private var saved = false
    @State private var message = ""
    @State private var messageIsError = false
    @State private var checking = false
    @State private var checkTask: Task<Void, Never>?
    @State private var checkID = UUID()
    var body: some View {
        Form {
            Section {
                if message.isEmpty && !saved {
                    Text("Enter your judging code to use Improve with AI.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                SecureField("Access code", text: $code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(checking)
                if saved { Button("Remove Code", role: .destructive) { cancelCheck(); AIAccessCodeStore.remove(); saved = false; messageIsError = false; message = "Code removed." } }
            } footer: {
                Text("Enter the judging code from the submission notes. Can’t find it? [Email Andrea](mailto:andreajanewilliams2@gmail.com)")
            }
            if !message.isEmpty {
                Section {
                    if messageIsError { errorNotice(message) }
                    else { Text(message).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("AI Access Code")
        .toolbar {
            if let onCancel {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { cancelCheck(); onCancel() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                checkTask = Task { await saveCode() }
            } label: {
                Label(checking ? "Checking code…" : "Save code", systemImage: checking ? "hourglass" : "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Brand.blue, in: RoundedRectangle(cornerRadius: 13))
            .disabled(checking || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Brand.background)
        }
        .onAppear {
            saved = AIAccessCodeStore.load() != nil
        }
        .onDisappear { cancelCheck() }
    }
    private func errorNotice(_ text: String) -> some View {
        Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        }
        .font(.subheadline)
    }
    private func cancelCheck() {
        checkID = UUID()
        checkTask?.cancel()
        checkTask = nil
        checking = false
    }
    private func saveCode() async {
        let candidate = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (20...128).contains(candidate.count) else {
            messageIsError = true
            message = "Incorrect code. Please enter the code from the submission notes."
            code = ""
            return
        }
        let currentCheckID = UUID()
        checkID = currentCheckID
        checking = true
        defer { checking = false }
        do {
            try await AIService.validateAccessCode(candidate)
            guard checkID == currentCheckID, !Task.isCancelled else { return }
            guard AIAccessCodeStore.save(candidate) else {
                messageIsError = true
                message = "Could not save the code. Please try again."
                return
            }
            saved = true
            code = ""
            messageIsError = false
            message = "Code ready for AI."
            onSaved?()
        } catch AIService.Failure.accessCodeRequired {
            guard checkID == currentCheckID, !Task.isCancelled else { return }
            messageIsError = true
            message = "Incorrect code. Please enter the code from the submission notes."
            code = ""
        } catch {
            guard checkID == currentCheckID, !Task.isCancelled else { return }
            messageIsError = true
            message = "Could not check the code right now. Please try again."
        }
    }
}

struct JobDefaultsView: View {
    @AppStorage("defaultJobReferencePrefix") private var referencePrefix = ""
    @Query private var profiles: [BusinessProfile]
    @AppStorage("defaultCurrencyCode") private var defaultCurrencyCode = ""
    @State private var defaults = JobDefaultsService.shared
    var body: some View {
        List {
            Section {
                NavigationLink { DefaultTechnicianView() } label: {
                    settingRow("Technician", value: defaults.state.defaultTechnician.isEmpty ? "Automatic" : defaults.state.defaultTechnician)
                }
                NavigationLink { DefaultCategoryView() } label: {
                    let category = defaults.category()
                    settingRow("Category", value: defaults.state.categoryMode == .lastUsed ? "Last Used" : defaults.state.categoryMode == .none ? "None" : category)
                }
            }
            Section {
                TextField("Prefix (e.g. FR or JOB)", text: $referencePrefix)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                Text("Example: \(JobReference.automatic(prefix: referencePrefix.isEmpty ? (profiles.first?.invoicePrefix ?? "FR") : referencePrefix, existing: []))")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Job references") }
            Section("Categories") {
                NavigationLink { ManageCustomCategoriesView() } label: { Text("Custom Categories") }
            }
            Section {
                CurrencyPickerRow(currencyCode: Binding(
                    get: { defaultCurrencyCode.isEmpty ? "USD" : defaultCurrencyCode },
                    set: { defaultCurrencyCode = $0 }
                ), title: "Currency")
            } footer: { Text("For new jobs. Presets can override these settings.") }
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
            } header: { Text("Default Technician") } footer: { Text(defaults.state.defaultTechnician.isEmpty ? "Uses the name in Business Details, or your last used name." : "Used for new jobs.") }
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
    var body: some View {
        List {
            Section("On this device") { Text("Jobs and photos are stored locally. Export PDFs before removing the app.") }
        }.navigationTitle("Data Management")
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Text("FixRecord"); Text("Capture. Create. Share.")
            Text("Your jobs stay on this device. When you choose Improve with AI, the job text and up to one Before and one After photo are sent for the draft.").font(.subheadline)
            Link("Source license", destination: URL(string: "https://www.gnu.org/licenses/agpl-3.0.html")!)
        }.navigationTitle("About")
    }
}

enum DocumentTemplate: String, CaseIterable, Codable {
    case modern = "Modern", minimal = "Minimal", classic = "Classic", studio = "Studio", blueprint = "Blueprint"
    case executive = "Executive", editorial = "Editorial", precision = "Precision", copper = "Copper", horizon = "Horizon"

    var displayName: String { self == .copper ? "Folio" : rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        // Preserve saved jobs and presets that used the retired Sage design.
        if value == "Sage" { self = .executive; return }
        guard let template = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown document template")
        }
        self = template
    }
}

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
    var title = "Currency"
    @State private var showingCurrencies = false

    var body: some View {
        Button { showingCurrencies = true } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(currencyCode.isEmpty ? "USD" : currencyCode.uppercased()).foregroundStyle(Brand.blue)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("\(title), \(currencyCode). Choose currency")
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
    // Optional so existing jobs and presets retain their saved settings.
    var brandColourHex: String?
    var templateColours: [String: String]?
    func colour(for layout: DocumentTemplate) -> String? {
        templateColours?[layout.rawValue] ?? brandColourHex
    }
    mutating func setColour(_ hex: String?, for layout: DocumentTemplate) {
        var colors = templateColours ?? [:]
        colors[layout.rawValue] = hex ?? DocumentColour.defaultHex
        templateColours = colors
    }
    mutating func setColourForAll(_ hex: String?) {
        brandColourHex = hex
        templateColours = nil
    }
    var selectedColour: String? {
        get { colour(for: template) }
        set { setColour(newValue, for: template) }
    }

    var logoSizePercent: Double?
    var logoSize: Double {
        get {
            guard let value = logoSizePercent, value.isFinite else { return 100 }
            return min(200, max(50, value))
        }
        set { logoSizePercent = newValue.isFinite ? min(200, max(50, newValue)) : 100 }
    }
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
    // Older presets keep labels visible when this setting is absent.
    var hidePhotoLabels: Bool?
    var showPhotoLabels: Bool {
        get { hidePhotoLabels != true }
        set { hidePhotoLabels = !newValue }
    }

    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "documentOptions"), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save() { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "documentOptions") } }
    func effective(isPro: Bool) -> Self {
        var value = self
        value.showFixRecordBranding = !isPro
        if !isPro { value.template = .modern; value.brandColourHex = nil; value.templateColours = nil; value.showLogo = false }
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
    @AppStorage("defaultCurrencyCode") private var defaultCurrencyCode = ""
    @State private var store = PresetStore.shared
    @StateObject private var entitlements = EntitlementService.shared
    @State private var editing: SavedPreset?
    @State private var presetToDelete: SavedPreset?

    var body: some View {
        List {
            Section {
                Picker("Default preset", selection: $store.defaultID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(store.presets) { preset in Text(preset.name).tag(Optional(preset.id)) }
                }
            } header: { Text("New jobs") }
              footer: { Text("Reuse business details and document settings.") }
            Section {
                ForEach(store.presets) { preset in
                    HStack(spacing: 8) {
                        Button { editing = preset } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preset.name).foregroundStyle(Brand.navy)
                                    Text(preset.business.businessName.isEmpty ? layoutDescription(for: preset) : "\(preset.business.businessName) · \(layoutDescription(for: preset))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.defaultID == preset.id { Text("DEFAULT").font(.caption2.bold()).foregroundStyle(Brand.blue) }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Button(role: .destructive) { presetToDelete = preset } label: {
                            Image(systemName: "trash").frame(width: 44, height: 44)
                        }.buttonStyle(.borderless).accessibilityLabel("Delete \(preset.name)")
                    }
                }
            } header: { Text("Presets") }
              footer: { Text("Existing jobs stay unchanged.") }
            Section {
                Button {
                    var preset = SavedPreset.custom(profile: profile)
                    preset.name = ""
                    preset.business.currencyCode = defaultCurrencyCode.isEmpty ? "USD" : defaultCurrencyCode
                    editing = preset
                } label: {
                    Label("Create Preset", systemImage: "plus.circle.fill")
                }
            }
        }.navigationTitle("Saved Presets")
            .sheet(item: $editing) { preset in NavigationStack { PresetEditorView(preset: preset) { store.save($0) } } }
            .alert("Delete preset?", isPresented: Binding(get: { presetToDelete != nil }, set: { if !$0 { presetToDelete = nil } }), presenting: presetToDelete) { preset in
                Button("Delete", role: .destructive) { store.delete(preset.id); presetToDelete = nil }
                Button("Cancel", role: .cancel) { presetToDelete = nil }
            } message: { preset in
                Text("Delete \"\(preset.name)\"? Existing jobs keep their saved settings.")
            }
            .task { await entitlements.refresh() }
    }

    private func layoutDescription(for preset: SavedPreset) -> String {
        if !entitlements.isPro && preset.options.template != .modern { return "Modern on Free" }
        return preset.options.template.displayName
    }
}

struct PresetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var preset: SavedPreset
    @State private var defaults = JobDefaultsService.shared
    @StateObject private var entitlements = EntitlementService.shared
    @State private var selectedLogo: PhotosPickerItem?
    @State private var showingUpgrade = false
    @State private var showingCategory = false
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
            Section {
                TextField("Business name", text: $preset.business.businessName)
                TextField("Owner / contractor", text: $preset.business.ownerName)
                TextField("Email", text: $preset.business.email).keyboardType(.emailAddress)
                TextField("Phone", text: $preset.business.phone).keyboardType(.phonePad)
                TextField("Address", text: $preset.business.address, axis: .vertical)
                TextField("Tax / VAT number", text: $preset.business.taxNumber)
                TextField("Payment instructions", text: $preset.business.paymentInstructions, axis: .vertical)
                CurrencyPickerRow(currencyCode: $preset.business.currencyCode)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tax / VAT (%)").font(.caption).foregroundStyle(.secondary)
                    TextField("0", text: $preset.business.taxRate).keyboardType(.decimalPad)
                        .accessibilityLabel("Tax / VAT percentage")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reference prefix").font(.caption).foregroundStyle(.secondary)
                    TextField("e.g. FR", text: $preset.business.invoicePrefix)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .accessibilityLabel("Job reference prefix")
                }
            } header: { Text("Business details") }
              footer: {
                  if !editName { Text("Changes here apply to this job only.") }
              }
            Section("Business logo · Pro") {
                if let image = PhotoStore.image(preset.business.logoFilename) {
                    if entitlements.isPro {
                        LogoSizeControl(image: image, percentage: $preset.options.logoSize)
                    } else {
                        Image(uiImage: image).resizable().scaledToFit().frame(height: 64)
                    }
                }
                if entitlements.isPro {
                    PhotosPicker("Choose logo", selection: $selectedLogo, matching: .images).disabled(loadingLogo)
                    if !preset.business.logoFilename.isEmpty { Button("Remove logo") { preset.business.logoFilename = "" } }
                } else { lockedOption("Choose business logo", detail: "Available with Pro") }
                if loadingLogo { ProgressView("Loading logo…") }
                if !logoError.isEmpty { Text(logoError).font(.caption).foregroundStyle(.red) }
            }
            if editName {
                Section {
                    HStack {
                        TextField("Technician (optional)", text: $preset.technician)
                        Menu {
                            Button("Use job default") { preset.technician = "" }
                            if !defaults.state.recentTechnicians.isEmpty {
                                Section("Recent technicians") {
                                    ForEach(defaults.state.recentTechnicians, id: \.self) { name in
                                        Button(name) { preset.technician = name }
                                    }
                                }
                            }
                        } label: { Image(systemName: "chevron.down.circle").foregroundStyle(Brand.blue) }
                            .accessibilityLabel("Choose technician")
                    }
                    Button { showingCategory = true } label: {
                        HStack {
                            Text("Category").foregroundStyle(.primary)
                            Spacer()
                            Text(preset.category.isEmpty ? "Use job default" : preset.category).foregroundStyle(Brand.blue)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Job defaults") }
                  footer: { Text("Leave either field empty to use your usual job defaults.") }
            }
            Section {
                ForEach(DocumentTemplate.allCases, id: \.self) { layout in
                    Button {
                        if entitlements.isPro || layout == .modern { preset.options.template = layout }
                        else { showingUpgrade = true }
                    } label: {
                        HStack {
                            Text(layout.displayName).foregroundStyle(.primary)
                            Spacer()
                            if !entitlements.isPro && layout != .modern {
                                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                                proBadge
                            } else if (entitlements.isPro ? preset.options.template : .modern) == layout {
                                Image(systemName: "checkmark").foregroundStyle(Brand.blue)
                            }
                        }
                    }
                }
                DocumentColourRow(hex: $preset.options.selectedColour, isPro: entitlements.isPro) { showingUpgrade = true }
                if entitlements.isPro { Toggle("Show business logo", isOn: $preset.options.showLogo) }
                else { lockedOption("Show business logo", detail: "Off on Free") }
                Toggle(isOn: $preset.options.showBusinessDetails) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show business details")
                        Text("Phone, email and address on PDFs, plus tax number on invoices.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Document layout") }
              footer: { Text("Modern and the unmarked settings are free. Pro adds nine layouts, brand colors, logos and footer removal.") }
            Section("Work report") {
                Toggle("Show before & after photos", isOn: $preset.includePhotos)
                Toggle("Show Before / After labels", isOn: $preset.options.showPhotoLabels)
                Toggle("Show reported issue", isOn: $preset.options.showReportedIssue)
                Toggle("Show materials used", isOn: $preset.options.showMaterials)
                Toggle("Show client acknowledgment", isOn: $preset.options.showClientAcknowledgement)
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
        }.navigationTitle(editName ? (preset.name.isEmpty ? "New Preset" : "Edit Preset") : "Customize Job")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { onSave(preset); dismiss() }
                        .disabled(loadingLogo || (editName && preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
            .sheet(isPresented: $showingUpgrade) { NavigationStack { UpgradeView() } }
            .sheet(isPresented: $showingCategory) { CategorySelectionSheet(value: preset.category) { preset.category = $0 } }
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
                        preset.business.logoFilename = try PhotoStore.save(image, preserveTransparency: true)
                        preset.options.showLogo = true
                    } catch {
                        logoError = "The selected image could not be saved. Try another photo."
                    }
                }
            }
    }

    private var proBadge: some View {
        Text("PRO").font(.caption2.bold()).foregroundStyle(Brand.blue)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Brand.pale, in: Capsule())
    }

    private func lockedOption(_ title: String, detail: String) -> some View {
        Button { showingUpgrade = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                proBadge
            }
        }
    }
}

/// Stored as sRGB HEX, independent of layout. Export text uses a darker, readable ink.
enum DocumentColour {
    static let defaultHex = "155EEF"
    static let swatches = ["155EEF", "172B4D", "326352", "754C91", "9A4D30", "52616B", "242424"]

    static func normalise(_ value: String?) -> String? {
        guard let value else { return nil }
        let hex = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "").uppercased()
        return hex.range(of: "^[0-9A-F]{6}$", options: .regularExpression) == nil ? nil : hex
    }

    static func colour(_ hex: String?) -> UIColor {
        let value = UInt32(normalise(hex) ?? defaultHex, radix: 16) ?? 0x155EEF
        return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    static func hex(_ colour: Color) -> String {
        let rgb = UIColor(colour).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

struct LogoSizeControl: View {
    let image: UIImage
    @Binding var percentage: Double

    var body: some View {
        VStack(spacing: 12) {
            Image(uiImage: image).resizable().scaledToFit()
                .frame(width: 48 * percentage / 100, height: 48 * percentage / 100)
                .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Logo size preview")
            HStack {
                Text("Logo size").font(.subheadline)
                Spacer()
                Text("\(Int(percentage))%").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                Button("Reset") { percentage = 100 }.font(.caption)
                    .disabled(percentage == 100)
            }
            Slider(value: $percentage, in: 50...200, step: 5)
                .accessibilityLabel("Logo size")
                .accessibilityValue("\(Int(percentage)) percent")
        }.padding(.vertical, 4)
    }
}

struct DocumentColourRow: View {
    @Binding var hex: String?
    let isPro: Bool
    var applyToAll: ((String?) -> Void)? = nil
    var upgrade: () -> Void
    @State private var showingPicker = false

    var body: some View {
        Button { if isPro { showingPicker = true } else { upgrade() } } label: {
            HStack(spacing: 12) {
                Circle().fill(Color(uiColor: DocumentColour.colour(isPro ? hex : nil)))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.12)))
                Text("Color").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Spacer()
                if !isPro { Text("PRO").font(.caption2.bold()).foregroundStyle(Brand.blue) }
                Image(systemName: isPro ? "chevron.right" : "lock.fill").font(.caption).foregroundStyle(.secondary)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .sheet(isPresented: $showingPicker) {
                NavigationStack { DocumentColourPicker(hex: $hex, applyToAll: applyToAll) }
                    .presentationDetents([.medium, .large])
            }
    }
}

struct DocumentColourPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var hex: String?
    var applyToAll: ((String?) -> Void)? = nil
    @State private var allTemplates = false
    @State private var draft = ""
    private var selection: Binding<Color> {
        Binding(get: { Color(uiColor: DocumentColour.colour(draft)) }, set: { draft = DocumentColour.hex($0) })
    }
    var body: some View {
        Form {
            Section {
                HStack(spacing: 0) {
                    ForEach(DocumentColour.swatches, id: \.self) { value in
                        Button { draft = value } label: {
                            Circle().fill(Color(uiColor: DocumentColour.colour(value)))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 2).padding(3).opacity(draft == value ? 1 : 0))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Color #\(value)")
                            .accessibilityAddTraits(draft == value ? .isSelected : [])
                    }
                }
                ColorPicker("Custom color", selection: selection, supportsOpacity: false)
                HStack {
                    Text("HEX").foregroundStyle(.secondary)
                    TextField("155EEF", text: $draft).monospaced().multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .accessibilityLabel("Hex color code")
                }
                if DocumentColour.normalise(draft) == nil {
                    Text("Enter a six-digit color, such as 155EEF.").font(.caption).foregroundStyle(.secondary)
                }
            } footer: { Text("Applies to the current template’s report and invoice.") }
            if applyToAll != nil { Toggle("Apply to all templates", isOn: $allTemplates) }
            Button("Reset to blue") { draft = DocumentColour.defaultHex }
        }.navigationTitle("Color").navigationBarTitleDisplayMode(.inline)
            .onAppear { draft = DocumentColour.normalise(hex) ?? DocumentColour.defaultHex }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        let color = DocumentColour.normalise(draft)
                        hex = color
                        if allTemplates { applyToAll?(color) }
                        dismiss()
                    }
                        .disabled(DocumentColour.normalise(draft) == nil)
                }
            }
    }
}

// Cached gallery samples are separate from exported customer documents.
// Increment the key version when sample content or PDF layouts change.
enum TemplatePreviewCache {
    struct Entry: Codable {
        let key: String
        let document: Data
        let images: [Data]
    }
    private static let queue = DispatchQueue(label: "fixrecord.template-previews", qos: .userInitiated)

    static func load(template: DocumentTemplate, key: String, options: DocumentOptions,
                     business: BusinessSnapshot?, isPro: Bool, includePhotos: Bool) async throws -> Entry {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let result = try autoreleasepool {
                        try loadOrRender(template: template, key: key, options: options,
                                         business: business, isPro: isPro, includePhotos: includePhotos)
                    }
                    continuation.resume(returning: result)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func loadOrRender(template: DocumentTemplate, key: String, options: DocumentOptions,
                                     business: BusinessSnapshot?, isPro: Bool, includePhotos: Bool) throws -> Entry {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TemplatePreviews", isDirectory: true)
        // One replaceable entry per layout keeps disk usage bounded.
        let file = folder.appendingPathComponent(template.rawValue + ".json")
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Entry.self, from: data),
           saved.key == key, saved.images.count == 2,
           saved.images.allSatisfy({ UIImage(data: $0) != nil }), PDFDocument(data: saved.document) != nil {
            return saved
        }
        // Create detached sample models on this queue; never pass live SwiftData models across threads.
        let job = SampleJob.make()
        let profile = business?.asProfile()
        let report = try PDFMaker.make(kind: .report, job: job, profile: profile, options: options,
                                      isPro: isPro, includePhotos: includePhotos, previewLayout: template)
        let invoice = try PDFMaker.make(kind: .invoice, job: job, profile: profile, options: options,
                                       isPro: isPro, previewLayout: template)
        guard let pdf = PDFDocument(data: report), let invoicePDF = PDFDocument(data: invoice),
              let reportPage = pdf.page(at: 0), let invoicePage = invoicePDF.page(at: 0),
              let first = reportPage.thumbnail(of: CGSize(width: 420, height: 594), for: .mediaBox).pngData(),
              let second = invoicePage.thumbnail(of: CGSize(width: 420, height: 594), for: .mediaBox).pngData() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for index in 0..<invoicePDF.pageCount {
            if let page = invoicePDF.page(at: index) { pdf.insert(page, at: pdf.pageCount) }
        }
        guard let document = pdf.dataRepresentation() else { throw CocoaError(.fileReadCorruptFile) }
        let result = Entry(key: key, document: document, images: [first, second])
        // Cache failures must not prevent viewing a generated preview.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(result) { try? data.write(to: file, options: .atomic) }
        return result
    }
}

struct TemplatesView: View {
    @Query private var profiles: [BusinessProfile]
    @AppStorage("showPhotosInWorkReport") private var includePreviewPhotos = true
    @State private var options = DocumentOptions.load()
    @StateObject private var entitlements = EntitlementService.shared
    @State private var showingUpgrade = false
    @State private var showingPreviewUpgrade = false
    @State private var preview: DocumentTemplate?
    @State private var documents: [DocumentTemplate: Data] = [:]
    @State private var thumbnails: [DocumentTemplate: [UIImage]] = [:]
    @State private var previewError = ""
    @State private var renderedPreviewKeys: [DocumentTemplate: String] = [:]
    private var selected: DocumentTemplate { options.effective(isPro: entitlements.isPro).template }
    private func previewKey(for template: DocumentTemplate) -> String {
        var settings = options.effective(isPro: entitlements.isPro)
        settings.brandColourHex = settings.colour(for: template)
        settings.templateColours = nil
        settings.template = template
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let settingsKey = (try? encoder.encode(settings).base64EncodedString()) ?? ""
        let businessKey = (try? encoder.encode(BusinessSnapshot(profile: profiles.first)).base64EncodedString()) ?? ""
        return "gallery-v2-\(Locale.current.identifier)-\(TimeZone.current.identifier)-\(entitlements.isPro)-\(includePreviewPhotos)-\(settingsKey)-\(businessKey)"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !previewError.isEmpty { Text(previewError).font(.caption).foregroundStyle(.secondary) }
                ForEach(DocumentTemplate.allCases, id: \.self) { template in
                    VStack(alignment: .leading, spacing: 12) {
                        Button { preview = template } label: {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(Array((renderedPreviewKeys[template] == previewKey(for: template) ? thumbnails[template] ?? [] : []).enumerated()), id: \.offset) { index, image in
                                    VStack(spacing: 8) {
                                        Image(uiImage: image).resizable().scaledToFit()
                                            .background(.white).clipShape(RoundedRectangle(cornerRadius: 3))
                                            .shadow(color: .black.opacity(0.10), radius: 5, y: 3)
                                        Text(index == 0 ? "Report" : "Invoice").font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity)
                                }
                                if renderedPreviewKeys[template] != previewKey(for: template) {
                                    if previewError.isEmpty { ProgressView().frame(maxWidth: .infinity, minHeight: 180) }
                                    else { Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 180) }
                                }
                            }.padding(16).frame(maxWidth: .infinity)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).disabled(renderedPreviewKeys[template] != previewKey(for: template))
                            .accessibilityLabel("Preview \(template.displayName) report and invoice")
                        HStack(spacing: 8) {
                            Text(template.displayName).font(.headline)
                            if !entitlements.isPro && template != .modern { Text("PRO").font(.caption2.bold()).foregroundStyle(Brand.blue).padding(.horizontal, 7).padding(.vertical, 4).background(Brand.pale, in: Capsule()) }
                            Spacer()
                            Button {
                                if entitlements.isPro || template == .modern { options.template = template }
                                else { showingUpgrade = true }
                            } label: {
                                Image(systemName: selected == template ? "checkmark.circle.fill" : "circle")
                                    .font(.title2).foregroundStyle(selected == template ? Brand.blue : Color.secondary)
                                    .frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel(selected == template ? "\(template.displayName), selected" : "Use \(template.displayName)")
                        }
                    }.padding(14).background(Brand.background, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected == template ? Brand.blue.opacity(0.5) : Color.primary.opacity(0.07), lineWidth: 1))
                        .task(id: previewKey(for: template)) { await renderPreview(template) }
                }
                Text("Used for new jobs. Customize an existing job from its document preview.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(18)
        }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Templates")
            .onAppear { options = .load() }
            .onChange(of: options) { _, value in value.save() }
            .sheet(isPresented: $showingUpgrade) { NavigationStack { UpgradeView() } }
            .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
                NavigationStack {
                    if let preview, renderedPreviewKeys[preview] == previewKey(for: preview), let data = documents[preview] {
                        PDFPreview(data: data).navigationTitle(preview.displayName).navigationBarTitleDisplayMode(.inline)
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                DocumentColourRow(hex: Binding(
                                    get: { options.colour(for: preview) },
                                    set: { options.setColour($0, for: preview) }
                                ), isPro: entitlements.isPro, applyToAll: { options.setColourForAll($0) }) {
                                    showingPreviewUpgrade = true
                                }
                                .padding(.horizontal, 20).padding(.vertical, 10)
                                .background(.regularMaterial)
                                .overlay(alignment: .top) { Divider() }
                            }
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { self.preview = nil }
                                }
                            }
                    } else {
                        ProgressView("Loading preview…")
                    }
                }
                .task(id: preview.map { previewKey(for: $0) }) { if let preview { await renderPreview(preview) } }
                .sheet(isPresented: $showingPreviewUpgrade) { NavigationStack { UpgradeView() } }
            }
            .task { await entitlements.refresh() }
    }

    @MainActor private func renderPreview(_ template: DocumentTemplate) async {
        let key = previewKey(for: template)
        guard renderedPreviewKeys[template] != key, !Task.isCancelled else { return }
        let business = profiles.first.map { BusinessSnapshot(profile: $0) }
        do {
            let result = try await TemplatePreviewCache.load(template: template, key: key,
                options: options.effective(isPro: entitlements.isPro), business: business,
                isPro: entitlements.isPro, includePhotos: includePreviewPhotos)
            guard !Task.isCancelled, key == previewKey(for: template) else { return }
            documents[template] = result.document
            thumbnails[template] = result.images.compactMap { UIImage(data: $0) }
            renderedPreviewKeys[template] = key
            previewError = ""
        } catch {
            guard !Task.isCancelled, key == previewKey(for: template) else { return }
            previewError = "Could not load this preview. Reopen Templates to try again."
        }
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
                DocumentColourRow(hex: $options.selectedColour, isPro: entitlements.isPro) { showingUpgrade = true }
                proToggle("Show business logo", value: $options.showLogo)
                Toggle(isOn: $options.showBusinessDetails) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show business details")
                        Text("Phone, email and address on PDFs, plus tax number on invoices.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Work Report") {
                Toggle("Show before & after photos", isOn: $showPhotosInWorkReport)
                Toggle("Show Before / After labels", isOn: $options.showPhotoLabels)
                Toggle("Show reported issue", isOn: $options.showReportedIssue)
                Toggle("Show materials used", isOn: $options.showMaterials)
                Toggle("Show client acknowledgment", isOn: $options.showClientAcknowledgement)
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
    private func proToggle(_ title: String, value: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            if !entitlements.isPro { Text("PRO").font(.caption2.bold()).foregroundStyle(Brand.blue) }
            Toggle(title, isOn: Binding(get: { entitlements.isPro && value.wrappedValue }, set: { newValue in if entitlements.isPro { value.wrappedValue = newValue } else { showingUpgrade = true } })).labelsHidden()
        }
    }
}
