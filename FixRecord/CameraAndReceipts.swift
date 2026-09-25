import SwiftUI
import PhotosUI
@preconcurrency import AVFoundation
import Vision
import VisionKit
import ImageIO

private extension UIImage.Orientation {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}

final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    @Published var capturedImage: UIImage?
    @Published var error: String?
    private var device: AVCaptureDevice?
    @MainActor func start() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { error = "Camera unavailable. Use the photo library or sample images."; return }
        guard await AVCaptureDevice.requestAccess(for: .video) else { error = "Allow camera access in Settings to take a photo."; return }
        do {
            session.beginConfiguration(); session.sessionPreset = .photo
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw CocoaError(.featureUnsupported) }
            device = camera
            if session.inputs.isEmpty {
                let input = try AVCaptureDeviceInput(device: camera)
                guard session.canAddInput(input), session.canAddOutput(output) else { throw CocoaError(.featureUnsupported) }
                session.addInput(input); session.addOutput(output)
            }
            session.commitConfiguration()
            let session = session
            await withCheckedContinuation { continuation in DispatchQueue.global(qos: .userInitiated).async { session.startRunning(); continuation.resume() } }
        } catch { session.commitConfiguration(); self.error = error.localizedDescription }
    }
    @MainActor func stop() { let session = session; DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() } }
    @MainActor func capture() { let settings = AVCapturePhotoSettings(); if device?.hasFlash == true { settings.flashMode = flashEnabled ? .on : .off }; output.capturePhoto(with: settings, delegate: self) }
    @Published var flashEnabled = false
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { DispatchQueue.main.async { self.error = error.localizedDescription }; return }
        if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) { DispatchQueue.main.async { self.capturedImage = image } }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView { let view = PreviewView(); view.layerSession.session = session; return view }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var layerSession: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override init(frame: CGRect) { super.init(frame: frame); layerSession.videoGravity = .resizeAspectFill }
    required init?(coder: NSCoder) { fatalError() }
}

