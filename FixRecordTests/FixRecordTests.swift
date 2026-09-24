import XCTest
import UIKit
import PDFKit
import SwiftData
@testable import FixRecord

final class FixRecordTests: XCTestCase {
    private func isolatedDefaults() -> (JobDefaultsService, UserDefaults) {
        let suite = "FixRecordTests.\(UUID().uuidString)"
        let storage = UserDefaults(suiteName: suite)!
        addTeardownBlock { storage.removePersistentDomain(forName: suite) }
        return (JobDefaultsService(storage: storage), storage)
    }

    func testFirstJobHasNoCategoryOrTechnicianDefault() {
        let (defaults, _) = isolatedDefaults()
        XCTAssertEqual(defaults.category(), "")
        XCTAssertEqual(defaults.technician(for: nil), "")
    }

    func testLastUsedCategoryAndTechnicianPersistAcrossLaunches() {
        let (defaults, storage) = isolatedDefaults()
        defaults.remember(technician: "Alex Turner", category: "Plumbing")
        let reopened = JobDefaultsService(storage: storage)
        XCTAssertEqual(reopened.category(), "Plumbing")
        XCTAssertEqual(reopened.technician(for: nil), "Alex Turner")
        XCTAssertEqual(reopened.state.recentTechnicians, ["Alex Turner"])
    }

    func testExistingJobsSeedDefaultsOnceWithoutUsingSampleData() {
        let (defaults, _) = isolatedDefaults()
        let sample = SampleJob.make()
        defaults.bootstrap(from: [sample])
        XCTAssertEqual(defaults.category(), "")
        let existing = SampleJob.make()
        existing.isSample = false
        existing.category = "Appliance Repair"
        existing.technician = "Alex Turner"
        defaults.bootstrap(from: [existing, sample])
        XCTAssertEqual(defaults.category(), "Appliance Repair")
        XCTAssertEqual(defaults.technician(for: nil), "Alex Turner")
        XCTAssertEqual(defaults.state.customCategories, ["Appliance Repair"])
        existing.category = "Plumbing"
        defaults.bootstrap(from: [existing])
        XCTAssertEqual(defaults.category(), "Appliance Repair")
    }

    func testExplicitDefaultsOutrankBusinessProfileAndOneOffJobValues() {
        let (defaults, _) = isolatedDefaults()
        let profile = BusinessProfile()
        profile.ownerName = "Alex Turner"
        defaults.remember(technician: "James Wilson", category: "Electrical")
        XCTAssertEqual(defaults.technician(for: profile), "Alex Turner")
        defaults.state.defaultTechnician = "Sarah Ngwenya"
        defaults.state.selectedCategory = "Maintenance"
        defaults.state.categoryMode = .selected
        defaults.remember(technician: "James Wilson", category: "Plumbing")
        XCTAssertEqual(defaults.technician(for: profile), "Sarah Ngwenya")
        XCTAssertEqual(defaults.category(), "Maintenance")
        XCTAssertEqual(defaults.state.lastUsedCategory, "Plumbing")
    }

    func testCategoryModeCanBeNoneOrLastUsed() {
        let (defaults, _) = isolatedDefaults()
        defaults.remember(technician: "", category: "HVAC")
        defaults.state.categoryMode = .none
        XCTAssertEqual(defaults.category(), "")
        defaults.state.categoryMode = .lastUsed
        XCTAssertEqual(defaults.category(), "HVAC")
    }

    func testCustomCategoryCanBecomeDefaultAndSurvivesRename() {
        let (defaults, _) = isolatedDefaults()
        XCTAssertEqual(defaults.addCustomCategory("Appliance Repair"), "Appliance Repair")
        XCTAssertEqual(defaults.state.customCategories, ["Appliance Repair"])
        defaults.state.categoryMode = .selected
        defaults.state.selectedCategory = "Appliance Repair"
        XCTAssertEqual(defaults.category(), "Appliance Repair")
        XCTAssertTrue(defaults.renameCustomCategory("Appliance Repair", to: "Appliance Service"))
        XCTAssertEqual(defaults.category(), "Appliance Service")
        XCTAssertFalse(defaults.renameCustomCategory("Appliance Service", to: "Plumbing"))
    }

