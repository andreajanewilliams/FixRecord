import SwiftUI
import SwiftData
import PDFKit
import UIKit

enum ExportKind: String, CaseIterable { case report = "Work Report", invoice = "Invoice", pack = "Client Pack" }

struct PDFPreview: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.backgroundColor = .systemGroupedBackground; view.document = PDFDocument(data: data); return view }
    func updateUIView(_ uiView: PDFView, context: Context) { uiView.document = PDFDocument(data: data) }
}

struct ExportView: View {
    @Query private var profiles: [BusinessProfile]
    @Bindable var job: Job
    @State private var kind: ExportKind = .report
    @State private var data = Data()
    @State private var url: URL?
    @State private var error = ""
    @StateObject private var entitlements = EntitlementService.shared
    var body: some View {
        VStack(spacing: 10) {
            Picker("Document", selection: $kind) { ForEach(ExportKind.allCases.filter { $0 != .pack || FeatureAccess.canExportClientPack(isPro: entitlements.isPro) }, id: \.self) { Text($0.rawValue) } }.pickerStyle(.segmented).padding(.horizontal)
            if !entitlements.isPro { Text("Client Pack export is available with Pro. Work Report and Invoice remain free.").font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
            if data.isEmpty { ContentUnavailableView("No preview", systemImage: "doc", description: Text(error)) }
            else { PDFPreview(data: data) }
            if let url { ShareLink(item: url, preview: SharePreview("\(job.number) \(kind.rawValue)")) { Label("Share \(kind.rawValue) PDF", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(12) }.buttonStyle(.borderedProminent).padding(.horizontal) }
        }.navigationTitle("Report & Invoice").navigationBarTitleDisplayMode(.inline)
            .onAppear { render() }.onChange(of: kind) { _, _ in render() }
            .task { await entitlements.refresh() }
    }
    private func render() {
        do {
            data = try PDFMaker.make(kind: kind, job: job, profile: profiles.first)
            let safeName = job.number.replacingOccurrences(of: "/", with: "-")
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName)-\(kind.rawValue.replacingOccurrences(of: " ", with: "-" )).pdf")
            try data.write(to: destination, options: .atomic); url = destination; error = ""
        } catch { data = Data(); url = nil; self.error = error.localizedDescription }
    }
}

enum PDFMaker {
    static let page = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 at 72 pt/in
    static func make(kind: ExportKind, job: Job, profile: BusinessProfile?) throws -> Data {
        guard Money.isValid(job.discount), Money.isValid(job.taxRate), job.items.allSatisfy({ Money.isValid($0.quantity) && Money.isValid($0.unitPrice) }) else {
            throw NSError(domain: "FixRecord", code: 1, userInfo: [NSLocalizedDescriptionKey: "Review the quantity, price, discount and Tax / VAT fields before exporting."])
        }
        if kind != .report && job.items.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw NSError(domain: "FixRecord", code: 2, userInfo: [NSLocalizedDescriptionKey: "Add a description to every invoice item before exporting."])
        }
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            if kind == .report || kind == .pack { drawReport(context: context, job: job, profile: profile) }
            if kind == .invoice || kind == .pack { drawInvoice(context: context, job: job, profile: profile) }
        }
    }
    private static func drawReport(context: UIGraphicsPDFRendererContext, job: Job, profile: BusinessProfile?) {
        context.beginPage(); var y: CGFloat = 48
        header("WORK REPORT", job: job, profile: profile, y: &y)
        labelValue("Job reference", job.number, y: &y)
        labelValue("Client", job.clientName, y: &y)
        labelValue("Site", job.siteAddress, y: &y)
        labelValue("Contractor", job.technician, y: &y)
        labelValue("Created", job.createdAt.formatted(date: .abbreviated, time: .omitted), y: &y)
        if let completed = job.completedAt { labelValue("Completed", completed.formatted(date: .abbreviated, time: .omitted), y: &y) }
        y += 12
        section("ISSUE REPORTED", y: &y)
        paragraph(job.issue.isEmpty ? "No issue description entered." : job.issue, y: &y, context: context)
        section("WORK RECORDED", y: &y)
        paragraph(job.summary.isEmpty ? "No work note entered." : job.summary, y: &y, context: context)
        let before = job.photos.filter { $0.kind == .before }
        let after = job.photos.filter { $0.kind == .after }
        if !before.isEmpty || !after.isEmpty {
            ensure(230, y: &y, context: context); section("BEFORE & AFTER", y: &y)
            for pair in photoPairs(before: before, after: after) {
                ensure(188, y: &y, context: context)
                photo(pair.0, label: "Before", x: 48, y: y)
                photo(pair.1, label: "After", x: 305, y: y)
                y += 180
            }
        }
        let materials = job.items.filter { $0.kind == .material && !$0.name.isEmpty }
        if !materials.isEmpty { ensure(90, y: &y, context: context); section("MATERIALS RECORDED", y: &y); for item in materials { paragraph("\(item.quantity) × \(item.name)", y: &y, context: context) } }
        ensure(90, y: &y, context: context)
        section("TECHNICIAN CONFIRMATION", y: &y)
        paragraph(job.technicianConfirmed ? "The technician confirms this record reflects the work they entered." : "Technician confirmation pending.", y: &y, context: context)
        footer(job: job)
    }
    static func photoPairs(before: [JobPhoto], after: [JobPhoto]) -> [(JobPhoto?, JobPhoto?)] {
        before.flatMap { original -> [(JobPhoto?, JobPhoto?)] in
            let matched = after.filter { $0.pairedBeforeID == original.id }
            return matched.isEmpty ? [(original, nil)] : matched.map { (original, $0) }
        } + after.filter { item in !before.contains(where: { $0.id == item.pairedBeforeID }) }.map { (nil, $0) }
    }
    private static func drawInvoice(context: UIGraphicsPDFRendererContext, job: Job, profile: BusinessProfile?) {
        context.beginPage(); var y: CGFloat = 48
        header("INVOICE", job: job, profile: profile, y: &y)
        labelValue("Invoice no.", job.number, y: &y)
        labelValue("Invoice date", Date().formatted(date: .abbreviated, time: .omitted), y: &y)
        labelValue("Due date", job.dueDate.formatted(date: .abbreviated, time: .omitted), y: &y)
        labelValue("Bill to", job.clientName, y: &y)
        labelValue("Job", job.title + " · " + job.siteAddress, y: &y)
        if job.paid { draw("PAID", at: CGPoint(x: 480, y: 145), font: .boldSystemFont(ofSize: 22), colour: UIColor.systemGreen) }
        y += 24; section("ITEMS", y: &y)
        draw("Description", at: CGPoint(x: 48, y: y), font: .boldSystemFont(ofSize: 10))
        draw("Qty / hours", at: CGPoint(x: 326, y: y), font: .boldSystemFont(ofSize: 10))
        draw("Unit / rate", at: CGPoint(x: 410, y: y), font: .boldSystemFont(ofSize: 10))
        draw("Total", at: CGPoint(x: 515, y: y), font: .boldSystemFont(ofSize: 10)); y += 23
        for item in job.items {
            ensure(32, y: &y, context: context)
            draw(String(item.name.prefix(42)), at: CGPoint(x: 48, y: y))
            draw(item.quantity, at: CGPoint(x: 326, y: y))
            draw(Money.format(Money.parse(item.unitPrice), currency: job.currencyCode), at: CGPoint(x: 410, y: y), font: .systemFont(ofSize: 9))
            draw(Money.format(item.total, currency: job.currencyCode), at: CGPoint(x: 500, y: y), font: .systemFont(ofSize: 9)); y += 29
        }
        let totals = InvoiceTotals(items: job.items, discount: Money.parse(job.discount), taxRate: Money.parse(job.taxRate))
        ensure(230, y: &y, context: context); y += 20
        amount("Subtotal", totals.subtotal, currency: job.currencyCode, y: &y)
        amount("Discount", -totals.discount, currency: job.currencyCode, y: &y)
        amount("Tax / VAT (\(job.taxRate)%)", totals.tax, currency: job.currencyCode, y: &y)
        y += 10; amount("TOTAL", totals.grandTotal, currency: job.currencyCode, y: &y, bold: true)
        if let payment = profile?.paymentInstructions, !payment.isEmpty { y += 26; section("PAYMENT DETAILS", y: &y); paragraph(payment, y: &y, context: context) }
        if !job.invoiceNotes.isEmpty { y += 18; section("NOTES", y: &y); paragraph(job.invoiceNotes, y: &y, context: context) }
        footer(job: job)
    }
    private static func header(_ title: String, job: Job, profile: BusinessProfile?, y: inout CGFloat) {
        let logo = profile.flatMap { PhotoStore.image($0.logoFilename) }
        if let logo { logo.draw(in: CGRect(x: 48, y: y - 2, width: 38, height: 38)) }
        draw(profile?.businessName.isEmpty == false ? profile!.businessName : job.businessName, at: CGPoint(x: logo == nil ? 48 : 96, y: y), font: .boldSystemFont(ofSize: 17), colour: UIColor(red: 0.06, green: 0.17, blue: 0.28, alpha: 1))
        draw(title, at: CGPoint(x: 380, y: y), font: .boldSystemFont(ofSize: 24), colour: UIColor(red: 0.03, green: 0.48, blue: 0.43, alpha: 1))
        y += 29
        let contact = [profile?.address, profile?.email, profile?.phone, profile?.taxNumber].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        draw(String(contact.prefix(105)), at: CGPoint(x: 48, y: y), font: .systemFont(ofSize: 9), colour: .darkGray)
        y += 25; rule(y: y); y += 23
        draw(job.title, at: CGPoint(x: 48, y: y), font: .boldSystemFont(ofSize: 18)); y += 36
    }
    private static func section(_ title: String, y: inout CGFloat) { draw(title, at: CGPoint(x: 48, y: y), font: .boldSystemFont(ofSize: 10), colour: UIColor(red: 0.03, green: 0.48, blue: 0.43, alpha: 1)); y += 23 }
    private static func labelValue(_ label: String, _ value: String, y: inout CGFloat) { draw(label.uppercased(), at: CGPoint(x: 48, y: y), font: .boldSystemFont(ofSize: 9), colour: .darkGray); draw(String(value.prefix(90)), at: CGPoint(x: 158, y: y), font: .systemFont(ofSize: 10)); y += 19 }
    private static func paragraph(_ value: String, y: inout CGFloat, context: UIGraphicsPDFRendererContext) {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.black]
        let rect = NSString(string: value).boundingRect(with: CGSize(width: 499, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
        ensure(rect.height + 8, y: &y, context: context)
        NSString(string: value).draw(in: CGRect(x: 48, y: y, width: 499, height: max(15, rect.height + 2)), withAttributes: attributes)
        y += max(16, rect.height + 9)
    }
    private static func photo(_ value: JobPhoto?, label: String, x: CGFloat, y: CGFloat) {
        draw(label.uppercased(), at: CGPoint(x: x, y: y), font: .boldSystemFont(ofSize: 9), colour: .darkGray)
        guard let value, let image = PhotoStore.image(value.filename) else { return }
        let bounds = CGRect(x: x, y: y + 18, width: 238, height: 148)
        image.draw(in: bounds)
    }
    private static func amount(_ label: String, _ value: Decimal, currency: String, y: inout CGFloat, bold: Bool = false) { draw(label, at: CGPoint(x: 340, y: y), font: bold ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 10)); draw(Money.format(value, currency: currency), at: CGPoint(x: 470, y: y), font: bold ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 10)); y += bold ? 32 : 23 }
    private static func draw(_ text: String, at point: CGPoint, font: UIFont = .systemFont(ofSize: 10), colour: UIColor = .black) { NSString(string: text).draw(at: point, withAttributes: [.font: font, .foregroundColor: colour]) }
    private static func rule(y: CGFloat) { let path = UIBezierPath(); path.move(to: CGPoint(x: 48, y: y)); path.addLine(to: CGPoint(x: 547, y: y)); UIColor.lightGray.setStroke(); path.lineWidth = 0.6; path.stroke() }
    private static func ensure(_ height: CGFloat, y: inout CGFloat, context: UIGraphicsPDFRendererContext) { if y + height > 775 { footer(job: nil); context.beginPage(); y = 52 } }
    private static func footer(job: Job?) { rule(y: 793); draw("FixRecord · Proof the work was done.  \(job?.number ?? "")", at: CGPoint(x: 48, y: 804), font: .systemFont(ofSize: 8), colour: .darkGray) }
}
