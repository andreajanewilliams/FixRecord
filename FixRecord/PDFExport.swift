import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers
import UIKit

enum ExportKind: String, CaseIterable { case report = "Work Report", invoice = "Invoice", pack = "Client Pack" }

struct PDFPreview: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.backgroundColor = .systemGroupedBackground
        view.document = PDFDocument(data: data); return view
    }
    func updateUIView(_ view: PDFView, context: Context) { view.document = PDFDocument(data: data) }
}

struct PDFFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct ExportView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [BusinessProfile]
    @Bindable var job: Job
    @State private var kind: ExportKind = .report
    @State private var data = Data()
    @State private var url: URL?
    @State private var packURL: URL?
    @State private var error = ""
    @State private var showingShare = false
    @State private var showingUpgrade = false
    @State private var showingBusiness = false
    @State private var dismissedBusinessPrompt = false
    @StateObject private var entitlements = EntitlementService.shared
    private var profile: BusinessProfile? { profiles.first }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Document", selection: $kind) { ForEach(ExportKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).padding(.horizontal)
            if profile?.businessName.isEmpty != false && !dismissedBusinessPrompt {
                HStack {
                    VStack(alignment: .leading, spacing: 3) { Text("Personalise your documents").font(.subheadline.bold()); Text("Add your business details.").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Add Details") { if profile == nil { context.insert(BusinessProfile()) }; showingBusiness = true }.font(.caption.bold())
                    Button("Not Now") { dismissedBusinessPrompt = true }.font(.caption)
                }.padding(10).background(Brand.pale, in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal)
            }
            if kind == .pack && !entitlements.isPro {
                ContentUnavailableView("Client Pack is Pro", systemImage: "lock.doc", description: Text("Work Reports and Invoices remain free."))
                Button("Upgrade to Pro") { showingUpgrade = true }.buttonStyle(.borderedProminent)
            } else if data.isEmpty {
                ContentUnavailableView("No preview", systemImage: "doc", description: Text(error))
            } else { PDFPreview(data: data) }
            HStack(spacing: 12) {
                NavigationLink { kind == .invoice ? AnyView(PricingView(job: job)) : AnyView(NotesView(job: job)) } label: { Text("Edit").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                Button("Export") { showingShare = true }.frame(maxWidth: .infinity).buttonStyle(.borderedProminent).disabled(url == nil)
            }.padding(.horizontal)
            NavigationLink("Edit Template") { TemplatesView() }.font(.caption).padding(.bottom, 6)
        }
        .navigationTitle("Preview").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingShare) { if let url { NavigationStack { ShareOptionsView(url: url, packURL: packURL, data: data, title: job.number) } } }
        .sheet(isPresented: $showingUpgrade) { NavigationStack { UpgradeView() } }
        .sheet(isPresented: $showingBusiness) { if let profile { NavigationStack { BusinessProfileView(profile: profile) } } }
        .onAppear { render() }
        .onChange(of: kind) { _, _ in render() }
        .task { await entitlements.refresh(); render() }
        .onChange(of: entitlements.isPro) { _, _ in render() }
        .onChange(of: showingBusiness) { _, showing in if !showing { render() } }
    }
    private func render() {
        guard kind != .pack || entitlements.isPro else { data = Data(); url = nil; return }
        do {
            let options = DocumentOptions.load()
            data = try PDFMaker.make(kind: kind, job: job, profile: profile, options: options, isPro: entitlements.isPro)
            url = try exportURL(for: data, label: kind.rawValue)
            if entitlements.isPro {
                let pack = try PDFMaker.make(kind: .pack, job: job, profile: profile, options: options, isPro: true)
                packURL = try exportURL(for: pack, label: "Client Pack")
            } else { packURL = nil }
            error = ""
        } catch { data = Data(); url = nil; packURL = nil; self.error = error.localizedDescription }
    }
    private func exportURL(for data: Data, label: String) throws -> URL {
        let safeName = job.number.replacingOccurrences(of: "/", with: "-")
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName)-\(label.replacingOccurrences(of: " ", with: "-")).pdf")
        try data.write(to: destination, options: .atomic)
        return destination
    }
}

