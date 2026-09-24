import Foundation
import SwiftData
import UIKit
import Observation

enum JobCategories {
    static let builtIn = ["Plumbing", "Electrical", "HVAC", "Installation", "Carpentry", "Painting", "Maintenance", "Inspection"]
}

enum DefaultCategoryMode: String, Codable, CaseIterable {
    case none, lastUsed, selected
}

struct JobDefaultsState: Codable, Equatable {
    var hasRecordedJob = false
    var defaultTechnician = ""
    var categoryMode: DefaultCategoryMode = .lastUsed
    var selectedCategory = ""
    var lastUsedTechnician = ""
    var lastUsedCategory = ""
    var recentTechnicians: [String] = []
    var customCategories: [String] = []
}

@Observable final class JobDefaultsService {
    static let shared = JobDefaultsService()
    private let storage: UserDefaults
    private let storageKey = "fixrecord.jobDefaults.v1"
    var state: JobDefaultsState {
        didSet { if let data = try? JSONEncoder().encode(state) { storage.set(data, forKey: storageKey) } }
    }

    init(storage: UserDefaults = .standard) {
        self.storage = storage
        state = (storage.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(JobDefaultsState.self, from: $0) }) ?? JobDefaultsState()
    }

    func technician(for profile: BusinessProfile?) -> String {
        let choices = [state.defaultTechnician, profile?.ownerName ?? "", state.lastUsedTechnician]
        return choices.map(Self.cleaned).first(where: { !$0.isEmpty }) ?? ""
    }

    func category() -> String {
        switch state.categoryMode {
        case .none: return ""
        case .lastUsed: return selectable(state.lastUsedCategory) ? state.lastUsedCategory : ""
        case .selected: return selectable(state.selectedCategory) ? state.selectedCategory : ""
        }
    }

    func remember(technician: String, category: String) {
        let name = Self.cleaned(technician)
        let category = Self.cleaned(category)
        state.hasRecordedJob = true
        if !name.isEmpty {
            state.lastUsedTechnician = name
            state.recentTechnicians.removeAll { Self.same($0, name) }
            state.recentTechnicians.insert(name, at: 0)
            state.recentTechnicians = Array(state.recentTechnicians.prefix(6))
        }
        state.lastUsedCategory = selectable(category) ? category : ""
    }

    func bootstrap(from jobs: [Job]) {
        guard !state.hasRecordedJob, let latest = jobs.filter({ !$0.isSample }).max(by: { $0.createdAt < $1.createdAt }) else { return }
        let category = Self.cleaned(latest.category)
        if !category.isEmpty && !JobCategories.builtIn.contains(where: { Self.same($0, category) }) {
            _ = addCustomCategory(category)
        }
        remember(technician: latest.technician, category: category)
    }

    @discardableResult func addCustomCategory(_ name: String) -> String? {
        let name = Self.cleaned(name)
        guard !name.isEmpty else { return nil }
        if let builtIn = JobCategories.builtIn.first(where: { Self.same($0, name) }) { return builtIn }
        if let existing = state.customCategories.first(where: { Self.same($0, name) }) { return existing }
        guard !Self.same(name, "Other") else { return nil }
        state.customCategories.append(name)
        return name
    }

    @discardableResult func renameCustomCategory(_ old: String, to new: String) -> Bool {
        let new = Self.cleaned(new)
        guard let index = state.customCategories.firstIndex(where: { Self.same($0, old) }),
              !new.isEmpty, !Self.same(new, "Other"),
              !JobCategories.builtIn.contains(where: { Self.same($0, new) }),
              !state.customCategories.enumerated().contains(where: { $0.offset != index && Self.same($0.element, new) }) else { return false }
        let previous = state.customCategories[index]
        state.customCategories[index] = new
        if Self.same(state.selectedCategory, previous) { state.selectedCategory = new }
        if Self.same(state.lastUsedCategory, previous) { state.lastUsedCategory = new }
        return true
    }

    func deleteCustomCategory(_ name: String) {
        guard let index = state.customCategories.firstIndex(where: { Self.same($0, name) }) else { return }
        let removed = state.customCategories.remove(at: index)
        if Self.same(state.selectedCategory, removed) {
            state.selectedCategory = ""
            state.categoryMode = .lastUsed
        }
        if Self.same(state.lastUsedCategory, removed) { state.lastUsedCategory = "" }
    }

    private func selectable(_ name: String) -> Bool {
        JobCategories.builtIn.contains(where: { Self.same($0, name) }) || state.customCategories.contains(where: { Self.same($0, name) })
    }
    private static func cleaned(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func same(_ first: String, _ second: String) -> Bool { first.caseInsensitiveCompare(second) == .orderedSame }
}

