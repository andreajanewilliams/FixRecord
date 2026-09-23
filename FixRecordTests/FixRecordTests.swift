import XCTest
import UIKit
@testable import FixRecord

final class FixRecordTests: XCTestCase {
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
        XCTAssertEqual(job.items.count, 3)
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
        let data = try PDFMaker.make(kind: .pack, job: job, profile: nil)
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
        let before = try XCTUnwrap(UIImage(named: "sample-before-original"))
        let after = try XCTUnwrap(UIImage(named: "sample-after-original"))
        let result = MatchShotBridge.compare(before: before, after: after)
        XCTAssertFalse(result.guidance.isEmpty)
        XCTAssertNotNil(PhotoStore.image("sample-before"))
        XCTAssertNotNil(PhotoStore.image("sample-after"))
    }
    func testClientPackEntitlementGate() {
        XCTAssertFalse(FeatureAccess.canExportClientPack(isPro: false))
        XCTAssertTrue(FeatureAccess.canExportClientPack(isPro: true))
    }
    func testPhotoFileRoundTrip() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1000)).image { context in UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1000)) }
        let filename = try PhotoStore.save(image)
        defer { PhotoStore.delete(filename) }
        let saved = try XCTUnwrap(PhotoStore.image(filename))
        XCTAssertLessThanOrEqual(max(saved.size.width, saved.size.height), 2400)
    }
}
