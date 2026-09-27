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
    private var clientPackLocked: Bool { kind == .pack && !entitlements.isPro }
    private var documentDetailsSubtitle: String {
        if let name = job.documentPreset?.name { return name }
        guard hasBusinessName else { return "Name and contact details · Free" }
        let businessName = renderProfile?.businessName ?? ""
        return businessName.isEmpty ? job.businessName : businessName
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Document", selection: $kind) {
                ForEach(ExportKind.allCases, id: \.self) { document in
                    if document == .pack && !entitlements.isPro {
                        Label("Client Pack", systemImage: "star.fill")
                            .accessibilityLabel("Client Pack, Pro")
                            .tag(document)
                    } else {
                        Text(document.rawValue).tag(document)
                    }
                }
            }
                .pickerStyle(.segmented).padding(.horizontal)
            if !clientPackLocked { documentSetup.padding(.horizontal) }
            if clientPackLocked {
                clientPackPreview
            } else if data.isEmpty {
                ContentUnavailableView("No preview", systemImage: "doc", description: Text(error))
            } else { PDFPreview(data: data) }
            if !clientPackLocked {
                Button { showingShare = true } label: { Text("Export").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).disabled(url == nil)
                    .padding(.horizontal).padding(.bottom, 6)
            }
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
        .onChange(of: kind) { _, selected in
            render()
            if selected == .pack {
                Task {
                    await entitlements.refresh()
                    if clientPackLocked { showingUpgrade = true }
                }
            }
        }
        .task { await entitlements.refresh(); render() }
        .onChange(of: entitlements.isPro) { _, _ in render() }
        .onChange(of: showPhotosInWorkReport) { _, _ in render() }
        .onChange(of: job.documentPresetData) { _, _ in render() }
    }
    private var clientPackPreview: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Brand.blue)
                        .frame(width: 52, height: 52)
                        .background(Brand.pale, in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Client Pack")
                                .font(.headline).foregroundStyle(Brand.navy)
                            Text("PRO")
                                .font(.caption2.bold()).foregroundStyle(Brand.blue)
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(Brand.pale, in: Capsule())
                        }
                        Text("Report + invoice.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                Button { showingUpgrade = true } label: {
                    Text("Get Pro").font(.headline).frame(maxWidth: .infinity)
                }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding(20)
            .frame(maxWidth: 420)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Brand.navy.opacity(0.06)))
            .shadow(color: Brand.navy.opacity(0.05), radius: 14, y: 6)
            .padding(.horizontal, 20)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background)
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
                        Text(hasBusinessName ? "Document details" : "Add your business name").font(.subheadline.bold()).foregroundStyle(Brand.navy)
                        Text(documentDetailsSubtitle)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
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
        job.documentPresetDraft(fallback: profile)
    }

    private func render() {
        guard kind != .pack || entitlements.isPro else { data = Data(); url = nil; return }
        do {
            let options = job.documentOptions
            let includePhotos = job.includePhotosInReport
            let business = job.documentProfile(fallback: profile)
            let documents = try PDFMaker.exportDocuments(kind: kind, job: job, profile: business,
                                                        options: options, isPro: entitlements.isPro, includePhotos: includePhotos)
            data = documents.document
            url = try exportURL(for: data, label: kind.rawValue)
            packURL = documents.clientPack.flatMap { try? exportURL(for: $0, label: "Client Pack") }
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

    static func exportDocuments(kind: ExportKind, job: Job, profile: BusinessProfile?, options: DocumentOptions,
                                isPro: Bool, includePhotos: Bool = true) throws -> (document: Data, clientPack: Data?) {
        let document = try make(kind: kind, job: job, profile: profile, options: options, isPro: isPro, includePhotos: includePhotos)
        // The optional combined download must not invalidate a usable report.
        let pack = isPro ? (kind == .pack ? document : try? make(kind: .pack, job: job, profile: profile,
                                                              options: options, isPro: true, includePhotos: includePhotos)) : nil
        return (document, pack)
    }

    static func make(kind: ExportKind, job: Job, profile: BusinessProfile?, options: DocumentOptions = DocumentOptions(), isPro: Bool = false, includePhotos: Bool = true, previewLayout: DocumentTemplate? = nil) throws -> Data {
        guard kind != .pack || isPro else {
            throw NSError(domain: "FixRecord", code: 3, userInfo: [NSLocalizedDescriptionKey: "Client Pack requires Pro."])
        }
        var effective = options.effective(isPro: isPro)
        if let previewLayout { effective.template = previewLayout }
        let pricedItems = kind == .report ? job.items.filter { $0.kind == .material && effective.showPricesInReport } : job.items
        guard (kind == .report || (Money.isValid(job.discount) && Money.isValid(job.taxRate))) && pricedItems.allSatisfy({ Money.isValid($0.quantity) && Money.isValid($0.unitPrice) }) else {
            throw NSError(domain: "FixRecord", code: 1, userInfo: [NSLocalizedDescriptionKey: "Review quantity, price, discount and Tax / VAT before exporting."])
        }
        if kind != .report && job.items.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw NSError(domain: "FixRecord", code: 2, userInfo: [NSLocalizedDescriptionKey: "Add a description to every invoice item before exporting."])
        }
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            if kind == .report || kind == .pack {
                DocumentRenderer(context, job: job, profile: profile, options: effective).report(includePhotos: includePhotos)
            }
            if kind == .invoice || kind == .pack {
                DocumentRenderer(context, job: job, profile: profile, options: effective).invoice()
            }
        }
    }

    static func photoPairs(before: [JobPhoto], after: [JobPhoto]) -> [(JobPhoto?, JobPhoto?)] {
        let includedBefore = before.filter { $0.includeInReport }
        let includedAfter = after.filter { $0.includeInReport }
        return includedBefore.flatMap { original -> [(JobPhoto?, JobPhoto?)] in
            let matched = includedAfter.filter { $0.pairedBeforeID == original.id }
            return matched.isEmpty ? [(original, nil)] : matched.map { (original, $0) }
        } + includedAfter.filter { item in !includedBefore.contains(where: { $0.id == item.pairedBeforeID }) }.map { (nil, $0) }
    }

    /// One renderer owns its palette and page geometry, so previews and exports stay identical.
    private final class DocumentRenderer {
        let context: UIGraphicsPDFRendererContext
        let job: Job
        let profile: BusinessProfile?
        let options: DocumentOptions
        let layout: DocumentTemplate
        let accent: UIColor
        let ink: UIColor
        let tint: UIColor
        let onAccent: UIColor
        var y: CGFloat = 0
        var pageNumber = 0
        var x: CGFloat { layout == .executive ? 216 : layout == .copper ? 174 : 44 }
        var width: CGFloat { 551 - x }
        var serif: Bool { [.classic, .editorial, .copper].contains(layout) }
        var businessName: String {
            let name = profile?.businessName.isEmpty == false ? profile!.businessName : job.businessName
            return name.isEmpty ? "Your Business" : name
        }

        init(_ context: UIGraphicsPDFRendererContext, job: Job, profile: BusinessProfile?, options: DocumentOptions) {
            self.context = context; self.job = job; self.profile = profile; self.options = options
            layout = options.template
            accent = DocumentColour.colour(options.colour(for: options.template))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            accent.getRed(&r, green: &g, blue: &b, alpha: &a)
            func luminance(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGFloat {
                func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
                return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
            }
            onAccent = luminance(r, g, b) < 0.18 ? .white : .black
            tint = UIColor(red: 0.94 + r * 0.06, green: 0.94 + g * 0.06, blue: 0.94 + b * 0.06, alpha: 1)
            while luminance(r, g, b) > 0.14 { r *= 0.92; g *= 0.92; b *= 0.92 }
            ink = UIColor(red: r, green: g, blue: b, alpha: 1)
        }

        func font(_ size: CGFloat, bold: Bool = false, display: Bool = false) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
            let design: UIFontDescriptor.SystemDesign = display && serif ? .serif : display && layout == .blueprint ? .monospaced : .default
            return UIFont(descriptor: base.fontDescriptor.withDesign(design) ?? base.fontDescriptor, size: size)
        }
        func text(_ value: String, _ rect: CGRect, size: CGFloat = 10, bold: Bool = false, colour: UIColor? = nil,
                  alignment: NSTextAlignment = .left, display: Bool = false) {
            let style = NSMutableParagraphStyle(); style.alignment = alignment; style.lineBreakMode = .byWordWrapping
            NSString(string: value).draw(in: rect, withAttributes: [.font: font(size, bold: bold, display: display),
                .foregroundColor: colour ?? navy, .paragraphStyle: style])
        }
        func height(_ value: String, width: CGFloat, size: CGFloat = 10, bold: Bool = false, display: Bool = false) -> CGFloat {
            ceil(NSString(string: value).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font(size, bold: bold, display: display)], context: nil).height)
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ colour: UIColor, radius: CGFloat = 0) {
            colour.setFill(); UIBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: radius).fill()
        }
        func rule(_ y: CGFloat, x: CGFloat? = nil, width: CGFloat? = nil, colour: UIColor? = nil, weight: CGFloat = 0.5) {
            rect(x ?? self.x, y, width ?? self.width, weight, colour ?? UIColor(white: 0.82, alpha: 1))
        }
        func border(_ rect: CGRect, colour: UIColor? = nil) {
            let path = UIBezierPath(rect: rect.insetBy(dx: 0.25, dy: 0.25)); path.lineWidth = 0.5
            (colour ?? ink.withAlphaComponent(0.3)).setStroke(); path.stroke()
        }
        func newPage() {
            context.beginPage(); pageNumber += 1; y = 44
            if layout == .copper { rect(26, 30, 3, 745, accent) }
        }
        func ensure(_ space: CGFloat) {
            if y + space > 768 { footer(); newPage() }
        }
        func footer() {
            rule(795, x: 44, width: 507)
            if options.showFixRecordBranding { text("Created with FixRecord", CGRect(x: 44, y: 806, width: 230, height: 14), size: 8, colour: .darkGray) }
            text("\(job.number)  ·  \(pageNumber)", CGRect(x: 315, y: 806, width: 236, height: 14), size: 8, colour: .darkGray, alignment: .right)
        }
        func lines(_ value: String, width: CGFloat, size: CGFloat = 10) -> [String] {
            let storage = NSTextStorage(string: value, attributes: [.font: font(size)])
            let manager = NSLayoutManager(); let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0; storage.addLayoutManager(manager); manager.addTextContainer(container)
            manager.ensureLayout(for: container)
            var result: [String] = []
            manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, _, _, range, _ in
                let characters = manager.characterRange(forGlyphRange: range, actualGlyphRange: nil)
                result.append((value as NSString).substring(with: characters).trimmingCharacters(in: .newlines))
            }
            return result
        }
        func write(_ value: String, x: CGFloat? = nil, width: CGFloat? = nil, size: CGFloat = 10) {
            let lineHeight = ceil(font(size).lineHeight) + 3
            for line in lines(value, width: width ?? self.width, size: size) {
                ensure(lineHeight)
                text(line, CGRect(x: x ?? self.x, y: y, width: width ?? self.width, height: lineHeight), size: size)
                y += lineHeight
            }
        }

        func letterhead(invoice: Bool) {
            let contact = options.showBusinessDetails ? [profile?.phone, profile?.email, profile?.address,
                invoice && profile?.taxNumber.isEmpty == false ? "Tax / VAT: \(profile!.taxNumber)" : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ") : ""
            let logo = options.showLogo ? profile.flatMap { PhotoStore.image($0.logoFilename) } : nil
            var nameX: CGFloat = 44
            var logoBox: CGRect?
            let nameSize: CGFloat = layout == .editorial ? 27 : 20
            let centred = layout == .classic || layout == .minimal
            if layout == .horizon { rect(0, 0, 595, 8, accent) }
            if layout == .executive { rect(44, 30, 507, 69, accent) }
            if layout == .studio { rect(44, 28, 32, 4, accent) }
            if logo != nil {
                let logoSize = CGFloat(40 * options.logoSize / 100)
                let logoX: CGFloat = centred ? (595 - logoSize) / 2 : layout == .executive ? 56 : 44
                logoBox = CGRect(x: logoX, y: 38, width: logoSize, height: logoSize)
                if !centred { nameX = logoX + logoSize + 14 }
            } else if layout == .executive { nameX += 14 }
            let nameY: CGFloat = centred ? (logoBox.map { $0.maxY + 9 } ?? 40) : 40
            let nameWidth: CGFloat = 551 - nameX - (layout == .executive ? 14 : 0)
            let nameHeight = height(businessName, width: nameWidth, size: nameSize, bold: !serif, display: true)
            // Long business names grow the header instead of colliding with contact details.
            let headerBottom = max(nameY + nameHeight, logoBox?.maxY ?? 0)
            if layout == .executive { rect(44, 30, 507, max(69, headerBottom - 30 + 15), accent) }
            if let logo, let logoBox { drawLogo(logo, in: logoBox) }
            text(businessName, CGRect(x: nameX, y: nameY, width: nameWidth, height: nameHeight), size: nameSize, bold: !serif,
                 colour: layout == .executive ? onAccent : ink, alignment: centred ? .center : layout == .copper ? .right : .left, display: true)
            var contactY = headerBottom + 9
            if layout == .executive { contactY = max(111, contactY + 20) }
            let contactHeight = contact.isEmpty ? 0 : height(contact, width: 507, size: 8)
            text(contact, CGRect(x: 44, y: contactY, width: 507, height: contactHeight), size: 8, colour: .darkGray,
                 alignment: centred ? .center : layout == .copper ? .right : .left)
            y = max(contactY + contactHeight + 22, 111)
            if [.classic, .editorial].contains(layout) {
                rule(y - 9, x: 44, width: 507, colour: ink, weight: 1)
                if layout == .classic { rule(y - 5, x: 44, width: 507, colour: ink) }
            } else if ![.studio, .executive, .horizon, .copper].contains(layout) { rule(y - 9, x: 44, width: 507) }
        }
        func drawLogo(_ image: UIImage, in box: CGRect) {
            guard image.size.width > 0, image.size.height > 0 else { return }
            let scale = min(box.width / image.size.width, box.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height))
        }
        func title(_ value: String, size: CGFloat = 25, centred: Bool = false) {
            let h = height(value, width: width, size: size, bold: !serif, display: true)
            ensure(h + 20)
            text(value, CGRect(x: x, y: y, width: width, height: h), size: size, bold: !serif, colour: ink, alignment: centred ? .center : .left, display: true)
            y += h + 12
        }
        func fields(_ entries: [(String, String)], columns: Int, boxed: Bool = false) {
            let gap: CGFloat = boxed ? 0 : 15
            let cell = (width - CGFloat(columns - 1) * gap) / CGFloat(columns)
            for start in stride(from: 0, to: entries.count, by: columns) {
                let row = Array(entries[start..<min(start + columns, entries.count)])
                let h = max(50, (row.map { height($0.1, width: cell - 20, size: 9) }.max() ?? 0) + 34)
                if h > 620 {
                    for entry in row { section(entry.0, value: entry.1) }
                    continue
                }
                ensure(h + 10)
                for (index, entry) in row.enumerated() {
                    let left = x + CGFloat(index) * (cell + gap)
                    if boxed { border(CGRect(x: left, y: y, width: cell, height: h)) }
                    else if layout == .modern || layout == .horizon { rect(left, y, cell, h, tint, radius: 5) }
                    text(entry.0, CGRect(x: left + 10, y: y + 8, width: cell - 20, height: 12), size: 7, bold: true, colour: ink)
                    text(entry.1, CGRect(x: left + 10, y: y + 24, width: cell - 20, height: h - 28), size: 9)
                }
                y += h + 12
            }
        }
        func sidebar(_ entries: [(String, String)]) {
            var sideY = y
            let sideWidth: CGFloat = layout == .executive ? 140 : 106
            if layout == .executive { rect(44, y, sideWidth, min(600, 768 - y), tint, radius: 4) }
            for entry in entries where !entry.1.isEmpty {
                let left: CGFloat = layout == .executive ? 56 : 44
                let available = sideWidth - (layout == .executive ? 24 : 12)
                let h = height(entry.1, width: available, size: 9)
                // Oversized identity content is handled in the main flow without loss.
                if sideY + h + 32 > 756 { section(entry.0, value: entry.1); continue }
                text(entry.0, CGRect(x: left, y: sideY + 9, width: available, height: 12), size: 7, bold: true, colour: ink)
                text(entry.1, CGRect(x: left, y: sideY + 26, width: available, height: h), size: 9)
                sideY += h + 45
            }
        }
        func section(_ label: String, value: String) {
            guard !value.isEmpty else { return }
            ensure(44)
            if layout == .minimal {
                let labelWidth: CGFloat = 97
                text(label, CGRect(x: x, y: y + 2, width: labelWidth - 12, height: 36), size: 8, bold: true, colour: ink)
                let top = y
                write(value, x: x + labelWidth, width: width - labelWidth)
                if y >= top { y = max(y, top + 30) }
                rule(y + 4); y += 19
            } else {
                if layout == .blueprint {
                    rect(x, y, width, 21, tint)
                    text(label, CGRect(x: x + 8, y: y + 5, width: width - 16, height: 14), size: 8, bold: true, colour: ink)
                    y += 29
                } else {
                    if layout == .studio || layout == .horizon || layout == .precision { rect(x, y + 2, 3, 12, accent) }
                    let inset: CGFloat = layout == .studio || layout == .horizon || layout == .precision ? 12 : 0
                    text(label, CGRect(x: x + inset, y: y, width: width - inset, height: 16), size: 9, bold: true, colour: ink)
                    y += 21
                }
                write(value, size: layout == .editorial ? 11 : 10)
                y += layout == .editorial ? 20 : 12
            }
        }
        func report(includePhotos: Bool) {
            newPage(); letterhead(invoice: false)
            let photos = includePhotos ? job.photos.filter { $0.includeInReport } : []
            let date = (job.completedAt ?? job.createdAt).formatted(date: .abbreviated, time: .omitted)
            let client = [job.clientName, job.clientEmail].filter { !$0.isEmpty }.joined(separator: "\n")
            let identity = [("CLIENT", client), ("PROPERTY / SITE", job.siteAddress), ("TECHNICIAN", job.technician)]
            if layout == .executive || layout == .copper {
                sidebar([("REFERENCE", job.number), ("DATE", date), ("STATUS", job.status.rawValue)] + identity)
            }
            if layout == .horizon { fields([("REFERENCE", job.number), ("DATE", date), ("STATUS", job.status.rawValue)], columns: 3) }
            title(photos.isEmpty ? "Work Report" : job.title, size: layout == .editorial || layout == .studio ? 31 : 24, centred: layout == .classic)
            if photos.isEmpty { write(job.title, size: 12); y += 10 }
            if ![.executive, .copper, .horizon].contains(layout) {
                let reference = [job.number, date] + (layout == .classic ? [] : [job.status.rawValue])
                text(reference.joined(separator: "  /  "), CGRect(x: x, y: y, width: width, height: 15), size: 9, colour: .darkGray, alignment: layout == .classic ? .center : .left); y += 25
            }
            switch layout {
            case .executive, .copper: break
            case .precision:
                for field in identity {
                    let h = max(30, height(field.1, width: width - 140, size: 10) + 14)
                    if h > 620 { section(field.0, value: field.1); continue }
                    ensure(h)
                    rule(y + h, colour: ink.withAlphaComponent(0.16))
                    text(field.0, CGRect(x: x + 8, y: y + 8, width: 103, height: 14), size: 8, bold: true, colour: ink)
                    text(field.1, CGRect(x: x + 128, y: y + 7, width: width - 140, height: h - 10), size: 10)
                    y += h
                }; y += 18
            case .classic: fields(identity + [("STATUS", job.status.rawValue)], columns: 2, boxed: true)
            case .studio:
                fields(identity, columns: 3)
            default: fields(identity, columns: 3, boxed: layout == .blueprint)
            }
            let narrativeWidth = (width - 24) / 2 - 20
            let pairedNarrative = [.editorial, .blueprint].contains(layout) && options.showReportedIssue && !job.issue.isEmpty && !job.summary.isEmpty
                && max(height(job.issue, width: narrativeWidth), height(job.summary, width: narrativeWidth)) < 180
            if !pairedNarrative && options.showReportedIssue { section("REPORTED ISSUE", value: job.issue) }
            if pairedNarrative && layout == .editorial { narrativeColumns() }
            let narrativeFirst = [.editorial, .precision, .copper].contains(layout)
            if narrativeFirst && !pairedNarrative { section("WORK COMPLETED", value: job.summary) }
            for pair in PDFMaker.photoPairs(before: photos.filter { $0.kind == .before }, after: photos.filter { $0.kind == .after }) { photoPair(pair) }
            if pairedNarrative && layout == .blueprint { narrativeColumns() }
            if !narrativeFirst && !pairedNarrative { section("WORK COMPLETED", value: job.summary) }
            let materials = job.items.filter { $0.kind == .material && !$0.name.isEmpty }
            if options.showMaterials && !materials.isEmpty {
                ensure(52)
                let label = photos.isEmpty ? "Materials Used" : "MATERIALS USED"
                text(label, CGRect(x: x, y: y, width: width, height: 17), size: 9, bold: true, colour: ink); y += 23
                if options.showPricesInReport {
                    text("ITEM / QTY", CGRect(x: x, y: y, width: width * 0.53, height: 13), size: 7, bold: true)
                    text("UNIT PRICE", CGRect(x: x + width * 0.55, y: y, width: width * 0.22, height: 13), size: 7, bold: true)
                    text("TOTAL", CGRect(x: x + width * 0.78, y: y, width: width * 0.22, height: 13), size: 7, bold: true, alignment: .right)
                    y += 19
                }
                for item in materials {
                    if options.showPricesInReport { pricedRow(item, report: true) }
                    else { write("\(item.name)  × \(item.quantity)"); y += 5 }
                }
                y += 14
            }
            if options.showTechnicianConfirmation && job.status == .completed && job.technicianConfirmed && !job.technician.isEmpty {
                section("COMPLETED BY", value: [job.technician, profile?.businessName ?? job.businessName,
                    job.completedAt?.formatted(date: .abbreviated, time: .shortened) ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
            }
            if options.showClientAcknowledgement { section("CLIENT ACKNOWLEDGMENT (OPTIONAL)", value: "Name: ____________________\nSignature: ____________________    Date: __________") }
            if options.showAdditionalNotes { section("ADDITIONAL NOTES", value: job.invoiceNotes) }
            footer()
        }
        func narrativeColumns() {
            let cell = (width - 24) / 2
            let blockHeight = max(height(job.issue, width: cell - 20), height(job.summary, width: cell - 20)) + 40
            ensure(blockHeight + 14)
            for (index, entry) in [("REPORTED ISSUE", job.issue), ("WORK COMPLETED", job.summary)].enumerated() {
                let left = x + CGFloat(index) * (cell + 24)
                if layout == .blueprint { border(CGRect(x: left, y: y, width: cell, height: blockHeight)) }
                else { rule(y, x: left, width: cell, colour: ink) }
                text(entry.0, CGRect(x: left + 10, y: y + 10, width: cell - 20, height: 13), size: 8, bold: true, colour: ink)
                text(entry.1, CGRect(x: left + 10, y: y + 29, width: cell - 20, height: blockHeight - 33), size: 10)
            }
            y += blockHeight + 18
        }
        func photoPair(_ pair: (JobPhoto?, JobPhoto?)) {
            if layout == .horizon { horizonPhotos(pair); return }
            let stacked = layout == .copper
            let h: CGFloat = stacked ? 105 : layout == .precision ? 132 : layout == .executive ? 133 : 174
            let values = [(pair.0, "BEFORE"), (pair.1, "AFTER")].filter { $0.0 != nil }
            let captions = layout == .classic || layout == .minimal || layout == .editorial
            if stacked {
                for (value, label) in values {
                    ensure(h + 18); photo(value, label: label, box: CGRect(x: x, y: y, width: width, height: h), caption: false); y += h + 12
                }
            } else {
                ensure(h + (captions ? 38 : 20))
                let gap: CGFloat = 12
                let firstWidth = values.count == 1 ? width : layout == .studio ? (width - gap) * 0.63 : (width - gap) / 2
                for (index, value) in values.enumerated() {
                    let photoX = index == 0 ? x : x + firstWidth + gap
                    let photoWidth = index == 0 ? firstWidth : width - firstWidth - gap
                    photo(value.0, label: value.1, box: CGRect(x: photoX, y: y, width: photoWidth, height: h), caption: captions)
                }
                y += h + (captions ? 35 : 18)
            }
        }
        // Horizon keeps the complete frame visible, including portrait and unmatched photos.
        func horizonPhotos(_ pair: (JobPhoto?, JobPhoto?)) {
            let values = [(pair.0, "BEFORE"), (pair.1, "AFTER")].compactMap { value, label -> (JobPhoto, String)? in
                value.map { ($0, label) }
            }
            guard !values.isEmpty else { return }
            let gap: CGFloat = 16
            let cell = (width - CGFloat(values.count - 1) * gap) / CGFloat(values.count)
            let naturalHeight = values.compactMap { PhotoStore.image($0.0.filename) }.map { image in
                image.size.width > 0 ? cell * image.size.height / image.size.width : 180
            }.max() ?? 180
            let photoHeight = min(values.count == 1 ? 280 : 230, max(160, naturalHeight))
            let captionSpace: CGFloat = options.showPhotoLabels ? 24 : 0
            ensure(photoHeight + captionSpace + 18)
            for (index, value) in values.enumerated() {
                let box = CGRect(x: x + CGFloat(index) * (cell + gap), y: y, width: cell, height: photoHeight)
                rect(box.minX, box.minY, box.width, box.height, tint, radius: 4)
                if let image = PhotoStore.image(value.0.filename) {
                    image.draw(in: PDFMaker.fittedPhotoRect(imageSize: image.size, in: box.insetBy(dx: 6, dy: 6)))
                } else { text("Photo unavailable", box.insetBy(dx: 12, dy: 30), size: 9) }
                if options.showPhotoLabels {
                    text(value.1, CGRect(x: box.minX, y: box.maxY + 7, width: box.width, height: 14), size: 8, bold: true, colour: ink)
                }
            }
            y += photoHeight + captionSpace + 18
        }
        func photo(_ value: JobPhoto?, label: String, box: CGRect, caption: Bool) {
            if let value, let image = PhotoStore.image(value.filename) { PDFMaker.aspectFill(image, in: box) }
            else { rect(box.minX, box.minY, box.width, box.height, tint); text("Photo unavailable", box.insetBy(dx: 12, dy: 30), size: 9) }
            if layout == .blueprint { border(box, colour: ink) }
            guard options.showPhotoLabels else { return }
            if caption { text(label, CGRect(x: box.minX, y: box.maxY + 7, width: box.width, height: 13), size: 8, bold: true, colour: ink) }
            else {
                rect(box.minX + 7, box.minY + 7, 57, 19, ink, radius: 2)
                text(label, CGRect(x: box.minX + 13, y: box.minY + 11, width: 45, height: 12), size: 7, bold: true, colour: .white)
            }
        }
        func invoice() {
            newPage(); letterhead(invoice: true)
            let totals = InvoiceTotals(items: job.items, discount: options.showDiscount ? Money.parse(job.discount) : 0, taxRate: options.showTax ? Money.parse(job.taxRate) : 0)
            let billTo = [job.clientName, job.siteAddress, job.clientEmail].filter { !$0.isEmpty }.joined(separator: "\n")
            var from = [businessName]
            if options.showBusinessDetails { from += [profile?.address, profile?.phone, profile?.email, profile?.taxNumber.isEmpty == false ? "Tax / VAT: \(profile!.taxNumber)" : nil].compactMap { $0 }.filter { !$0.isEmpty } }
            let dates = [("ISSUED", job.createdAt.formatted(date: .abbreviated, time: .omitted))] + (options.showDueDate ? [("DUE", job.dueDate.formatted(date: .abbreviated, time: .omitted))] : [])
            if layout == .executive || layout == .copper { sidebar([("REFERENCE", job.number), ("BILL TO", billTo)] + dates + [("FROM", from.joined(separator: "\n"))]) }
            let invoiceTitleY = y
            title("INVOICE", size: layout == .editorial || layout == .minimal ? 34 : 27, centred: layout == .classic)
            if layout == .horizon {
                text("TOTAL DUE", CGRect(x: 331, y: invoiceTitleY - 4, width: 220, height: 12), size: 7, bold: true, colour: ink, alignment: .right)
                text(Money.format(totals.grandTotal, currency: job.currencyCode), CGRect(x: 331, y: invoiceTitleY + 10, width: 220, height: 29), size: 23, bold: true, colour: ink, alignment: .right)
            }
            if layout != .executive && layout != .copper {
                write("\(job.number)  /  \(job.title)", size: 9); y += 10
                if layout == .minimal { section("BILL TO", value: billTo); invoiceDates(dates) }
                else if layout == .precision {
                    fields([("BILL TO", billTo), ("FROM", from.joined(separator: "\n"))], columns: 2)
                    invoiceDates(dates)
                } else {
                    fields([("BILL TO", billTo), ("FROM", from.joined(separator: "\n"))], columns: 2, boxed: [.classic, .blueprint].contains(layout))
                    invoiceDates(dates)
                }
            } else { write(job.title, size: 10); y += 17 }
            if job.paid { text("PAID", CGRect(x: x, y: y, width: width, height: 16), size: 10, bold: true, colour: ink); y += 24 }
            ensure(65); tableHeader()
            for (kind, label) in [(PriceItem.Kind.material, "MATERIALS"), (.labour, "LABOR"), (.charge, "ADDITIONAL CHARGES")] {
                let items = job.items.filter { $0.kind == kind }; guard !items.isEmpty else { continue }
                if y + 53 > 768 { footer(); newPage(); tableHeader() }
                text(label, CGRect(x: x + 7, y: y + 6, width: width - 14, height: 13), size: 7, bold: true, colour: ink); y += 21
                for item in items { pricedRow(item) }
            }
            let totalRows = 2 + (options.showDiscount && totals.discount > 0 ? 1 : 0) + (options.showTax && totals.tax > 0 ? 1 : 0)
            ensure(CGFloat(totalRows) * 27 + 28); y += 18
            amount("Subtotal", totals.subtotal)
            if options.showDiscount && totals.discount > 0 { amount("Discount", -totals.discount) }
            if options.showTax && totals.tax > 0 { amount("Tax / VAT (\(job.taxRate)%)", totals.tax) }
            amount("TOTAL DUE", totals.grandTotal, total: true)
            y += 18
            let payment = options.showPaymentInstructions ? profile?.paymentInstructions ?? "" : ""
            let terms = options.showTerms ? job.invoiceNotes : ""
            let noteWidth = (width - 24) / 2
            let noteHeight = max(height(payment, width: noteWidth), height(terms, width: noteWidth)) + 27
            if layout == .studio && !payment.isEmpty && !terms.isEmpty && noteHeight < 150 {
                ensure(noteHeight)
                for (index, entry) in [("PAYMENT DETAILS", payment), ("TERMS & NOTES", terms)].enumerated() {
                    let left = x + CGFloat(index) * (noteWidth + 24)
                    text(entry.0, CGRect(x: left, y: y, width: noteWidth, height: 15), size: 8, bold: true, colour: ink)
                    text(entry.1, CGRect(x: left, y: y + 21, width: noteWidth, height: noteHeight - 21), size: 10)
                }
                y += noteHeight
            } else {
                section("PAYMENT DETAILS", value: payment)
                section("TERMS & NOTES", value: terms)
            }
            footer()
        }
        func invoiceDates(_ entries: [(String, String)]) {
            ensure(27)
            let cell = width / CGFloat(max(entries.count, 1))
            for (index, entry) in entries.enumerated() {
                text("\(entry.0)  \(entry.1)", CGRect(x: x + CGFloat(index) * cell + 10, y: y, width: cell - 20, height: 15), size: 8, colour: .darkGray)
            }
            y += 27
        }
        func tableHeader() {
            if layout == .studio { rule(y, colour: ink); y += 8; return }
            let filled = [.modern, .executive, .blueprint, .horizon].contains(layout)
            if filled { rect(x, y, width, 27, accent) }
            else { rule(y, colour: ink, weight: layout == .classic ? 1.2 : 0.6); rule(y + 27, colour: ink) }
            let colour = filled ? onAccent : ink
            let labels: [(String, CGFloat, CGFloat)] = [("DESCRIPTION", 0.015, 0.47), ("QTY", 0.50, 0.09), ("RATE", 0.62, 0.16), ("AMOUNT", 0.80, 0.18)]
            for (label, left, w) in labels { text(label, CGRect(x: x + width * left, y: y + 9, width: width * w, height: 13), size: 7, bold: true, colour: colour, alignment: label == "AMOUNT" ? .right : .left) }
            y += 28
        }
        func pricedRow(_ item: PriceItem, report: Bool = false) {
            let card = layout == .studio && !report
            let rowSize: CGFloat = layout == .precision ? 10 : 9
            let descriptionWidth = width * (report ? 0.53 : card ? 0.75 : 0.47) - 10
            let description = report ? "\(item.name) × \(item.quantity)" : item.name
            var remaining = lines(description, width: descriptionWidth, size: card ? 11 : rowSize)
            if remaining.isEmpty { remaining = [""] }
            var first = true
            repeat {
                let rate = Money.format(Money.parse(item.unitPrice), currency: job.currencyCode)
                let total = Money.format(item.total, currency: job.currencyCode)
                let numericHeight = max(height(total, width: width * 0.18, size: rowSize),
                    height(rate, width: width * (report ? 0.22 : 0.17), size: rowSize), height(item.quantity, width: width * 0.1, size: rowSize))
                let minimum: CGFloat = max(card ? 43 : 26, numericHeight + 16)
                if y + minimum > 768 { footer(); newPage(); if !report { tableHeader() } }
                let lineHeight: CGFloat = card ? 16 : ceil(font(rowSize).lineHeight) + 2
                let capacity = max(1, Int((768 - y - (card ? 27 : 13)) / lineHeight))
                let count = min(capacity, remaining.count)
                let chunk = Array(remaining.prefix(count)); remaining.removeFirst(count)
                let h = max(minimum, CGFloat(count) * lineHeight + (card ? 27 : 13))
                if card { rect(x, y + 3, width, h - 6, tint, radius: 5) }
                if layout == .blueprint { border(CGRect(x: x, y: y, width: width, height: h)) }
                for (index, line) in chunk.enumerated() { text(line, CGRect(x: x + 7, y: y + 8 + CGFloat(index) * lineHeight, width: descriptionWidth, height: lineHeight), size: card ? 11 : rowSize) }
                if first {
                    if card {
                        text("\(item.quantity) × \(rate)", CGRect(x: x + 7, y: y + h - 20, width: width * 0.6, height: 14), size: 9, colour: .darkGray)
                    } else if !report { text(item.quantity, CGRect(x: x + width * 0.50, y: y + 8, width: width * 0.1, height: h - 12), size: rowSize) }
                    if !card { text(rate, CGRect(x: x + width * (report ? 0.55 : 0.62), y: y + 8, width: width * (report ? 0.22 : 0.17), height: h - 12), size: rowSize) }
                    text(Money.format(item.total, currency: job.currencyCode), CGRect(x: x + width * 0.8, y: y + 8, width: width * 0.18, height: h - 12), size: rowSize, bold: card, alignment: .right)
                }
                if !card { rule(y + h) }
                y += h; first = false
            } while !remaining.isEmpty
        }
        func amount(_ label: String, _ value: Decimal, total: Bool = false) {
            let full = [.minimal, .horizon, .precision].contains(layout)
            let w = full ? width : min(width, 245)
            let left = x + width - w
            let labelSize: CGFloat = total ? 10 : 9
            let valueSize: CGFloat = total ? 11 : 9
            let valueText = Money.format(value, currency: job.currencyCode)
            let rowHeight = max(total ? 36 : 23, max(height(label, width: w * 0.58 - 10, size: labelSize, bold: total),
                height(valueText, width: w * 0.41 - 8, size: valueSize, bold: total)) + 12)
            ensure(rowHeight)
            if total {
                if layout == .classic || layout == .editorial || layout == .minimal { rule(y, x: left, width: w, colour: ink, weight: 1) }
                else { rect(left, y, w, rowHeight - 3, tint, radius: 3) }
            }
            text(label, CGRect(x: left + 8, y: y + 8, width: w * 0.58 - 10, height: rowHeight - 12), size: total ? 10 : 9, bold: total, colour: total ? ink : navy)
            text(Money.format(value, currency: job.currencyCode), CGRect(x: left + w * 0.59, y: y + 8, width: w * 0.41 - 8, height: rowHeight - 12), size: total ? 11 : 9, bold: total, colour: total ? ink : navy, alignment: .right)
            y += rowHeight
        }
    }

    static func fittedPhotoRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    private static func aspectFill(_ image: UIImage, in rect: CGRect) {
        guard image.size.width > 0, image.size.height > 0, let graphics = UIGraphicsGetCurrentContext() else { return }
        graphics.saveGState(); graphics.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 3).cgPath); graphics.clip()
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        graphics.restoreGState()
    }
}