    func testDeletingCustomCategoryKeepsHistoricalJobValue() {
        let (defaults, _) = isolatedDefaults()
        let job = SampleJob.make()
        job.category = defaults.addCustomCategory("Appliance Repair")!
        defaults.remember(technician: job.technician, category: job.category)
        defaults.state.categoryMode = .selected
        defaults.state.selectedCategory = job.category
        defaults.deleteCustomCategory("Appliance Repair")
        XCTAssertEqual(job.category, "Appliance Repair")
        XCTAssertEqual(defaults.state.categoryMode, .lastUsed)
        XCTAssertEqual(defaults.category(), "")
        XCTAssertTrue(defaults.state.customCategories.isEmpty)
    }

    func testExistingJobKeepsItsOwnCategoryAndTechnician() {
        let (defaults, _) = isolatedDefaults()
        let job = SampleJob.make()
        job.category = "Inspection"
        job.technician = "Alex Turner"
        defaults.state.defaultTechnician = "James Wilson"
        defaults.state.selectedCategory = "Plumbing"
        defaults.state.categoryMode = .selected
        _ = defaults.technician(for: nil)
        _ = defaults.category()
        XCTAssertEqual(job.technician, "Alex Turner")
        XCTAssertEqual(job.category, "Inspection")
    }

    func testDecimalInvoiceTotals() {
        let items = [PriceItem(kind: .material, name: "Part", quantity: "3", unitPrice: "8.50"), PriceItem(kind: .labour, name: "Labour", quantity: "1.5", unitPrice: "80")]
        let totals = InvoiceTotals(items: items, discount: Decimal(5), taxRate: Decimal(15))
        XCTAssertEqual(totals.subtotal, Decimal(string: "145.50"))
        XCTAssertEqual(totals.tax, Decimal(string: "21.08"))
        XCTAssertEqual(totals.grandTotal, Decimal(string: "161.58"))
    }
    func testDiscountCannotMakeNegativeTotal() {
        let totals = InvoiceTotals(items: [PriceItem(kind: .charge, name: "Call-out", unitPrice: "10")], discount: Decimal(100), taxRate: Decimal(15))
        XCTAssertEqual(totals.grandTotal, .zero)
    }
    func testInvoiceLinesReconcileAtCurrencyPrecision() {
        let items = [PriceItem(kind: .material, name: "Part A", unitPrice: "0.005"), PriceItem(kind: .material, name: "Part B", unitPrice: "0.005")]
        let totals = InvoiceTotals(items: items, discount: Decimal(string: "0.005")!, taxRate: .zero)
        XCTAssertEqual(items[0].total + items[1].total, totals.subtotal)
        XCTAssertEqual(totals.subtotal, .zero)
        XCTAssertEqual(totals.discount, .zero)
        XCTAssertEqual(totals.grandTotal, .zero)
    }
    func testInvoiceRejectsUnnamedBilledItem() throws {
        let job = SampleJob.make()
        job.items.append(PriceItem(kind: .charge, name: "  ", unitPrice: "12"))
        XCTAssertThrowsError(try PDFMaker.make(kind: .invoice, job: job, profile: nil))
        XCTAssertNoThrow(try PDFMaker.make(kind: .report, job: job, profile: nil))
    }
    func testWorkReportCanExportWithUnfinishedInvoicePrices() throws {
        let job = SampleJob.make()
        job.items = [PriceItem(kind: .material, name: "Connector", unitPrice: "not entered")]
        XCTAssertNoThrow(try PDFMaker.make(kind: .report, job: job, profile: nil))
        XCTAssertThrowsError(try PDFMaker.make(kind: .invoice, job: job, profile: nil))
        var pricedReport = DocumentOptions()
        pricedReport.showPricesInReport = true
        XCTAssertThrowsError(try PDFMaker.make(kind: .report, job: job, profile: nil, options: pricedReport))
    }
    func testReportOnlyNamesConfirmedCompletedTechnician() throws {
        let job = SampleJob.make()
        job.technicianConfirmed = false
        let unconfirmed = try XCTUnwrap(PDFDocument(data: PDFMaker.make(kind: .report, job: job, profile: nil)))
        XCTAssertFalse((unconfirmed.string ?? "").contains("COMPLETED BY"))
        job.technicianConfirmed = true
        job.status = .inProgress
        XCTAssertFalse(job.technicianConfirmed)
        let draft = try XCTUnwrap(PDFDocument(data: PDFMaker.make(kind: .report, job: job, profile: nil)))
        XCTAssertFalse((draft.string ?? "").contains("COMPLETED BY"))
    }
    func testPhotoFreeWorkReportUsesTextLayout() throws {
        let job = SampleJob.make()
        job.photos = []
        var options = DocumentOptions()
        options.showPricesInReport = true
        let report = try XCTUnwrap(PDFDocument(data: PDFMaker.make(kind: .report, job: job, profile: nil, options: options)))
        let content = report.string ?? ""
        XCTAssertEqual(report.pageCount, 1)
        XCTAssertTrue(content.contains("Work Report"))
        XCTAssertTrue(content.contains("Materials Used"))
        XCTAssertTrue(content.contains("UNIT PRICE"))
        XCTAssertFalse(content.contains("BEFORE"))
        XCTAssertFalse(content.contains("AFTER"))
    }
    func testPhotosCanBeHiddenWithoutRemovingThemFromJob() throws {
        let job = SampleJob.make()
        let report = try XCTUnwrap(PDFDocument(data: PDFMaker.make(kind: .report, job: job, profile: nil, includePhotos: false)))
        XCTAssertEqual(job.photos.count, 2)
        XCTAssertFalse((report.string ?? "").contains("BEFORE"))
    }
    func testSinglePhotoDoesNotCreateEmptyPartnerPanel() throws {
        let job = SampleJob.make()
        job.photos = job.photos.filter { $0.kind == .before }
        let report = try XCTUnwrap(PDFDocument(data: PDFMaker.make(kind: .report, job: job, profile: nil)))
        XCTAssertTrue((report.string ?? "").contains("BEFORE"))
        XCTAssertFalse((report.string ?? "").contains("AFTER"))
    }
    func testInvoiceIncludesBusinessTaxNumber() throws {
        let profile = BusinessProfile()
        profile.businessName = "Turner Maintenance"
        profile.address = "Workshop 12, Industrial Estate\nLong Market Street\nBristol BS8 2QH"
        profile.phone = "07123 456789"
        profile.email = "hello@example.com"
        profile.taxNumber = "GB123456789"
        let invoice = try XCTUnwrap(PDFDocument(data: PDFMaker.make(kind: .invoice, job: SampleJob.make(), profile: profile)))
        XCTAssertTrue((invoice.string ?? "").contains("GB123456789"))
        XCTAssertEqual(invoice.pageCount, 1)
    }
    func testAllPairedAfterPhotosAppearInReportPlan() {
        let before = JobPhoto(kind: .before, filename: "before")
        let first = JobPhoto(kind: .after, filename: "after-1", pairedBeforeID: before.id)
        let second = JobPhoto(kind: .after, filename: "after-2", pairedBeforeID: before.id)
        let unmatched = JobPhoto(kind: .after, filename: "after-3")
        let pairs = PDFMaker.photoPairs(before: [before], after: [first, second, unmatched])
        XCTAssertEqual(pairs.map { $0.1?.id }, [first.id, second.id, unmatched.id])
        XCTAssertEqual(pairs.map { $0.0?.id }, [before.id, before.id, nil])
    }
    func testMoneyInputValidation() throws {
        XCTAssertEqual(Money.decimal("1,234.50"), Decimal(string: "1234.50"))
        XCTAssertEqual(Money.decimal("1.234,50"), Decimal(string: "1234.50"))
        XCTAssertFalse(Money.isValid("not a price"))
        let job = SampleJob.make(); job.items = [PriceItem(kind: .material, name: "Part", unitPrice: "bad")]
        XCTAssertThrowsError(try PDFMaker.make(kind: .invoice, job: job, profile: nil))
    }
    func testStatusTransitionAndSampleMapping() {
        let job = SampleJob.make()
        XCTAssertEqual(job.status, .completed)
        XCTAssertNotNil(job.completedAt)
        XCTAssertEqual(job.photos.count, 2)
        XCTAssertEqual(job.items.count, 5)
        job.status = .inProgress
        XCTAssertNil(job.completedAt)
    }
    func testReceiptParserExcludesTotals() {
        let result = ReceiptParser.parse(["Hardware Shop", "2026-09-23", "PVC Connector 8.50", "TOTAL 8.50"])
        XCTAssertEqual(result.merchant, "Hardware Shop")
        XCTAssertEqual(result.items.count, 1)
        XCTAssertNotNil(result.date)
        XCTAssertEqual(result.total, "8.50")
    }
    func testPDFAndAIFallbackDecoding() throws {
        let job = SampleJob.make()
        let data = try PDFMaker.make(kind: .pack, job: job, profile: nil, isPro: true)
        XCTAssertFalse(data.isEmpty)
        let response = try JSONDecoder().decode(AIResponse.self, from: Data(#"{"reportedIssue":"issue","workCompleted":"work","completionNotes":"note","professionalSummary":"summary"}"#.utf8))
        XCTAssertEqual(response.professionalSummary, "summary")
    }
    func testMatchShotLowConfidenceIsNeutral() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120))
        let blank = renderer.image { context in UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 120, height: 120)) }
        let result = MatchShotBridge.compare(before: blank, after: blank)
        XCTAssertFalse(result.confident)
        XCTAssertTrue(result.guidance.contains("uncertain"))
    }
    func testMatchShotSamplePairProducesGuidance() throws {
        let before = try XCTUnwrap(UIImage(named: "sample-before-repair-v2"))
        let after = try XCTUnwrap(UIImage(named: "sample-after-repair-v2"))
        let result = MatchShotBridge.compare(before: before, after: after)
        XCTAssertFalse(result.guidance.isEmpty)
        XCTAssertNotNil(PhotoStore.image("sample-before"))
        XCTAssertNotNil(PhotoStore.image("sample-after"))
    }
    func testClientPackEntitlementGate() {
        XCTAssertFalse(FeatureAccess.canExportClientPack(isPro: false))
        XCTAssertTrue(FeatureAccess.canExportClientPack(isPro: true))
        XCTAssertThrowsError(try PDFMaker.make(kind: .pack, job: SampleJob.make(), profile: nil))
    }

    func testSampleTotalsAndOptionalInvoiceSections() throws {
        let job = SampleJob.make()
        let totals = InvoiceTotals(items: job.items, discount: 0, taxRate: 20)
        XCTAssertEqual(totals.materials, Decimal(string: "7.70"))
        XCTAssertEqual(totals.labour, Decimal(string: "67.50"))
        XCTAssertEqual(totals.charges, Decimal(string: "25.00"))
        XCTAssertEqual(totals.grandTotal, Decimal(string: "120.24"))
        var options = DocumentOptions()
        options.showTax = false; options.showDueDate = false; options.showTerms = false
        let data = try PDFMaker.make(kind: .invoice, job: job, profile: nil, options: options)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let words = pdf.string ?? ""
        XCTAssertTrue(words.contains("TOTAL DUE"))
        XCTAssertFalse(words.contains("Tax / VAT"))
        XCTAssertFalse(words.contains("Payment due within"))
    }

    func testFreeBrandingAndProOptionalReportSections() throws {
        let job = SampleJob.make()
        var options = DocumentOptions()
        options.showFixRecordBranding = false
        options.showReportedIssue = false
        options.showMaterials = false
        let free = try XCTUnwrap(PDFDocument(data: PDFMaker.make(kind: .report, job: job, profile: nil, options: options)))
        let pro = try XCTUnwrap(PDFDocument(data: PDFMaker.make(kind: .report, job: job, profile: nil, options: options, isPro: true)))
        XCTAssertTrue((free.string ?? "").contains("Generated with FixRecord"))
        XCTAssertFalse((pro.string ?? "").contains("Generated with FixRecord"))
        XCTAssertFalse((pro.string ?? "").contains("REPORTED ISSUE"))
        XCTAssertFalse((pro.string ?? "").contains("MATERIALS USED"))
        XCTAssertTrue((pro.string ?? "").contains("WORK COMPLETED"))
    }

    func testReceiptReviewRejectsIncompleteItems() {
        let parsed = ReceiptParser.parse(["Builders Warehouse", "2026-09-24", "PVC Connector 40mm 89.99", "Rubber Washer 12.50", "TOTAL 102.49"])
        XCTAssertEqual(parsed.items.count, 2)
        XCTAssertTrue(ReceiptParser.canConfirm(parsed.items))
        var incomplete = parsed.items
        incomplete[0].unitPrice = "bad"
        XCTAssertFalse(ReceiptParser.canConfirm(incomplete))
    }

    func testJobSurvivesSwiftDataSave() throws {
        let container = try ModelContainer(for: Job.self, BusinessProfile.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let writer = ModelContext(container)
        let job = SampleJob.make()
        writer.insert(job)
        try writer.save()
        let reader = ModelContext(container)
        let loaded = try XCTUnwrap(reader.fetch(FetchDescriptor<Job>()).first)
        XCTAssertEqual(loaded.title, "Kitchen Sink Repair")
        XCTAssertEqual(loaded.photos.count, 2)
        XCTAssertEqual(loaded.items.count, 5)
    }
    func testPhotoFileRoundTrip() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1000)).image { context in UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1000)) }
        let filename = try PhotoStore.save(image)
        defer { PhotoStore.delete(filename) }
        let saved = try XCTUnwrap(PhotoStore.image(filename))
        XCTAssertLessThanOrEqual(max(saved.size.width, saved.size.height), 2400)
    }
}
