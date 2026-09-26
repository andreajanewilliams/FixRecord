import SwiftUI
import RevenueCat
import UIKit
import Security

enum AIAccessCodeStore {
    private static let service = "com.andreajanewilliams.fixrecord.ai"
    private static let account = "accessCode"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static func load() -> String? {
        var result: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ code: String) -> Bool {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (20...128).contains(value.count), let data = value.data(using: .utf8) else { return false }
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
    static func remove() { SecItemDelete(query as CFDictionary) }
}

struct AIResponse: Codable {
    let reportedIssue: String
    let workCompleted: String
    let completionNotes: String
    let professionalSummary: String
}

enum AIService {
    enum Failure: LocalizedError {
        case notConfigured, accessCodeRequired, insufficientDetail, limitReached, unavailable, invalidResponse
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "AI writing is not set up yet. Your note is still available."
            case .accessCodeRequired: return "Enter the judging code to use AI writing."
            case .insufficientDetail: return "Add a work note or a Before/After photo first."
            case .limitReached: return "AI limit reached. You can keep editing your note or try again later."
            case .unavailable: return "AI is unavailable right now. Your note is still available."
            case .invalidResponse: return "AI could not prepare a draft. Please try again."
            }
        }
    }
    static func endpointURL(from value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil else { return nil }
        return url
    }
    static var endpointURL: URL? {
        endpointURL(from: (Bundle.main.object(forInfoDictionaryKey: "AI_ENDPOINT") as? String) ?? "")
    }
    static var isConfigured: Bool { endpointURL != nil }
    static func validateAccessCode(_ code: String) async throws {
        guard let url = endpointURL else { throw Failure.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(code.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "X-FixRecord-Access-Code")
        // The server checks the code before job facts. An empty body returns 400 for an
        // accepted code, without calling the model or using the AI request allowance.
        request.httpBody = Data("{}".utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.unavailable }
        switch http.statusCode {
        case 400: return
        case 401: throw Failure.accessCodeRequired
        default: throw Failure.unavailable
        }
    }
    static func clipped(_ value: String, maxUTF16Units: Int) -> String {
        var result = ""
        var remaining = maxUTF16Units
        for scalar in value.unicodeScalars {
            let units = scalar.value > 0xFFFF ? 2 : 1
            guard units <= remaining else { break }
            result.unicodeScalars.append(scalar)
            remaining -= units
        }
        return result
    }
    private static func selectedPhotos(for job: Job) -> (before: JobPhoto?, after: JobPhoto?) {
        let photos = job.photos
        let after = photos.last { $0.kind == .after && PhotoStore.image($0.filename) != nil }
        let before = photos.first { $0.id == after?.pairedBeforeID && PhotoStore.image($0.filename) != nil }
            ?? photos.last { $0.kind == .before && PhotoStore.image($0.filename) != nil }
        return (before, after)
    }
    static func hasReadablePhoto(job: Job) -> Bool {
        let photos = selectedPhotos(for: job)
        return photos.before != nil || photos.after != nil
    }
    static func hasEvidence(job: Job) -> Bool {
        !job.roughNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasReadablePhoto(job: job)
    }
    private static func encodedPhoto(_ photo: JobPhoto?) -> String? {
        guard let photo, let image = PhotoStore.image(photo.filename), image.size.width > 0, image.size.height > 0 else { return nil }
        func jpeg(maxDimension: CGFloat, quality: CGFloat) -> Data? {
            let width = CGFloat(image.cgImage?.width ?? Int(image.size.width * image.scale))
            let height = CGFloat(image.cgImage?.height ?? Int(image.size.height * image.scale))
            let scale = min(1, maxDimension / max(width, height))
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let resized = UIGraphicsImageRenderer(size: CGSize(width: width * scale, height: height * scale), format: format)
                .image { _ in image.draw(in: CGRect(x: 0, y: 0, width: width * scale, height: height * scale)) }
            return resized.jpegData(compressionQuality: quality)
        }
        let preferred = jpeg(maxDimension: 1200, quality: 0.72)
        let data = preferred.flatMap { $0.count <= 900_000 ? $0 : nil }
            ?? jpeg(maxDimension: 900, quality: 0.55)
        guard let data, data.count <= 900_000 else { return nil }
        return data.base64EncodedString()
    }
    static func improve(job: Job) async throws -> AIResponse {
        guard let url = endpointURL else { throw Failure.notConfigured }
        guard let accessCode = AIAccessCodeStore.load() else { throw Failure.accessCodeRequired }
        let photos = selectedPhotos(for: job)
        let beforeImage = encodedPhoto(photos.before)
        let afterImage = encodedPhoto(photos.after)
        guard !job.roughNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || beforeImage != nil || afterImage != nil else { throw Failure.insufficientDetail }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accessCode, forHTTPHeaderField: "X-FixRecord-Access-Code")
        let installKey = "aiInstallationID"
        let installID = UserDefaults.standard.string(forKey: installKey) ?? UUID().uuidString
        UserDefaults.standard.set(installID, forKey: installKey)
        var body: [String: Any] = ["installId": installID, "jobTitle": clipped(job.title, maxUTF16Units: 150), "issueDescription": clipped(job.issue, maxUTF16Units: 1000), "roughNotes": clipped(job.roughNote, maxUTF16Units: 3000), "materials": job.items.filter { $0.kind == .material }.prefix(30).map { clipped($0.name, maxUTF16Units: 80) }, "locale": clipped(Locale.current.identifier, maxUTF16Units: 40)]
        if let beforeImage { body["beforeImage"] = beforeImage }
        if let afterImage { body["afterImage"] = afterImage }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.unavailable }
        if http.statusCode == 401 { throw Failure.accessCodeRequired }
        if http.statusCode == 429 { throw Failure.limitReached }
        guard (200..<300).contains(http.statusCode) else { throw Failure.unavailable }
        guard let result = try? JSONDecoder().decode(AIResponse.self, from: data),
              !result.professionalSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalidResponse }
        return result
    }
}