struct PhotoCaptureView: View {
    @Bindable var job: Job
    let kind: PhotoKind
    @StateObject private var camera = CameraController()
    @State private var selectedItem: PhotosPickerItem?
    @State private var ghostOpacity = 0.40
    @State private var selectedBeforeID: UUID?
    @State private var qualityWarning = ""
    @State private var alignmentGuidance = ""
    private var beforePhotos: [JobPhoto] { job.photos.filter { $0.kind == .before } }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(kind == .before ? "Capture Before" : "MatchShot · Capture After").font(.title3.bold()).foregroundStyle(Brand.navy)
                if kind == .after && !beforePhotos.isEmpty {
                    Picker("Before photo", selection: $selectedBeforeID) { ForEach(beforePhotos) { photo in Text(photo.capturedAt.formatted()).tag(Optional(photo.id)) } }.pickerStyle(.menu)
                    HStack { Text("Ghost opacity"); Slider(value: $ghostOpacity, in: 0.1...0.75) }
                }
                ZStack {
                    CameraPreview(session: camera.session).frame(height: 430).clipped()
                    if kind == .after, let photo = beforePhotos.first(where: { $0.id == selectedBeforeID }), let image = PhotoStore.image(photo.filename) {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 430).clipped().opacity(ghostOpacity)
                    }
                    if camera.error != nil { Text(camera.error ?? "").padding().background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white) }
                }.clipShape(RoundedRectangle(cornerRadius: 16))
                if UIImagePickerController.isSourceTypeAvailable(.camera) { HStack { Button { camera.flashEnabled.toggle() } label: { Image(systemName: camera.flashEnabled ? "bolt.fill" : "bolt.slash") }; Spacer(); Button { camera.capture() } label: { Image(systemName: "circle.inset.filled").font(.system(size: 62)) }; Spacer(); Text(" ") }.padding(.horizontal, 30) }
                PhotosPicker(selection: $selectedItem, matching: .images) { Label("Choose Photo", systemImage: "photo.on.rectangle") }.buttonStyle(.bordered)
                if kind == .after && beforePhotos.isEmpty { Text("Add a before photo first to use the MatchShot ghost overlay.").font(.caption).foregroundStyle(.secondary) }
                if !qualityWarning.isEmpty { Label(qualityWarning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                if !alignmentGuidance.isEmpty { Label(alignmentGuidance, systemImage: "viewfinder").font(.caption).foregroundStyle(Brand.teal) }
                Text("Saved \(kind.rawValue) photos").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                ScrollView(.horizontal) { HStack { ForEach(job.photos.filter { $0.kind == kind }) { photo in if let image = PhotoStore.image(photo.filename) { ZStack(alignment: .topTrailing) { Image(uiImage: image).resizable().scaledToFill().frame(width: 115, height: 100).clipped().clipShape(RoundedRectangle(cornerRadius: 8)); Button { var photos = job.photos; photos.removeAll { $0.id == photo.id }; job.photos = photos; job.technicianConfirmed = false; PhotoStore.delete(photo.filename); if kind == .before && selectedBeforeID == photo.id { selectedBeforeID = beforePhotos.first?.id } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white).shadow(radius: 3) }.padding(4).accessibilityLabel("Remove photo") } } } } }
            }.padding()
        }.navigationTitle(kind == .before ? "Before photos" : "After photos")
            .task { if kind == .after { selectedBeforeID = beforePhotos.first?.id }; await camera.start() }
            .onDisappear { camera.stop() }
            .onChange(of: camera.capturedImage) { _, newValue in if let newValue { save(newValue); camera.capturedImage = nil } }
            .onChange(of: selectedItem) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) { save(image) } } }
    }
    private func save(_ image: UIImage) {
        do {
            let filename = try PhotoStore.save(image)
            var photos = job.photos
            photos.append(JobPhoto(kind: kind, filename: filename, pairedBeforeID: kind == .after ? selectedBeforeID : nil))
            job.photos = photos
            job.technicianConfirmed = false
            if job.status == .draft { job.status = .inProgress }
            qualityWarning = ImageQuality.warning(for: image) ?? ""
            if kind == .after, let before = beforePhotos.first(where: { $0.id == selectedBeforeID }), let original = PhotoStore.image(before.filename) {
                alignmentGuidance = MatchShotBridge.compare(before: original, after: image).guidance
            }
        } catch { camera.error = error.localizedDescription }
    }
}

enum ImageQuality {
    static func warning(for image: UIImage) -> String? {
        guard let cg = image.cgImage else { return nil }
        let width = 48, height = 48
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let average = Double(pixels.reduce(0) { $0 + Int($1) }) / Double(pixels.count)
        if average < 28 { return "This photo looks very dark. You can keep it or retake it." }
        var edges = 0.0
        for y in 1..<height { for x in 1..<width { let i = y * width + x; edges += abs(Double(pixels[i]) - Double(pixels[i - 1])) + abs(Double(pixels[i]) - Double(pixels[i - width])) } }
        if edges / Double(width * height) < 10 { return "This photo may be blurry. You can keep it or retake it." }
        return nil
    }
}