struct ShareOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let packURL: URL?
    let data: Data
    let title: String
    @State private var saveToFiles = false
    var body: some View {
        List {
            ShareLink(item: url) { Label("Share PDF", systemImage: "square.and.arrow.up") }
            Button { saveToFiles = true } label: { Label("Save to Files", systemImage: "folder") }
            Button { let printer = UIPrintInteractionController.shared; printer.printingItem = data; printer.present(animated: true) } label: { Label("Print", systemImage: "printer") }
            if let packURL { ShareLink(item: packURL) { Label("Share Both Documents", systemImage: "square.stack") } }
        }.navigationTitle("Share").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .fileExporter(isPresented: $saveToFiles, document: PDFFileDocument(data: data), contentType: .pdf, defaultFilename: title) { _ in }
    }
}

enum PDFMaker {
    static let page = CGRect(x: 0, y: 0, width: 595, height: 842)
    private static let navy = UIColor(red: 0.07, green: 0.14, blue: 0.25, alpha: 1)
    private static let blue = UIColor(red: 0.04, green: 0.37, blue: 0.89, alpha: 1)
    private static let pale = UIColor(red: 0.93, green: 0.96, blue: 0.99, alpha: 1)
    private static let green = UIColor(red: 0.07, green: 0.56, blue: 0.40, alpha: 1)
    private static let margin: CGFloat = 44
    private static let contentWidth: CGFloat = 507