enum JobStatus: String, CaseIterable, Codable { case draft = "Draft", inProgress = "In Progress", completed = "Completed" }
enum PhotoKind: String, Codable { case before, after }

struct JobPhoto: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: PhotoKind
    var filename: String
    var capturedAt = Date()
    var pairedBeforeID: UUID?
    var note = ""
}

struct PriceItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case material, labour, charge }
    var id = UUID()
    var kind: Kind
    var name: String
    var quantity: String = "1"
    var unitPrice: String = "0"
    var sourceReceiptID: UUID?
    var total: Decimal { Money.rounded(Money.parse(quantity) * Money.parse(unitPrice)) }
}

struct ReceiptRecord: Codable, Identifiable {
    var id = UUID()
    var merchant: String
    var date: Date
    var number: String
    var filename: String
    var items: [PriceItem]
    var confirmed: Bool
}

@Model final class Job {
    @Attribute(.unique) var id: UUID
    var number: String
    var title: String
    var clientName: String
    var clientEmail: String
    var clientPhone: String
    var siteAddress: String
    var category: String
    var issue: String
    var technician: String
    var businessName: String
    var createdAt: Date
    var completedAt: Date?
    var statusRaw: String
    var roughNote: String
    var professionalNote: String
    var invoiceNotes: String
    var currencyCode: String
    var taxRate: String
    var discount: String
    var dueDate: Date
    var paid: Bool
    var technicianConfirmed: Bool
    var photosData: Data
    var itemsData: Data
    var receiptsData: Data
    var isSample: Bool

    init(number: String, title: String, clientName: String, siteAddress: String, category: String, issue: String, technician: String, businessName: String, currencyCode: String, taxRate: String, isSample: Bool = false) {
        id = UUID(); self.number = number; self.title = title; self.clientName = clientName
        clientEmail = ""; clientPhone = ""; self.siteAddress = siteAddress; self.category = category
        self.issue = issue; self.technician = technician; self.businessName = businessName
        createdAt = Date(); completedAt = nil; statusRaw = JobStatus.draft.rawValue
        roughNote = ""; professionalNote = ""; invoiceNotes = ""; self.currencyCode = currencyCode
        self.taxRate = taxRate; discount = "0"; dueDate = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
        paid = false; technicianConfirmed = false; photosData = Data(); itemsData = Data(); receiptsData = Data(); self.isSample = isSample
    }
    var status: JobStatus { get { JobStatus(rawValue: statusRaw) ?? .draft } set { statusRaw = newValue.rawValue; completedAt = newValue == .completed ? Date() : nil; if newValue != .completed { technicianConfirmed = false } } }
    var photos: [JobPhoto] { get { (try? JSONDecoder().decode([JobPhoto].self, from: photosData)) ?? [] } set { photosData = (try? JSONEncoder().encode(newValue)) ?? Data() } }
    var items: [PriceItem] { get { (try? JSONDecoder().decode([PriceItem].self, from: itemsData)) ?? [] } set { itemsData = (try? JSONEncoder().encode(newValue)) ?? Data() } }
    var receipts: [ReceiptRecord] { get { (try? JSONDecoder().decode([ReceiptRecord].self, from: receiptsData)) ?? [] } set { receiptsData = (try? JSONEncoder().encode(newValue)) ?? Data() } }
    var summary: String { professionalNote.isEmpty ? roughNote : professionalNote }
}

@Model final class BusinessProfile {
    @Attribute(.unique) var id: UUID
    var businessName: String
    var ownerName: String
    var email: String
    var phone: String
    var address: String
    var taxNumber: String
    var paymentInstructions: String
    var currencyCode: String
    var taxRate: String
    var invoicePrefix: String
    var logoFilename: String
    init() {
        id = UUID(); businessName = ""; ownerName = ""; email = ""; phone = ""; address = ""
        taxNumber = ""; paymentInstructions = ""; currencyCode = Locale.current.currency?.identifier ?? "ZAR"
        taxRate = "0"; invoicePrefix = "FR"; logoFilename = ""
    }
}

