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
            Section("Your work note") { TextEditor(text: $job.roughNote).frame(minHeight: 140); Text("Record what you did and observed. The note remains usable without AI.").font(.caption).foregroundStyle(.secondary) }
            Section { Button { Task { await improve() } } label: { Label(busy ? "Improving…" : "Improve with AI", systemImage: "sparkles") }.disabled(busy || job.roughNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            if !message.isEmpty { Section { Text(message).font(.caption).foregroundStyle(.secondary) } }
            if !draft.isEmpty { Section("AI-assisted draft · review before use") { TextEditor(text: $draft).frame(minHeight: 140); Button("Use this note") { job.professionalNote = draft; draft = ""; message = "Reviewed note saved." } } }
            if !job.professionalNote.isEmpty { Section("Saved professional note") { TextEditor(text: $job.professionalNote).frame(minHeight: 130) } }
        }.navigationTitle("Job Notes")
    }
    private func improve() async {
        busy = true; defer { busy = false }
        do { draft = try await AIService.improve(job: job).professionalSummary; message = "Review and edit this AI-assisted draft. It has not verified the work." }
        catch { message = "AI is unavailable. Your manual note is saved and can be used in the report." }
    }
}

struct PricingView: View {
    @Bindable var job: Job
    private var totals: InvoiceTotals { InvoiceTotals(items: job.items, discount: Money.parse(job.discount), taxRate: Money.parse(job.taxRate)) }
    private var valid: Bool { Money.isValid(job.discount) && Money.isValid(job.taxRate) && job.items.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Money.isValid($0.quantity) && Money.isValid($0.unitPrice) } }
    var body: some View {
        Form {
            Section { Text(job.title).font(.headline); Text(job.number).font(.caption).foregroundStyle(.secondary) }
            itemSection("Materials", kind: .material)
            itemSection("Labour", kind: .labour)
            itemSection("Additional charges", kind: .charge)
            Section("Adjustments") { HStack { Text("Currency"); Spacer(); TextField("Code", text: $job.currencyCode).multilineTextAlignment(.trailing).textInputAutocapitalization(.characters).frame(width: 80) }; HStack { Text("Tax / VAT %"); Spacer(); TextField("0", text: $job.taxRate).multilineTextAlignment(.trailing).keyboardType(.decimalPad).frame(width: 90) }; HStack { Text("Fixed discount"); Spacer(); TextField("0", text: $job.discount).multilineTextAlignment(.trailing).keyboardType(.decimalPad).frame(width: 90) }; DatePicker("Due date", selection: $job.dueDate, displayedComponents: .date); Toggle("Mark invoice paid", isOn: $job.paid); TextField("Invoice notes", text: $job.invoiceNotes, axis: .vertical) }
            Section("Live summary") { totalRow("Materials", totals.materials); totalRow("Labour", totals.labour); totalRow("Additional charges", totals.charges); totalRow("Subtotal", totals.subtotal); totalRow("Discount", -totals.discount); totalRow("Tax / VAT", totals.tax); HStack { Text("Grand total").font(.headline); Spacer(); Text(Money.format(totals.grandTotal, currency: job.currencyCode)).font(.headline).foregroundStyle(Brand.teal) } }
            if !valid { Section { Label("Add a description and review quantities or prices before exporting the invoice.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) } }
            Section { NavigationLink("Preview invoice") { ExportView(job: job) }.disabled(!valid) }
        }.navigationTitle("Materials & Pricing")
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
        List {
            Section { Label(service.isPro ? "Pro active" : "Free plan", systemImage: service.isPro ? "checkmark.seal.fill" : "leaf"); Text("The core job, MatchShot, report and invoice workflows are available on Free.").font(.subheadline) }
            Section("Upgrade") {
                ForEach(service.packages, id: \.identifier) { package in Button { Task { await service.purchase(package) } } label: { HStack { Text(package.storeProduct.localizedTitle); Spacer(); Text(package.storeProduct.localizedPriceString) } } }
                if service.packages.isEmpty { Text("No packages are configured. Connect a Test Store offering with a pro entitlement in RevenueCat.").font(.caption).foregroundStyle(.secondary) }
                Button("Restore purchases") { Task { await service.restore() } }.disabled(!service.configured)
            }
            if !service.message.isEmpty { Section { Text(service.message).font(.caption) } }
        }.navigationTitle("Plan & Upgrade").task { await service.refresh() }
    }
}

enum FeatureAccess { static func canExportClientPack(isPro: Bool) -> Bool { isPro } }