struct ReceiptView: View {
    @Bindable var job: Job
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var merchant = ""
    @State private var number = ""
    @State private var message = ""
    @State private var detectedTotal = ""
    @State private var date = Date()
    @State private var rows: [PriceItem] = []
    @State private var showingCamera = false
    @State private var pendingCapture: UIImage?
    @State private var processing = false
    @State private var addedCount = 0
    var body: some View {
        Group {
            if addedCount > 0 { successView }
            else if processing { VStack(spacing: 22) { Spacer(); Image(systemName: "doc.text.viewfinder").font(.system(size: 62)).foregroundStyle(Brand.blue); Text("Processing receipt").font(.title2.bold()); ProgressView("Reading text and finding items…"); Spacer() }.frame(maxWidth: .infinity) }
            else if image == nil { startView }
            else { reviewView }
        }.navigationTitle(image == nil ? "Add Materials" : "Receipt Details")
            .sheet(isPresented: $showingCamera, onDismiss: {
                guard let captured = pendingCapture else { return }
                pendingCapture = nil
                image = captured
                Task { await recognise(captured) }
            }) {
                ReceiptCamera { captured in pendingCapture = captured } onError: { message = $0 }
            }
            .onChange(of: item) { _, selected in Task { if let data = try? await selected?.loadTransferable(type: Data.self), let value = UIImage(data: data) { image = value; await recognise(value) } } }
    }
    private var startView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.text.viewfinder").font(.system(size: 60)).foregroundStyle(Brand.navy).frame(width: 100, height: 100).background(Brand.pale, in: RoundedRectangle(cornerRadius: 25))
            Text("Scan a receipt").font(.title.bold()).foregroundStyle(Brand.navy)
            Text("Take a photo of your receipt and we'll extract the items and prices.").multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 28)
            Text("After capturing, tap Save in the scanner.").font(.subheadline).foregroundStyle(.secondary)
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.red).padding(.horizontal) }
            VStack(alignment: .leading, spacing: 12) {
                Label("Saves you time", systemImage: "clock")
                Label("Adds items to your job", systemImage: "plus.circle")
                Label("Review everything before saving", systemImage: "checkmark.circle")
            }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 38)
            Spacer()
            if VNDocumentCameraViewController.isSupported {
                PrimaryButton(title: "Scan Receipt", icon: "camera") { showingCamera = true }.padding(.horizontal)
            }
            PhotosPicker(selection: $item, matching: .images) { Label("Choose from Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity).padding(12) }.buttonStyle(.bordered).padding(.horizontal)
            Spacer().frame(height: 20)
        }
    }
    private var reviewView: some View {
        Form {
            Section("Receipt") {
                if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220) }
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Review extracted details") {
                TextField("Merchant", text: $merchant)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Receipt number", text: $number)
                if !detectedTotal.isEmpty { LabeledContent("Receipt total", value: detectedTotal) }
            }
            Section("Items found") {
                if rows.isEmpty { Text("No items found. Add them manually or retake the receipt.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach($rows) { $row in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Item", text: $row.name)
                        HStack {
                            TextField("Qty", text: $row.quantity).frame(width: 70).keyboardType(.decimalPad)
                            TextField("Unit price", text: $row.unitPrice).keyboardType(.decimalPad)
                        }
                    }
                }.onDelete { rows.remove(atOffsets: $0) }
                Button { rows.append(PriceItem(kind: .material, name: "", unitPrice: "0")) } label: { Label("Add Item", systemImage: "plus") }
            }
            Section {
                PrimaryButton(title: "Add Items to Job", icon: "checkmark") { confirm() }.disabled(!ReceiptParser.canConfirm(rows))
                if !ReceiptParser.canConfirm(rows) { Text("Review each item's name, quantity and price.").font(.caption).foregroundStyle(.secondary) }
                Button("Retake Receipt") { image = nil; rows = []; message = ""; showingCamera = true }
            }
        }
    }
    private var successView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 75)).foregroundStyle(Brand.teal)
            Text("Materials added").font(.title.bold()).foregroundStyle(Brand.navy)
            Text("\(addedCount) item\(addedCount == 1 ? "" : "s") added to this job.").foregroundStyle(.secondary)
            Spacer()
            NavigationLink { PricingView(job: job) } label: { Text("View in Materials").font(.headline).frame(maxWidth: .infinity).padding(14).foregroundStyle(.white).background(Brand.blue, in: RoundedRectangle(cornerRadius: 12)) }.padding(.horizontal)
            Button("Scan Another Receipt") { addedCount = 0; image = nil; rows = []; message = "" }.padding(.bottom, 25)
        }
    }
    private func recognise(_ image: UIImage) async {
        processing = true
        defer { processing = false }
        guard let cg = image.cgImage else { message = "Could not read this image. Please retake it or add items manually."; return }
        let orientation = image.imageOrientation.cgImagePropertyOrientation
        do {
            let lines = try await Task.detached(priority: .userInitiated) {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                try VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            }.value
            let parsed = ReceiptParser.parse(lines)
            merchant = parsed.merchant; number = parsed.number; rows = parsed.items; date = parsed.date ?? Date(); detectedTotal = parsed.total
            message = rows.isEmpty ? "No items were recognised. Add them manually or retake the receipt." : "Review every field before adding materials. OCR can make mistakes."
        } catch { message = "Text recognition failed. You can add and edit materials manually." }
    }
    private func confirm() {
        guard ReceiptParser.canConfirm(rows), let image, let filename = try? PhotoStore.save(image) else { return }
        var record = ReceiptRecord(merchant: merchant, date: date, number: number, filename: filename, items: rows, confirmed: true)
        let confirmed = rows.map { row -> PriceItem in var item = row; item.sourceReceiptID = record.id; return item }
        record.items = confirmed
        var items = job.items; items.append(contentsOf: confirmed); job.items = items
        job.technicianConfirmed = false
        var receipts = job.receipts; receipts.append(record); job.receipts = receipts
        addedCount = confirmed.count; rows = []; self.image = nil
    }
}

