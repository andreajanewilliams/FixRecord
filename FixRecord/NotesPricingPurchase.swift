import SwiftUI
import RevenueCat

struct AIResponse: Codable {
    let reportedIssue: String
    let workCompleted: String
    let completionNotes: String
    let professionalSummary: String
}

enum AIService {
    static func improve(job: Job) async throws -> AIResponse {
        let endpoint = (Bundle.main.object(forInfoDictionaryKey: "AI_ENDPOINT") as? String) ?? ""
        guard let url = URL(string: endpoint), !endpoint.isEmpty else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let installID: String = {
            if let id = UserDefaults.standard.string(forKey: "installID") { return id }
            let id = UUID().uuidString; UserDefaults.standard.set(id, forKey: "installID"); return id
        }()
        let body: [String: Any] = ["installId": installID, "jobId": job.id.uuidString, "revenueCatAppUserId": installID, "jobTitle": String(job.title.prefix(150)), "issueDescription": String(job.issue.prefix(1000)), "roughNotes": String(job.roughNote.prefix(3000)), "materials": job.items.filter { $0.kind == .material }.map(\.name), "locale": Locale.current.identifier]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(AIResponse.self, from: data)
    }
}

struct NotesView: View {
    @Bindable var job: Job
    @State private var draft = ""
    @State private var message = ""
    @State private var busy = false
    var body: some View {
        Form {
            Section { VoiceTextInput(title: "Reported Issue", placeholder: "What was reported?", text: $job.issue) }
            Section { VoiceTextInput(title: "Work Completed", placeholder: "Describe what you completed…", text: $job.roughNote) }
            Section { Button { Task { await improve() } } label: { Label(busy ? "Improving…" : "Improve with AI", systemImage: "sparkles") }.disabled(busy || job.roughNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            if !message.isEmpty { Section { Text(message).font(.caption).foregroundStyle(.secondary) } }
            if !draft.isEmpty {
                Section("AI-assisted draft · review and edit") {
                    TextEditor(text: $draft).frame(minHeight: 120)
                    HStack {
                        Button("Try Again") { Task { await improve() } }.disabled(busy)
                        Spacer()
                        Button("Use This Version") { job.professionalNote = draft; draft = ""; message = "Reviewed wording saved." }.buttonStyle(.borderedProminent)
                    }
                }
            }
            if !job.professionalNote.isEmpty { Section("Approved wording") { TextEditor(text: $job.professionalNote).frame(minHeight: 110) } }
        }.navigationTitle("Work Details")
            .onChange(of: job.issue) { _, _ in job.technicianConfirmed = false }
            .onChange(of: job.roughNote) { _, _ in job.technicianConfirmed = false }
            .onChange(of: job.professionalNote) { _, _ in job.technicianConfirmed = false }
    }
    private func improve() async {
        busy = true; defer { busy = false }
        do { draft = try await AIService.improve(job: job).professionalSummary; message = "Review and edit this AI-assisted draft. It has not verified the work." }
        catch { message = "AI is unavailable. Your manual note is saved and can be used in the report." }
    }
}

struct PricingView: View {
    @Bindable var job: Job
    private var documentOptions: DocumentOptions { DocumentOptions.load() }
    private var totals: InvoiceTotals { InvoiceTotals(items: job.items, discount: documentOptions.showDiscount ? Money.parse(job.discount) : 0, taxRate: documentOptions.showTax ? Money.parse(job.taxRate) : 0) }
    private var valid: Bool { Money.isValid(job.discount) && Money.isValid(job.taxRate) && job.items.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Money.isValid($0.quantity) && Money.isValid($0.unitPrice) } }
    var body: some View {
        Form {
            Section { Text(job.title).font(.headline); Text(job.number).font(.caption).foregroundStyle(.secondary) }
            itemSection("Materials", kind: .material)
            itemSection("Labour", kind: .labour)
            itemSection("Additional charges", kind: .charge)
            Section("Adjustments") { HStack { Text("Currency"); Spacer(); TextField("Code", text: $job.currencyCode).multilineTextAlignment(.trailing).textInputAutocapitalization(.characters).frame(width: 80) }; HStack { Text("Tax / VAT %"); Spacer(); TextField("0", text: $job.taxRate).multilineTextAlignment(.trailing).keyboardType(.decimalPad).frame(width: 90) }; HStack { Text("Fixed discount"); Spacer(); TextField("0", text: $job.discount).multilineTextAlignment(.trailing).keyboardType(.decimalPad).frame(width: 90) }; DatePicker("Due date", selection: $job.dueDate, displayedComponents: .date); Toggle("Mark invoice paid", isOn: $job.paid); TextField("Invoice notes", text: $job.invoiceNotes, axis: .vertical) }
            Section("Live summary") { totalRow("Materials", totals.materials); totalRow("Labour", totals.labour); totalRow("Additional charges", totals.charges); totalRow("Subtotal", totals.subtotal); if documentOptions.showDiscount { totalRow("Discount", -totals.discount) }; if documentOptions.showTax { totalRow("Tax / VAT", totals.tax) }; HStack { Text("Grand total").font(.headline); Spacer(); Text(Money.format(totals.grandTotal, currency: job.currencyCode)).font(.headline).foregroundStyle(Brand.blue) } }
            if !valid { Section { Label("Add a description and review quantities or prices before exporting the invoice.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) } }
            Section { NavigationLink("Preview invoice") { ExportView(job: job) }.disabled(!valid) }
        }.navigationTitle("Materials & Pricing")
            .onChange(of: job.itemsData) { _, _ in job.technicianConfirmed = false }
    }
    private func itemSection(_ title: String, kind: PriceItem.Kind) -> some View {
        Section(title) {
            ForEach(job.items.filter { $0.kind == kind }) { item in
                VStack(alignment: .leading, spacing: 7) {
                    TextField("Description", text: itemBinding(item.id, \.name))
                    HStack { TextField(kind == .labour ? "Hours" : "Qty", text: itemBinding(item.id, \.quantity)).keyboardType(.decimalPad).frame(width: 75); Text("×"); TextField(kind == .labour ? "Hourly rate" : "Unit price", text: itemBinding(item.id, \.unitPrice)).keyboardType(.decimalPad).frame(width: 110); Spacer(); Text(Money.format(item.total, currency: job.currencyCode)).font(.caption.bold()) }
                    Button("Remove", role: .destructive) { var items = job.items; items.removeAll { $0.id == item.id }; job.items = items }.font(.caption)
                }.padding(.vertical, 3)
            }
            Button { var items = job.items; items.append(PriceItem(kind: kind, name: "", unitPrice: "0")); job.items = items } label: { Label("Add \(kind.rawValue.capitalized)", systemImage: "plus") }
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
                    Label("Remove FixRecord branding", systemImage: "checkmark.circle.fill")
                    Label("Add your business logo", systemImage: "checkmark.circle.fill")
                    Label("Choose premium templates", systemImage: "checkmark.circle.fill")
                    Label("More AI-assisted writing", systemImage: "checkmark.circle.fill")
                }.font(.subheadline).foregroundStyle(Brand.navy).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                if !service.isPro {
                    ForEach(service.packages, id: \.identifier) { package in
                        Button { Task { await service.purchase(package) } } label: {
                            HStack { Text(package.storeProduct.localizedTitle); Spacer(); Text(package.storeProduct.localizedPriceString) }
                                .font(.headline).frame(maxWidth: .infinity).padding(15).foregroundStyle(.white).background(Brand.blue, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    if service.packages.isEmpty { Text("Purchases are unavailable right now.").font(.caption).foregroundStyle(.secondary) }
                }
                Button("Restore Purchases") { Task { await service.restore() } }.disabled(!service.configured).frame(maxWidth: .infinity)
                if !service.message.isEmpty { Text(service.message).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
            }.padding(20)
        }.background(Brand.background).navigationTitle("FixRecord Pro").navigationBarTitleDisplayMode(.inline).task { await service.refresh() }
    }
}

enum FeatureAccess { static func canExportClientPack(isPro: Bool) -> Bool { isPro } }