    static func make(kind: ExportKind, job: Job, profile: BusinessProfile?, options: DocumentOptions = DocumentOptions(), isPro: Bool = false) throws -> Data {
        guard kind != .pack || isPro else {
            throw NSError(domain: "FixRecord", code: 3, userInfo: [NSLocalizedDescriptionKey: "Client Pack requires Pro."])
        }
        let effective = options.effective(isPro: isPro)
        let pricedItems = kind == .report ? job.items.filter { $0.kind == .material && effective.showPricesInReport } : job.items
        guard (kind == .report || (Money.isValid(job.discount) && Money.isValid(job.taxRate))) && pricedItems.allSatisfy({ Money.isValid($0.quantity) && Money.isValid($0.unitPrice) }) else {
            throw NSError(domain: "FixRecord", code: 1, userInfo: [NSLocalizedDescriptionKey: "Review quantity, price, discount and Tax / VAT before exporting."])
        }
        if kind != .report && job.items.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw NSError(domain: "FixRecord", code: 2, userInfo: [NSLocalizedDescriptionKey: "Add a description to every invoice item before exporting."])
        }
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            if kind == .report || kind == .pack { drawReport(context, job: job, profile: profile, options: effective) }
            if kind == .invoice || kind == .pack { drawInvoice(context, job: job, profile: profile, options: effective) }
        }
    }

    static func photoPairs(before: [JobPhoto], after: [JobPhoto]) -> [(JobPhoto?, JobPhoto?)] {
        before.flatMap { original -> [(JobPhoto?, JobPhoto?)] in
            let matched = after.filter { $0.pairedBeforeID == original.id }
            return matched.isEmpty ? [(original, nil)] : matched.map { (original, $0) }
        } + after.filter { item in !before.contains(where: { $0.id == item.pairedBeforeID }) }.map { (nil, $0) }
    }

    private static func drawReport(_ context: UIGraphicsPDFRendererContext, job: Job, profile: BusinessProfile?, options: DocumentOptions) {
        context.beginPage()
        var y = header("WORK REPORT", job: job, profile: profile, options: options)
        text(job.title, x: margin, y: y, width: contentWidth, size: 22, bold: true, colour: navy); y += 32
        text("Job #\(job.number)  |  \((job.completedAt ?? job.createdAt).formatted(date: .abbreviated, time: .omitted))", x: margin, y: y, width: contentWidth, size: 10, colour: .darkGray); y += 26
        let cellWidth = (contentWidth - 16) / 3
        for (index, pair) in [("CLIENT", job.clientName), ("PROPERTY / SITE", job.siteAddress), ("TECHNICIAN", job.technician)].enumerated() {
            let x = margin + CGFloat(index) * (cellWidth + 8)
            panel(CGRect(x: x, y: y, width: cellWidth, height: 63), template: options.template)
            text(pair.0, x: x + 9, y: y + 10, width: cellWidth - 18, size: 8, bold: true, colour: navy)
            text(pair.1, x: x + 9, y: y + 28, width: cellWidth - 18, height: 30, size: 10, colour: navy, wrap: true)
        }
        y += 77
        if options.showReportedIssue && !job.issue.isEmpty {
            section("REPORTED ISSUE", y: &y)
            paragraph(job.issue, y: &y, context: context, options: options)
        }
        let before = job.photos.filter { $0.kind == .before }
        let after = job.photos.filter { $0.kind == .after }
        for pair in photoPairs(before: before, after: after) {
            ensure(205, y: &y, context: context, options: options)
            photo(pair.0, title: "BEFORE", x: margin, y: y)
            photo(pair.1, title: "AFTER", x: margin + 258, y: y)
            y += 201
        }
        if !job.summary.isEmpty {
            section("WORK COMPLETED", y: &y)
            paragraph(job.summary, y: &y, context: context, options: options)
        }
        let materials = job.items.filter { $0.kind == .material && !$0.name.isEmpty }
        if options.showMaterials && !materials.isEmpty {
            section("MATERIALS USED", y: &y)
            for item in materials {
                ensure(20, y: &y, context: context, options: options)
                let price = options.showPricesInReport ? "   ·   \(Money.format(item.total, currency: job.currencyCode))" : ""
                text("•  \(item.name) (×\(item.quantity))\(price)", x: margin + 4, y: y, width: contentWidth - 8, size: 10)
                y += 19
            }
            y += 5
        }
        if options.showTechnicianConfirmation && job.status == .completed && job.technicianConfirmed && !job.technician.isEmpty {
            section("COMPLETED BY", y: &y)
            let detail = [job.technician, profile?.businessName ?? job.businessName, job.completedAt?.formatted(date: .abbreviated, time: .shortened) ?? ""].filter { !$0.isEmpty }.joined(separator: "  ·  ")
            paragraph(detail, y: &y, context: context, options: options)
        }
        if options.showClientAcknowledgement {
            ensure(64, y: &y, context: context, options: options)
            section("CLIENT ACKNOWLEDGEMENT (OPTIONAL)", y: &y)
            text("Name: ____________________    Signature: ____________________    Date: __________", x: margin, y: y, width: contentWidth, size: 9); y += 25
        }
        if options.showAdditionalNotes && !job.invoiceNotes.isEmpty { section("ADDITIONAL NOTES", y: &y); paragraph(job.invoiceNotes, y: &y, context: context, options: options) }
        footer(job: job, options: options)
    }

    private static func drawInvoice(_ context: UIGraphicsPDFRendererContext, job: Job, profile: BusinessProfile?, options: DocumentOptions) {
        context.beginPage()
        var y = header("INVOICE", job: job, profile: profile, options: options)
        text("INVOICE", x: margin, y: y, width: 300, size: 28, bold: true, colour: navy)
        text("Invoice #\(job.number)", x: 360, y: y + 2, width: 190, size: 11, bold: true, colour: navy)
        y += 37
        text("Issued \(job.createdAt.formatted(date: .abbreviated, time: .omitted))", x: margin, y: y, width: 250, size: 10)
        if options.showDueDate { text("Due \(job.dueDate.formatted(date: .abbreviated, time: .omitted))", x: 360, y: y, width: 190, size: 10) }
        y += 25
        let half = (contentWidth - 10) / 2
        let billTo = [job.clientName, job.siteAddress, job.clientEmail].filter { !$0.isEmpty }.joined(separator: "\n")
        var fromDetails = [profile?.businessName ?? job.businessName]
        if options.showBusinessDetails {
            fromDetails += [profile?.taxNumber.isEmpty == false ? "Tax / VAT: \(profile!.taxNumber)" : nil, profile?.address, profile?.phone, profile?.email].compactMap { $0 }
        }
        let from = fromDetails.filter { !$0.isEmpty }.joined(separator: "\n")
        let textWidth = half - 20
        let paragraphFont = UIFont.systemFont(ofSize: 10)
        let textHeight = max(NSString(string: billTo).boundingRect(with: CGSize(width: textWidth, height: 600), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: paragraphFont], context: nil).height,
                             NSString(string: from).boundingRect(with: CGSize(width: textWidth, height: 600), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: paragraphFont], context: nil).height)
        let panelHeight = max(102, ceil(textHeight) + 35)
        panel(CGRect(x: margin, y: y, width: half, height: panelHeight), template: options.template)
        panel(CGRect(x: margin + half + 10, y: y, width: half, height: panelHeight), template: options.template)
        text("BILL TO", x: margin + 10, y: y + 10, width: half - 20, size: 9, bold: true, colour: navy)
        text(billTo, x: margin + 10, y: y + 27, width: textWidth, height: panelHeight - 31, size: 10, wrap: true)
        text("FROM", x: margin + half + 20, y: y + 10, width: half - 20, size: 9, bold: true, colour: navy)
        text(from, x: margin + half + 20, y: y + 27, width: textWidth, height: panelHeight - 31, size: 10, wrap: true)
        y += panelHeight + 14
        text("Job reference: \(job.number)  ·  \(job.title)", x: margin, y: y, width: contentWidth, size: 10, colour: .darkGray)
        if job.paid { text("PAID", x: 500, y: y, width: 50, size: 10, bold: true, colour: green) }
        y += 26
        tableHeader(y: &y, template: options.template)
        for (kind, heading) in [(PriceItem.Kind.material, "MATERIALS"), (.labour, "LABOUR"), (.charge, "ADDITIONAL CHARGES")] {
            let items = job.items.filter { $0.kind == kind }
            guard !items.isEmpty else { continue }
            ensure(27, y: &y, context: context, options: options)
            fill(CGRect(x: margin, y: y, width: contentWidth, height: 20), colour: pale)
            text(heading, x: margin + 7, y: y + 4, width: 280, size: 8, bold: true, colour: navy); y += 21
            for item in items {
                ensure(27, y: &y, context: context, options: options)
                text(item.name, x: margin + 7, y: y + 6, width: 250, size: 9)
                text(item.quantity, x: 314, y: y + 6, width: 45, size: 9)
                text(Money.format(Money.parse(item.unitPrice), currency: job.currencyCode), x: 376, y: y + 6, width: 80, size: 9)
                text(Money.format(item.total, currency: job.currencyCode), x: 462, y: y + 6, width: 85, size: 9, alignment: .right)
                line(y + 26); y += 27
            }
        }
        let totals = InvoiceTotals(items: job.items, discount: options.showDiscount ? Money.parse(job.discount) : 0, taxRate: options.showTax ? Money.parse(job.taxRate) : 0)
        ensure(145, y: &y, context: context, options: options); y += 17
        amount("Subtotal", totals.subtotal, currency: job.currencyCode, y: &y)
        if options.showDiscount && totals.discount > 0 { amount("Discount", -totals.discount, currency: job.currencyCode, y: &y) }
        if options.showTax && totals.tax > 0 { amount("Tax / VAT (\(job.taxRate)%)", totals.tax, currency: job.currencyCode, y: &y) }
        fill(CGRect(x: 333, y: y + 2, width: 218, height: 33), colour: pale)
        amount("TOTAL DUE", totals.grandTotal, currency: job.currencyCode, y: &y, bold: true)
        if options.showPaymentInstructions, let payment = profile?.paymentInstructions, !payment.isEmpty {
            y += 15; section("PAYMENT DETAILS", y: &y); paragraph(payment, y: &y, context: context, options: options)
        }
        if options.showTerms && !job.invoiceNotes.isEmpty {
            y += 10; section("TERMS & NOTES", y: &y); paragraph(job.invoiceNotes, y: &y, context: context, options: options)
        }
        footer(job: job, options: options)
    }

    private static func header(_ title: String, job: Job, profile: BusinessProfile?, options: DocumentOptions) -> CGFloat {
        var nameX = margin
        if options.showLogo, let logo = profile.flatMap({ PhotoStore.image($0.logoFilename) }) {
            aspectFill(logo, in: CGRect(x: margin, y: 39, width: 43, height: 43)); nameX += 54
        }
        let businessName = profile?.businessName.isEmpty == false ? profile!.businessName : job.businessName
        text(businessName.isEmpty ? "Your Business" : businessName, x: nameX, y: 42, width: 290, size: 18, bold: true, colour: navy)
        if options.showBusinessDetails {
            let contact = [profile?.phone, profile?.email, profile?.address, title == "INVOICE" && profile?.taxNumber.isEmpty == false ? "Tax / VAT: \(profile!.taxNumber)" : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
            text(contact, x: nameX, y: 67, width: 360, size: 8, colour: .darkGray)
        }
        text(title, x: 405, y: 45, width: 144, size: 9, bold: true, colour: blue, alignment: .right)
        line(96)
        return 111
    }

    private static func photo(_ value: JobPhoto?, title: String, x: CGFloat, y: CGFloat) {
        let box = CGRect(x: x, y: y, width: 249, height: 187)
        if let value, let image = PhotoStore.image(value.filename) { aspectFill(image, in: box) }
        else { fill(box, colour: pale); text("No photo", x: x + 20, y: y + 82, width: 209, size: 11, colour: .gray, alignment: .center) }
        fill(CGRect(x: x, y: y, width: 66, height: 23), colour: title == "AFTER" ? green : navy)
        text(title, x: x + 8, y: y + 5, width: 55, size: 9, bold: true, colour: .white)
    }

    private static func section(_ title: String, y: inout CGFloat) {
        text(title, x: margin, y: y, width: contentWidth, size: 10, bold: true, colour: navy); y += 18
    }
    private static func paragraph(_ value: String, y: inout CGFloat, context: UIGraphicsPDFRendererContext, options: DocumentOptions) {
        let words = value.split(separator: " ")
        var chunks: [String] = []; var current = ""
        for word in words {
            if current.count + word.count > 450 && !current.isEmpty { chunks.append(current); current = "" }
            current += (current.isEmpty ? "" : " ") + word
        }
        if !current.isEmpty { chunks.append(current) }
        for chunk in chunks {
            let font = UIFont.systemFont(ofSize: 10)
            let height = ceil(NSString(string: chunk).boundingRect(with: CGSize(width: contentWidth, height: 600), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil).height) + 5
            ensure(height + 8, y: &y, context: context, options: options)
            text(chunk, x: margin, y: y, width: contentWidth, height: height, size: 10, wrap: true)
            y += height + 8
        }
    }
    private static func tableHeader(y: inout CGFloat, template: DocumentTemplate) {
        fill(CGRect(x: margin, y: y, width: contentWidth, height: 29), colour: template == .minimal ? pale : navy)
        let colour: UIColor = template == .minimal ? navy : .white
        text("DESCRIPTION", x: margin + 7, y: y + 9, width: 240, size: 8, bold: true, colour: colour)
        text("QTY / HOURS", x: 314, y: y + 9, width: 63, size: 8, bold: true, colour: colour)
        text("RATE", x: 386, y: y + 9, width: 65, size: 8, bold: true, colour: colour)
        text("AMOUNT", x: 474, y: y + 9, width: 72, size: 8, bold: true, colour: colour, alignment: .right)
        y += 29
    }
    private static func amount(_ title: String, _ value: Decimal, currency: String, y: inout CGFloat, bold: Bool = false) {
        text(title, x: 344, y: y + 7, width: 105, size: bold ? 12 : 10, bold: bold, colour: navy)
        text(Money.format(value, currency: currency), x: 453, y: y + 7, width: 94, size: bold ? 12 : 10, bold: bold, colour: navy, alignment: .right)
        y += bold ? 38 : 24
    }
    private static func ensure(_ height: CGFloat, y: inout CGFloat, context: UIGraphicsPDFRendererContext, options: DocumentOptions) {
        if y + height > 772 { footer(job: nil, options: options); context.beginPage(); y = 48 }
    }
    private static func footer(job: Job?, options: DocumentOptions) {
        line(797)
        if options.showFixRecordBranding { text("Generated with FixRecord", x: margin, y: 807, width: 230, size: 8, colour: .darkGray) }
        else if let job { text(job.businessName, x: margin, y: 807, width: 230, size: 8, colour: .darkGray) }
        if let job { text(job.number, x: 430, y: 807, width: 117, size: 8, colour: .darkGray, alignment: .right) }
    }
    private static func panel(_ rect: CGRect, template: DocumentTemplate) {
        if template != .minimal { fill(rect, colour: pale) }
        if template == .classic { navy.setStroke(); UIBezierPath(roundedRect: rect, cornerRadius: 5).stroke() }
    }
    private static func fill(_ rect: CGRect, colour: UIColor) { colour.setFill(); UIBezierPath(roundedRect: rect, cornerRadius: 5).fill() }
    private static func line(_ y: CGFloat) { let path = UIBezierPath(); path.move(to: CGPoint(x: margin, y: y)); path.addLine(to: CGPoint(x: 551, y: y)); UIColor.lightGray.setStroke(); path.lineWidth = 0.6; path.stroke() }
    private static func aspectFill(_ image: UIImage, in rect: CGRect) {
        guard image.size.width > 0, image.size.height > 0, let graphics = UIGraphicsGetCurrentContext() else { return }
        graphics.saveGState(); graphics.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 5).cgPath); graphics.clip()
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        graphics.restoreGState()
    }
    private static func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 40, size: CGFloat, bold: Bool = false, colour: UIColor = .black, alignment: NSTextAlignment = .left, wrap: Bool = false) {
        let style = NSMutableParagraphStyle(); style.alignment = alignment; style.lineBreakMode = wrap ? .byWordWrapping : .byTruncatingTail
        NSString(string: value).draw(in: CGRect(x: x, y: y, width: width, height: height), withAttributes: [.font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size), .foregroundColor: colour, .paragraphStyle: style])
    }
}