struct NotesView: View {
    @Bindable var job: Job
    @State private var draft = ""
    @State private var message = ""
    @State private var busy = false
    @State private var hasPhotoEvidence = false
    @State private var showingAccessCode = false
    @State private var codeRejected = false
    var body: some View {
        let hasEvidence = !job.roughNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasPhotoEvidence
        return Form {
            Section { VoiceTextInput(title: "Reported Issue", placeholder: "What was reported?", text: $job.issue) }
            Section { VoiceTextInput(title: "Work Completed", placeholder: "Describe what you completed…", text: $job.roughNote) }
            Section {
                Button { requestImprovement() } label: { Label(busy ? "Improving…" : "Improve with AI", systemImage: "sparkles") }
                    .disabled(busy || !AIService.isConfigured || !hasEvidence)
                if !hasEvidence {
                    Text("Add a work note or a Before/After photo to use AI.").font(.caption).foregroundStyle(.secondary)
                } else if !AIService.isConfigured {
                    Text("AI writing will be available after setup.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !message.isEmpty { Section { Text(message).font(.caption).foregroundStyle(.secondary) } }
            if !draft.isEmpty {
                Section("AI-assisted draft · review and edit") {
                    TextEditor(text: $draft).frame(minHeight: 120)
                    HStack {
                        Button("Try Again") { requestImprovement() }.disabled(busy)
                        Spacer()
                        Button("Use This Version") { job.professionalNote = draft; draft = ""; message = "Reviewed wording saved." }.buttonStyle(.borderedProminent)
                    }
                }
            }
            if !job.professionalNote.isEmpty { Section("Approved wording") { TextEditor(text: $job.professionalNote).frame(minHeight: 110) } }
        }.navigationTitle("Work Details")
            .onAppear { hasPhotoEvidence = AIService.hasReadablePhoto(job: job) }
            .onChange(of: job.photosData) { _, _ in hasPhotoEvidence = AIService.hasReadablePhoto(job: job) }
            .onChange(of: job.issue) { _, _ in job.technicianConfirmed = false }
            .onChange(of: job.roughNote) { _, _ in job.technicianConfirmed = false }
            .onChange(of: job.professionalNote) { _, _ in job.technicianConfirmed = false }
            .sheet(isPresented: $showingAccessCode) {
                NavigationStack {
                    AIAccessCodeView(warning: codeRejected ? "That code was not accepted. Check it and try again." : nil, onSaved: {
                        showingAccessCode = false
                        codeRejected = false
                        message = ""
                        Task { await improve() }
                    }, onCancel: { showingAccessCode = false })
                }
                .interactiveDismissDisabled()
            }
    }
    private func requestImprovement() {
        if AIAccessCodeStore.load() == nil { codeRejected = false; showingAccessCode = true }
        else { Task { await improve() } }
    }
    private func improve() async {
        busy = true; defer { busy = false }
        do { draft = try await AIService.improve(job: job).professionalSummary; message = "Review and edit this AI-assisted draft. It has not verified the work." }
        catch {
            if let failure = error as? AIService.Failure, case .accessCodeRequired = failure {
                message = "That code was not accepted. Check it and try again."
                codeRejected = true
                showingAccessCode = true
            } else {
                message = (error as? AIService.Failure)?.localizedDescription ?? AIService.Failure.unavailable.localizedDescription
            }
        }
    }
}

struct PricingView: View {
    @Bindable var job: Job
    private var documentOptions: DocumentOptions { job.documentOptions }
    private var totals: InvoiceTotals { InvoiceTotals(items: job.items, discount: documentOptions.showDiscount ? Money.parse(job.discount) : 0, taxRate: documentOptions.showTax ? Money.parse(job.taxRate) : 0) }
    private var valid: Bool { Money.isValid(job.discount) && Money.isValid(job.taxRate) && job.items.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Money.isValid($0.quantity) && Money.isValid($0.unitPrice) } }
    var body: some View {
        Form {
            itemSection("Materials", kind: .material)
            itemSection("Labour", kind: .labour)
            itemSection("Additional charges", kind: .charge)
            Section("Adjustments") { CurrencyPickerRow(currencyCode: Binding(get: { job.currencyCode }, set: { job.setCurrency($0) })); HStack { Text("Tax / VAT %"); Spacer(); TextField("0", text: $job.taxRate).multilineTextAlignment(.trailing).keyboardType(.decimalPad).frame(width: 90) }; HStack { Text("Fixed discount"); Spacer(); TextField("0", text: $job.discount).multilineTextAlignment(.trailing).keyboardType(.decimalPad).frame(width: 90) }; DatePicker("Due date", selection: $job.dueDate, displayedComponents: .date); Toggle("Mark invoice paid", isOn: $job.paid); TextField("Invoice notes", text: $job.invoiceNotes, axis: .vertical) }
            Section("Live summary") { totalRow("Materials", totals.materials); totalRow("Labour", totals.labour); totalRow("Additional charges", totals.charges); totalRow("Subtotal", totals.subtotal); if documentOptions.showDiscount { totalRow("Discount", -totals.discount) }; if documentOptions.showTax { totalRow("Tax / VAT", totals.tax) }; HStack { Text("Grand total").font(.headline); Spacer(); Text(Money.format(totals.grandTotal, currency: job.currencyCode)).font(.headline).foregroundStyle(Brand.blue) } }
            if !valid { Section { Label("Add a description and review quantities or prices before exporting the invoice.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) } }
            Section { NavigationLink("Preview invoice") { ExportView(job: job) }.disabled(!valid) }
        }.navigationTitle("Materials & Pricing")
            .onChange(of: job.itemsData) { _, _ in job.technicianConfirmed = false }
    }
    private func itemSection(_ title: String, kind: PriceItem.Kind) -> some View {
        Section(title) {
            ForEach(job.items.filter { $0.kind == kind }) { item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        TextField("Description", text: itemBinding(item.id, \.name))
                        Button(role: .destructive) {
                            var items = job.items
                            items.removeAll { $0.id == item.id }
                            job.items = items
                        } label: {
                            Image(systemName: "trash")
                                .font(.subheadline)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Remove \(item.name.isEmpty ? kind.rawValue : item.name)")
                    }
                    HStack {
                        TextField(kind == .labour ? "Hours" : "Qty", text: itemBinding(item.id, \.quantity))
                            .keyboardType(.decimalPad).frame(width: 75)
                        Text("×").foregroundStyle(.secondary)
                        TextField(kind == .labour ? "Hourly rate" : "Unit price", text: itemBinding(item.id, \.unitPrice))
                            .keyboardType(.decimalPad).frame(width: 110)
                        Spacer()
                        Text(Money.format(item.total, currency: job.currencyCode)).font(.caption.bold())
                    }
                }
                .padding(.vertical, 2)
            }
            Button { var items = job.items; items.append(PriceItem(kind: kind, name: "", unitPrice: "0")); job.items = items } label: { Label("Add \(kind.rawValue.capitalized)", systemImage: "plus") }
            if kind == .material {
                NavigationLink { ReceiptView(job: job) } label: { Label("Scan receipt", systemImage: "doc.viewfinder") }
            }
        }
    }
    private func itemBinding(_ id: UUID, _ keyPath: WritableKeyPath<PriceItem, String>) -> Binding<String> {
        Binding(get: { job.items.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" }, set: { value in var items = job.items; if let index = items.firstIndex(where: { $0.id == id }) { items[index][keyPath: keyPath] = value; job.items = items } })
    }
    private func totalRow(_ label: String, _ amount: Decimal) -> some View { HStack { Text(label); Spacer(); Text(Money.format(amount, currency: job.currencyCode)) } }
}

@MainActor final class EntitlementService: ObservableObject {
    static let shared = EntitlementService()
    @Published private(set) var isPro = false
    @Published private(set) var packages: [Package] = []
    @Published var message = ""
    private(set) var configured = false
    private init() {
        let key = (Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String) ?? ""
        guard !key.isEmpty, !key.contains("YOUR_") else { message = "Add a RevenueCat Test Store public key to enable test purchases."; return }
        let id = UserDefaults.standard.string(forKey: "installID") ?? UUID().uuidString
        UserDefaults.standard.set(id, forKey: "installID")
        Purchases.configure(withAPIKey: key, appUserID: id)
        configured = true
    }
    func refresh() async {
        guard configured else { return }
        do {
            let info = try await Purchases.shared.customerInfo()
            isPro = info.entitlements["pro"]?.isActive == true
            packages = try await Purchases.shared.offerings().current?.availablePackages ?? []
        } catch { message = error.localizedDescription }
    }
    func purchase(_ package: Package) async {
        do { let result = try await Purchases.shared.purchase(package: package); isPro = result.customerInfo.entitlements["pro"]?.isActive == true; message = isPro ? "Pro is active." : "No Pro entitlement was granted." }
        catch { message = error.localizedDescription }
    }
    func restore() async {
        guard configured else { message = "Add a RevenueCat Test Store public key to restore purchases."; return }
        do { let info = try await Purchases.shared.restorePurchases(); isPro = info.entitlements["pro"]?.isActive == true; message = isPro ? "Pro restored." : "No active Pro purchase found." }
        catch { message = error.localizedDescription }
    }
}

struct UpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = EntitlementService.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 9) {
                    Image(systemName: service.isPro ? "checkmark.seal.fill" : "star.square.fill").font(.system(size: 48)).foregroundStyle(Brand.blue)
                    Text(service.isPro ? "FixRecord Pro is active" : "Upgrade to FixRecord Pro").font(.title.bold()).multilineTextAlignment(.center)
                    Text("Make every document your business's own.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.top, 28)
                VStack(alignment: .leading, spacing: 16) {
                    Label("Combine report and invoice in a Client Pack", systemImage: "checkmark.circle.fill")
                    Label("Remove FixRecord branding", systemImage: "checkmark.circle.fill")
                    Label("Add your business logo", systemImage: "checkmark.circle.fill")
                    Label("Choose premium templates", systemImage: "checkmark.circle.fill")
                    Label("Pro demo code: 30 AI requests/month (Free: 3)", systemImage: "checkmark.circle.fill")
                }.font(.subheadline).foregroundStyle(Brand.navy).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                if !service.isPro {
                    ForEach(service.packages, id: \.identifier) { package in
                        Button { Task { await service.purchase(package) } } label: {
                            HStack { Text(package.storeProduct.localizedTitle); Spacer(); Text(package.storeProduct.localizedPriceString) }
                                .font(.headline).frame(maxWidth: .infinity).padding(15).foregroundStyle(.white).background(Brand.blue, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    if service.packages.isEmpty {
                        Text(service.configured ? "Pro plans are unavailable right now." : "Pro purchases aren't enabled in this test build.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Restore Purchases") { Task { await service.restore() } }.disabled(!service.configured).frame(maxWidth: .infinity)
                if !service.message.isEmpty { Text(service.message).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
            }.padding(20)
        }.background(Brand.background).navigationTitle("FixRecord Pro").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task { await service.refresh() }
    }
}

enum FeatureAccess { static func canExportClientPack(isPro: Bool) -> Bool { isPro } }
