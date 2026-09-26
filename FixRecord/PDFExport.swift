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
    @Query private var profiles: [BusinessProfile]
    @Bindable var job: Job
    @State private var kind: ExportKind = .report
    @State private var data = Data()
    @State private var url: URL?
    @State private var packURL: URL?
    @State private var error = ""
    @State private var showingShare = false
    @State private var showingUpgrade = false
    @State private var store = PresetStore.shared
    @State private var editingJobPreset: SavedPreset?
    @State private var creatingPreset: SavedPreset?
    @State private var pendingPreset: SavedPreset?
    @AppStorage("showPhotosInWorkReport") private var showPhotosInWorkReport = true
    @StateObject private var entitlements = EntitlementService.shared
    private var profile: BusinessProfile? { profiles.first }
    private var renderProfile: BusinessProfile? { job.documentProfile(fallback: profile) }
    private var hasBusinessName: Bool { renderProfile?.businessName.isEmpty == false || !job.businessName.isEmpty }
    private var documentDetailsSubtitle: String {
        guard hasBusinessName else { return "Add your business details" }
        if let name = job.documentPreset?.name { return name }
        let businessName = renderProfile?.businessName ?? ""
        return businessName.isEmpty ? job.businessName : businessName
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Document", selection: $kind) { ForEach(ExportKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).padding(.horizontal)
            documentSetup.padding(.horizontal)
            if kind == .pack && !entitlements.isPro {
                ContentUnavailableView("Client Pack is Pro", systemImage: "lock.doc", description: Text("Work Reports and Invoices remain free."))
                Button("Upgrade to Pro") { showingUpgrade = true }.buttonStyle(.borderedProminent)
            } else if data.isEmpty {
                ContentUnavailableView("No preview", systemImage: "doc", description: Text(error))
            } else { PDFPreview(data: data) }
            Button { showingShare = true } label: { Text("Export").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).disabled(url == nil)
                .padding(.horizontal).padding(.bottom, 6)
        }
        .navigationTitle("Preview").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingShare) { if let url { NavigationStack { ShareOptionsView(url: url, packURL: packURL, data: data, title: job.number) } } }
        .sheet(isPresented: $showingUpgrade) { NavigationStack { UpgradeView() } }
        .sheet(item: $editingJobPreset) { preset in
            NavigationStack {
                PresetEditorView(preset: preset, editName: false) { job.applyPreset($0, includeJobDefaults: false) }
            }
        }
        .sheet(item: $creatingPreset) { preset in
            NavigationStack {
                PresetEditorView(preset: preset) { saved in
                    store.save(saved)
                    job.applyPreset(saved, includeJobDefaults: false)
                }
            }
        }
        .alert("Use this preset?", isPresented: Binding(get: { pendingPreset != nil }, set: { if !$0 { pendingPreset = nil } })) {
            Button("Use Preset") { if let preset = pendingPreset { job.applyPreset(preset, includeJobDefaults: false) }; pendingPreset = nil }
            Button("Cancel", role: .cancel) { pendingPreset = nil }
        } message: {
            Text("This updates this job’s business and document settings. Client details and work notes stay as they are.")
        }
        .onAppear { render() }
        .onChange(of: kind) { _, _ in render() }
        .task { await entitlements.refresh(); render() }
        .onChange(of: entitlements.isPro) { _, _ in render() }
        .onChange(of: showPhotosInWorkReport) { _, _ in render() }
        .onChange(of: job.documentPresetData) { _, _ in render() }
    }
    private var documentSetup: some View {
        VStack(spacing: 0) {
            Button { editingJobPreset = presetDraft() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Brand.blue)
                        .frame(width: 40, height: 40)
                        .background(Brand.pale, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Document details").font(.subheadline.bold()).foregroundStyle(Brand.navy)
                        Text(documentDetailsSubtitle)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(hasBusinessName ? "Edit" : "Set up").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.blue)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Brand.blue)
                }
                .padding(15).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Rectangle().fill(Brand.navy.opacity(0.08)).frame(height: 1).padding(.leading, 67)
            Menu {
                ForEach(store.presets) { preset in
                    Button { pendingPreset = preset } label: {
                        if job.documentPreset?.id == preset.id { Label(preset.name, systemImage: "checkmark") }
                        else { Text(preset.name) }
                    }
                }
                if !store.presets.isEmpty { Divider() }
                Button { var draft = presetDraft(); draft.name = ""; creatingPreset = draft } label: {
                    Label("Create New Preset", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.on.square").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.blue)
                        .frame(width: 40)
                    Text("Presets").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.navy)
                    Spacer()
                    Text(store.presets.isEmpty ? "Create one" : "Choose").font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 15).padding(.vertical, 13).contentShape(Rectangle())
            }
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Brand.navy.opacity(0.06)))
        .shadow(color: Brand.navy.opacity(0.04), radius: 10, y: 4)
    }
    private func presetDraft() -> SavedPreset {
        var draft = job.documentPreset ?? SavedPreset.custom(profile: profile)
        if job.documentPreset == nil {
            if !job.businessName.isEmpty { draft.business.businessName = job.businessName }
            draft.business.taxRate = job.taxRate
        }
        draft.business.currencyCode = job.currencyCode
        draft.id = UUID()
        draft.name = "Custom"
        draft.technician = ""
        draft.category = ""
        return draft
    }
    private func render() {
        guard kind != .pack || entitlements.isPro else { data = Data(); url = nil; return }
        do {
            let options = job.documentOptions
            let includePhotos = job.includePhotosInReport
            let business = job.documentProfile(fallback: profile)
            data = try PDFMaker.make(kind: kind, job: job, profile: business, options: options, isPro: entitlements.isPro, includePhotos: includePhotos)
            url = try exportURL(for: data, label: kind.rawValue)
            if entitlements.isPro {
                let pack = try PDFMaker.make(kind: .pack, job: job, profile: business, options: options, isPro: true, includePhotos: includePhotos)
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

    static func make(kind: ExportKind, job: Job, profile: BusinessProfile?, options: DocumentOptions = DocumentOptions(), isPro: Bool = false, includePhotos: Bool = true) throws -> Data {
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
            if kind == .report || kind == .pack {
                if includePhotos && !job.photos.isEmpty { drawReport(context, job: job, profile: profile, options: effective) }
                else { drawTextReport(context, job: job, profile: profile, options: effective) }
            }
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
            if pair.0 != nil && pair.1 != nil {
                photo(pair.0, title: "BEFORE", x: margin, y: y)
                photo(pair.1, title: "AFTER", x: margin + 258, y: y)
            } else {
                photo(pair.0 ?? pair.1, title: pair.0 == nil ? "AFTER" : "BEFORE", x: margin, y: y, width: contentWidth)
            }
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

    private static func drawTextReport(_ context: UIGraphicsPDFRendererContext, job: Job, profile: BusinessProfile?, options: DocumentOptions) {
        context.beginPage()
        var nameX = margin
        if options.showLogo, let logo = profile.flatMap({ PhotoStore.image($0.logoFilename) }) {
            aspectFill(logo, in: CGRect(x: margin, y: 34, width: 48, height: 48)); nameX += 60
        } else if options.showFixRecordBranding {
            fill(CGRect(x: margin, y: 34, width: 48, height: 48), colour: navy)
            drawPDFSymbol("wrench.adjustable.fill", in: CGRect(x: margin + 10, y: 44, width: 28, height: 28), colour: .white)
            nameX += 60
        }
        let business = profile?.businessName.isEmpty == false ? profile!.businessName : job.businessName
        text(business.isEmpty ? "Your Business" : business, x: nameX, y: 38, width: 280, size: 20, bold: true, colour: navy)
        text("Professional work documentation", x: nameX, y: 66, width: 270, size: 9, colour: .darkGray)
        if options.showBusinessDetails {
            let contact = [profile?.phone, profile?.email, profile?.address].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            text(contact, x: 377, y: 38, width: 174, height: 56, size: 8, colour: navy, alignment: .right, wrap: true)
        }
        line(106)

        text("Work Report", x: margin, y: 122, width: 360, size: 28, bold: true, colour: navy)
        let completed = job.status == .completed
        fill(CGRect(x: 456, y: 128, width: 95, height: 25), colour: completed ? UIColor(red: 0.87, green: 0.98, blue: 0.91, alpha: 1) : pale)
        text(job.status.rawValue, x: 461, y: 134, width: 85, size: 10, bold: true, colour: completed ? green : navy, alignment: .center)
        text(job.title, x: margin, y: 162, width: contentWidth, size: 13, bold: true, colour: navy)
        let dateLabel = completed ? "Completed" : "Created"
        text("Job #\(job.number)    |    \(dateLabel): \((job.completedAt ?? job.createdAt).formatted(date: .abbreviated, time: .omitted))", x: margin, y: 184, width: contentWidth, size: 10, colour: .darkGray)

        var y: CGFloat = 216
        panel(CGRect(x: margin, y: y, width: contentWidth, height: 87), template: options.template)
        let identityWidth = (contentWidth - 20) / 3
        let identity: [(String, String)] = [
            ("CLIENT", [job.clientName, job.clientEmail].filter { !$0.isEmpty }.joined(separator: "\n")),
            ("PROPERTY / SITE", job.siteAddress),
            ("TECHNICIAN", [job.technician, business].filter { !$0.isEmpty }.joined(separator: "\n"))
        ]
        for (index, entry) in identity.enumerated() {
            let x = margin + CGFloat(index) * (identityWidth + 10)
            text(entry.0, x: x + 10, y: y + 12, width: identityWidth - 20, size: 9, bold: true, colour: navy)
            text(entry.1, x: x + 10, y: y + 31, width: identityWidth - 20, height: 50, size: 10, colour: navy, wrap: true)
        }
        y += 106

        if options.showReportedIssue && !job.issue.isEmpty {
            textReportSection("Reported Issue", symbol: "doc.text.fill", value: job.issue, y: &y, context: context, options: options)
        }
        if !job.summary.isEmpty {
            textReportSection("Work Completed", symbol: "wrench.adjustable.fill", value: job.summary, y: &y, context: context, options: options)
        }
        let materials = job.items.filter { $0.kind == .material && !$0.name.isEmpty }
        if options.showMaterials && !materials.isEmpty {
            ensure(56, y: &y, context: context, options: options)
            reportIcon("shippingbox.fill", x: margin, y: y, size: 16)
            text("Materials Used", x: margin + 28, y: y, width: 300, size: 12, bold: true, colour: navy)
            y += 29
            fill(CGRect(x: margin, y: y, width: contentWidth, height: 24), colour: pale)
            text("ITEM", x: margin + 10, y: y + 6, width: 235, size: 9, bold: true, colour: navy)
            text("QTY", x: 331, y: y + 6, width: 40, size: 9, bold: true, colour: navy)
            if options.showPricesInReport {
                text("UNIT PRICE", x: 389, y: y + 6, width: 75, size: 9, bold: true, colour: navy)
                text("TOTAL", x: 475, y: y + 6, width: 65, size: 9, bold: true, colour: navy, alignment: .right)
            }
            y += 24
            for item in materials {
                ensure(25, y: &y, context: context, options: options)
                text(item.name, x: margin + 10, y: y + 6, width: 265, size: 10, colour: navy)
                text(item.quantity, x: 331, y: y + 6, width: 40, size: 10, colour: navy)
                if options.showPricesInReport {
                    text(Money.format(Money.parse(item.unitPrice), currency: job.currencyCode), x: 379, y: y + 6, width: 85, size: 10, colour: navy)
                    text(Money.format(item.total, currency: job.currencyCode), x: 465, y: y + 6, width: 75, size: 10, colour: navy, alignment: .right)
                }
                line(y + 24); y += 25
            }
            y += 18
        }
        if options.showAdditionalNotes && !job.invoiceNotes.isEmpty {
            textReportSection("Additional Notes", symbol: "note.text", value: job.invoiceNotes, y: &y, context: context, options: options)
        }
        if options.showTechnicianConfirmation && completed && job.technicianConfirmed && !job.technician.isEmpty {
            ensure(98, y: &y, context: context, options: options)
            let cardWidth = (contentWidth - 14) / 2
            panel(CGRect(x: margin, y: y, width: cardWidth, height: 82), template: options.template)
            panel(CGRect(x: margin + cardWidth + 14, y: y, width: cardWidth, height: 82), template: options.template)
            text("COMPLETED BY", x: margin + 11, y: y + 10, width: cardWidth - 22, size: 10, bold: true, colour: navy)
            text([job.technician, business, job.completedAt?.formatted(date: .abbreviated, time: .shortened) ?? ""].filter { !$0.isEmpty }.joined(separator: "\n"), x: margin + 11, y: y + 28, width: cardWidth - 22, height: 50, size: 10, colour: navy, wrap: true)
            let signatureX = margin + cardWidth + 25
            text("SIGNATURE (OPTIONAL)", x: signatureX, y: y + 10, width: cardWidth - 22, size: 10, bold: true, colour: navy)
            let path = UIBezierPath(); path.move(to: CGPoint(x: signatureX, y: y + 61)); path.addLine(to: CGPoint(x: signatureX + cardWidth - 24, y: y + 61)); UIColor.lightGray.setStroke(); path.lineWidth = 0.7; path.stroke()
            y += 97
        }
        if options.showClientAcknowledgement {
            ensure(45, y: &y, context: context, options: options)
            text("CLIENT ACKNOWLEDGEMENT (OPTIONAL)", x: margin, y: y, width: contentWidth, size: 10, bold: true, colour: navy)
            text("Name: ____________________    Signature: ____________________    Date: __________", x: margin, y: y + 19, width: contentWidth, size: 9)
        }
        footer(job: job, options: options)
    }

    private static func textReportSection(_ title: String, symbol: String, value: String, y: inout CGFloat, context: UIGraphicsPDFRendererContext, options: DocumentOptions) {
        let width = contentWidth - 29
        let font = UIFont.systemFont(ofSize: 11)
        let height = max(17, ceil(NSString(string: value).boundingRect(with: CGSize(width: width, height: 650), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil).height) + 4)
        ensure(33 + height, y: &y, context: context, options: options)
        reportIcon(symbol, x: margin, y: y, size: 16)
        text(title, x: margin + 29, y: y, width: width, size: 12, bold: true, colour: navy)
        text(value, x: margin + 29, y: y + 26, width: width, height: height, size: 11, colour: navy, wrap: true)
        y += 34 + height
        line(y); y += 16
    }

    private static func reportIcon(_ symbol: String, x: CGFloat, y: CGFloat, size: CGFloat) {
        drawPDFSymbol(symbol, in: CGRect(x: x, y: y + 1, width: size, height: size), colour: navy)
    }

    private static func drawPDFSymbol(_ symbol: String, in rect: CGRect, colour: UIColor) {
        guard let source = UIImage(systemName: symbol)?.withTintColor(colour, renderingMode: .alwaysOriginal) else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let raster = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: rect.size))
        }
        raster.draw(in: rect)
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

    private static func photo(_ value: JobPhoto?, title: String, x: CGFloat, y: CGFloat, width: CGFloat = 249) {
        let box = CGRect(x: x, y: y, width: width, height: 187)
        if let value, let image = PhotoStore.image(value.filename) { aspectFill(image, in: box) }
        else {
            fill(box, colour: pale)
            text("Photo unavailable", x: x + 20, y: y + 82, width: width - 40, size: 11, colour: .gray, alignment: .center)
        }
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