enum Money {
    static func decimal(_ value: String) -> Decimal? {
        var normalised = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        if normalised.contains(",") && normalised.contains(".") {
            if normalised.lastIndex(of: ",")! > normalised.lastIndex(of: ".")! {
                normalised = normalised.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else { normalised = normalised.replacingOccurrences(of: ",", with: "") }
        } else if normalised.contains(",") {
            let groups = normalised.split(separator: ",")
            normalised = groups.count > 1 && groups.dropFirst().allSatisfy { $0.count == 3 } ? groups.joined() : normalised.replacingOccurrences(of: ",", with: ".")
        }
        return Decimal(string: normalised, locale: Locale(identifier: "en_US_POSIX"))
    }
    static func parse(_ value: String) -> Decimal { decimal(value) ?? .zero }
    static func isValid(_ value: String) -> Bool { guard let number = decimal(value) else { return false }; return number >= .zero }
    static func rounded(_ value: Decimal) -> Decimal { var input = value; var output = Decimal(); NSDecimalRound(&output, &input, 2, .bankers); return output }
    static func format(_ value: Decimal, currency: String) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.currencyCode = currency
        return formatter.string(from: NSDecimalNumber(decimal: rounded(value))) ?? "\(value) \(currency)"
    }
}

struct InvoiceTotals {
    let materials: Decimal
    let labour: Decimal
    let charges: Decimal
    let subtotal: Decimal
    let discount: Decimal
    let tax: Decimal
    let grandTotal: Decimal
    init(items: [PriceItem], discount: Decimal, taxRate: Decimal) {
        materials = items.filter { $0.kind == .material }.reduce(.zero) { $0 + $1.total }
        labour = items.filter { $0.kind == .labour }.reduce(.zero) { $0 + $1.total }
        charges = items.filter { $0.kind == .charge }.reduce(.zero) { $0 + $1.total }
        subtotal = Money.rounded(materials + labour + charges)
        self.discount = min(Money.rounded(max(discount, .zero)), subtotal)
        tax = Money.rounded((subtotal - self.discount) * max(taxRate, .zero) / 100)
        grandTotal = Money.rounded(subtotal - self.discount + tax)
    }
}

enum PhotoStore {
    static var directory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JobPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    static func save(_ image: UIImage) throws -> String {
        let filename = UUID().uuidString + ".jpg"
        guard image.size.width > 0, image.size.height > 0 else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        let pixelWidth = CGFloat(image.cgImage?.width ?? Int(image.size.width * image.scale))
        let pixelHeight = CGFloat(image.cgImage?.height ?? Int(image.size.height * image.scale))
        let scale = min(1, 2400 / max(pixelWidth, pixelHeight))
        let target = CGSize(width: pixelWidth * scale, height: pixelHeight * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let prepared = scale < 1 ? UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) } : image
        guard let data = prepared.jpegData(compressionQuality: 0.86) else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
        return filename
    }
    static func image(_ filename: String) -> UIImage? {
        let bundledName: String
        switch filename {
        case "sample-before": bundledName = "sample-before-original"
        case "sample-after": bundledName = "sample-after-original"
        default: bundledName = filename
        }
        return UIImage(contentsOfFile: directory.appendingPathComponent(filename).path) ?? UIImage(named: bundledName)
    }
    static func delete(_ filename: String) { try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename)) }
}

enum SampleJob {
    static func make() -> Job {
        let job = Job(number: "FR-DEMO-001", title: "Kitchen Sink Repair", clientName: "Sarah Mitchell", siteAddress: "12 Oak Avenue, Bristol, BS8 2QH", category: "Plumbing", issue: "Leak from kitchen sink pipe.", technician: "Alex Turner", businessName: "Turner Maintenance", currencyCode: "GBP", taxRate: "20", isSample: true)
        job.status = .completed
        let date = Calendar.current.date(from: DateComponents(year: 2025, month: 10, day: 12, hour: 14, minute: 35)) ?? Date()
        job.createdAt = date; job.completedAt = date
        job.dueDate = Calendar.current.date(byAdding: .day, value: 14, to: date) ?? date
        job.roughNote = "Changed connector and washer, tightened everything and tested it. Didn't see any more leaking."
        job.professionalNote = "The damaged connector and washer were replaced and the fittings were tightened. The technician recorded that the connection was tested and no further leakage was observed."
        job.technicianConfirmed = true
        let before = JobPhoto(kind: .before, filename: "sample-before-repair-v2")
        job.photos = [before, JobPhoto(kind: .after, filename: "sample-after-repair-v2", pairedBeforeID: before.id)]
        job.items = [PriceItem(kind: .material, name: "40mm compression connector", quantity: "1", unitPrice: "4.50"), PriceItem(kind: .material, name: "Rubber washer", quantity: "1", unitPrice: "1.20"), PriceItem(kind: .material, name: "Plumber's tape", quantity: "1", unitPrice: "2.00"), PriceItem(kind: .labour, name: "Plumbing labour", quantity: "1.5", unitPrice: "45.00"), PriceItem(kind: .charge, name: "Call-out fee", quantity: "1", unitPrice: "25.00")]
        job.invoiceNotes = "Payment due within 14 days. Please quote the invoice number when paying."
        return job
    }
}