struct ReceiptCamera: UIViewControllerRepresentable {
    let completion: (UIImage) -> Void
    let onError: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let camera = VNDocumentCameraViewController(); camera.delegate = context.coordinator; return camera
    }
    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion, onError: onError, dismiss: dismiss) }
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completion: (UIImage) -> Void
        let onError: (String) -> Void
        let dismiss: DismissAction
        init(completion: @escaping (UIImage) -> Void, onError: @escaping (String) -> Void, dismiss: DismissAction) { self.completion = completion; self.onError = onError; self.dismiss = dismiss }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            if scan.pageCount > 0 { completion(scan.imageOfPage(at: 0)) }
            else { onError("No receipt page was saved. Please scan it again.") }
            dismiss()
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { dismiss() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onError("Could not scan the receipt: \(error.localizedDescription)")
            dismiss()
        }
    }
}

enum ReceiptParser {
    static func canConfirm(_ rows: [PriceItem]) -> Bool {
        !rows.isEmpty && rows.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && Money.isValid($0.quantity) && Money.parse($0.quantity) > 0
                && Money.isValid($0.unitPrice)
        }
    }
    static func parse(_ lines: [String]) -> (merchant: String, number: String, date: Date?, total: String, items: [PriceItem]) {
        let merchant = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        let number = lines.first(where: { $0.lowercased().contains("receipt") || $0.lowercased().contains("invoice") })?.components(separatedBy: .whitespaces).last ?? ""
        let expression = try! NSRegularExpression(pattern: #"^(.+?)\s+(\d+[.,]\d{2})$"#)
        let excluded = ["total", "tax", "vat", "subtotal", "change", "balance"]
        let date = lines.compactMap { line -> Date? in
            for format in ["dd/MM/yyyy", "MM/dd/yyyy", "yyyy-MM-dd"] {
                let formatter = DateFormatter(); formatter.dateFormat = format; formatter.isLenient = false
                for token in line.components(separatedBy: .whitespaces) { if let value = formatter.date(from: token) { return value } }
            }
            return nil
        }.first
        let totalLine = lines.last(where: { $0.lowercased().contains("total") && !$0.lowercased().contains("subtotal") }) ?? ""
        let total = totalLine.components(separatedBy: .whitespaces).last ?? ""
        let items = lines.compactMap { line -> PriceItem? in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = expression.firstMatch(in: line, range: range), let nameRange = Range(match.range(at: 1), in: line), let priceRange = Range(match.range(at: 2), in: line) else { return nil }
            let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
            guard !excluded.contains(where: { name.lowercased().contains($0) }) else { return nil }
            return PriceItem(kind: .material, name: name, unitPrice: String(line[priceRange]).replacingOccurrences(of: ",", with: "."))
        }
        return (merchant, number, date, total, items)
    }
}
