import SwiftUI
import PhotosUI
@preconcurrency import AVFoundation
import Vision
import ImageIO
import CoreImage

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
    var gravity: AVLayerVideoGravity = .resizeAspectFill
    func makeUIView(context: Context) -> PreviewView { let view = PreviewView(); view.layerSession.session = session; view.layerSession.videoGravity = gravity; return view }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var layerSession: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override init(frame: CGRect) { super.init(frame: frame); layerSession.videoGravity = .resizeAspectFill }
    required init?(coder: NSCoder) { fatalError() }
}

struct PhotoCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var job: Job
    let kind: PhotoKind
    var initialBeforeID: UUID? = nil
    @StateObject private var camera = CameraController()
    @State private var selectedItem: PhotosPickerItem?
    @State private var ghostOpacity = 0.40
    @State private var selectedBeforeID: UUID?
    private var beforePhotos: [JobPhoto] { job.photos.filter { $0.kind == .before } }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(kind == .before ? "Capture Before" : "MatchShot · Capture After").font(.title3.bold()).foregroundStyle(Brand.navy)
                if kind == .after && !beforePhotos.isEmpty {
                    Picker("Match to", selection: $selectedBeforeID) {
                        Text("No overlay").tag(nil as UUID?)
                        ForEach(Array(beforePhotos.enumerated()), id: \.element.id) { index, photo in
                            Text("Before \(index + 1)").tag(Optional(photo.id))
                        }
                    }.pickerStyle(.menu)
                    HStack { Text("Ghost opacity"); Slider(value: $ghostOpacity, in: 0.1...0.75) }
                }
                Color.black.aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        GeometryReader { geometry in
                            ZStack {
                                CameraPreview(session: camera.session, gravity: .resizeAspect)
                                if kind == .after, let photo = beforePhotos.first(where: { $0.id == selectedBeforeID }), let image = PhotoStore.image(photo.filename) {
                                    Image(uiImage: image).resizable().scaledToFit()
                                        .frame(width: geometry.size.width, height: geometry.size.height)
                                        .opacity(ghostOpacity)
                                }
                                if let error = camera.error {
                                    Text(error).padding().background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                                }
                            }.frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                if UIImagePickerController.isSourceTypeAvailable(.camera) { HStack { Button { camera.flashEnabled.toggle() } label: { Image(systemName: camera.flashEnabled ? "bolt.fill" : "bolt.slash") }; Spacer(); Button { camera.capture() } label: { Image(systemName: "circle.inset.filled").font(.system(size: 62)) }; Spacer(); Text(" ") }.padding(.horizontal, 30) }
                PhotosPicker(selection: $selectedItem, matching: .images) { Label("Choose Photo", systemImage: "photo.on.rectangle") }.buttonStyle(.bordered)
                if kind == .after && beforePhotos.isEmpty { Text("Add a before photo first to use the MatchShot ghost overlay.").font(.caption).foregroundStyle(.secondary) }

            }.padding()
        }.navigationTitle(kind == .before ? "Before photos" : "After photos")
            .task { selectedBeforeID = initialBeforeID; await camera.start() }
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
            dismiss()
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
    @Environment(\.dismiss) private var dismiss
    @Bindable var job: Job
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var merchant = ""
    @State private var number = ""
    @State private var message = ""
    @State private var date = Date()
    @State private var rows: [PriceItem] = []
    @State private var showingCamera = false
    @State private var pendingCapture: UIImage?
    @State private var processing = false
    @State private var processingStage = "Opening receipt…"
    @State private var savedNotice = ""
    @State private var showingReceipt = false
    @State private var uncertainItems: Set<UUID> = []
    @FocusState private var editingItem: Bool
    var body: some View {
        Group {
            if processing { processingView }
            else if image == nil { startView }
            else { reviewView }
        }.navigationTitle(image == nil ? "Add Materials" : "Receipt Details")
            .fullScreenCover(isPresented: $showingCamera, onDismiss: {
                guard let captured = pendingCapture else { return }
                pendingCapture = nil
                processing = true
                processingStage = "Opening receipt…"
                image = captured
                Task { await recognise(captured) }
            }) {
                ReceiptCamera { captured in pendingCapture = captured } onError: { message = $0 }
            }
            .onChange(of: item) { _, selected in
                guard let selected else { return }
                processing = true
                processingStage = "Loading photo…"
                Task {
                    if let data = try? await selected.loadTransferable(type: Data.self), let value = UIImage(data: data) {
                        image = value; await recognise(value)
                    } else { message = "Could not open this photo. Please choose another image."; processing = false }
                }
            }
    }
    private var processingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(Brand.pale).frame(width: 104, height: 104)
                ProgressView().controlSize(.large).tint(Brand.blue)
            }
            Text("Reading your receipt").font(.title2.bold()).foregroundStyle(Brand.navy)
            Text(processingStage).font(.subheadline).foregroundStyle(.secondary)
            Text("This can take a few moments.").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
    private var startView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.text.viewfinder").font(.system(size: 60)).foregroundStyle(Brand.navy).frame(width: 100, height: 100).background(Brand.pale, in: RoundedRectangle(cornerRadius: 25))
            Text("Scan a receipt").font(.title.bold()).foregroundStyle(Brand.navy)
            Text("Take a photo of your receipt and we'll extract the items and prices.").multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 28)
            if !savedNotice.isEmpty { Text(savedNotice).font(.subheadline).foregroundStyle(Brand.blue) }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.red).padding(.horizontal) }
            VStack(alignment: .leading, spacing: 12) {
                Label("Saves you time", systemImage: "clock")
                Label("Adds items to your job", systemImage: "plus.circle")
                Label("Review everything before saving", systemImage: "checkmark.circle")
            }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 38)
            Spacer()
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                PrimaryButton(title: "Scan Receipt", icon: "camera") { showingCamera = true }.padding(.horizontal)
            }
            PhotosPicker(selection: $item, matching: .images) { Label("Choose from Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity).padding(12) }.buttonStyle(.bordered).padding(.horizontal)
            Spacer().frame(height: 20)
        }
    }
    private var reviewView: some View {
        Form {
            Section {
                DisclosureGroup("View receipt", isExpanded: $showingReceipt) {
                    if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260) }
                }
                CurrencyPickerRow(currencyCode: Binding(get: { job.currencyCode }, set: { job.setCurrency($0) }))
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Items found") {
                ForEach($rows) { $row in
                    VStack(alignment: .leading, spacing: 6) {
                        if uncertainItems.contains(row.id) {
                            Label("Check this item", systemImage: "magnifyingglass").font(.caption).foregroundStyle(Brand.blue)
                        }
                        HStack {
                            TextField("Item", text: $row.name).focused($editingItem)
                            Button(role: .destructive) { rows.removeAll { $0.id == row.id } } label: {
                                Image(systemName: "trash").frame(width: 44, height: 44)
                            }.buttonStyle(.borderless).accessibilityLabel("Remove \(row.name)")
                        }
                        HStack(alignment: .bottom, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Qty").font(.caption).foregroundStyle(.secondary)
                                TextField("Qty", text: $row.quantity).keyboardType(.decimalPad).focused($editingItem)
                            }.frame(width: 55)
                            Text("×").foregroundStyle(.secondary).padding(.bottom, 3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Unit price").font(.caption).foregroundStyle(.secondary)
                                TextField("Unit price", text: $row.unitPrice).keyboardType(.decimalPad).focused($editingItem)
                            }
                            Spacer(minLength: 0)
                            Text(Money.format(row.total, currency: job.currencyCode)).font(.subheadline.bold())
                        }
                    }.padding(.bottom, 6)
                }
                Button { rows.append(PriceItem(kind: .material, name: "", unitPrice: "0")) } label: { Label("Add Item", systemImage: "plus") }
                Button("Retake Receipt") { showingCamera = true }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editingItem = false } }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                HStack {
                    Text("Items total").font(.subheadline)
                    Spacer()
                    Text(Money.format(rows.reduce(Decimal.zero) { $0 + $1.total }, currency: job.currencyCode)).font(.headline)
                }
                if !ReceiptParser.canConfirm(rows) {
                    Text(rows.isEmpty ? "Add an item to continue." : "Check item names, quantities and prices.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                PrimaryButton(title: "Add Items to Job", icon: "checkmark") { confirm() }
                    .disabled(!ReceiptParser.canConfirm(rows))
                Button { confirm(scanAnother: true) } label: {
                    Label("Add & Scan Another Receipt", systemImage: "plus.viewfinder").font(.subheadline.weight(.medium))
                }.disabled(!ReceiptParser.canConfirm(rows))
            }.padding().background(.regularMaterial)
        }
    }
    private func recognise(_ image: UIImage) async {
        processing = true
        rows = []; uncertainItems = []; message = ""; showingReceipt = false
        defer { processing = false }
        guard let cg = image.cgImage else { message = "Could not read this image. Please retake it or add items manually."; return }
        let orientation = image.imageOrientation.cgImagePropertyOrientation
        do {
            let scan = try await Task.detached(priority: .userInitiated) {
                try ReceiptOCR.read(cg, orientation: orientation) { stage in
                    Task { @MainActor in if processing { processingStage = stage } }
                }
            }.value
            let parsed = ReceiptParser.parse(ReceiptParser.lines(from: scan.fragments))
            uncertainItems = scan.needsReview ? Set(parsed.items.map(\.id)) : parsed.uncertainItems
            merchant = parsed.merchant; number = parsed.number; rows = parsed.items; date = parsed.date ?? Date()
            message = rows.isEmpty
                ? "We couldn't recognize any items from this receipt. You can enter them manually or retake the photo."
                : [ImageQuality.warning(for: image), scan.needsReview ? "Some text was unclear. Check the highlighted items." : nil,
                   parsed.warning.isEmpty ? nil : parsed.warning].compactMap { $0 }.joined(separator: " ")
        } catch { message = "Text recognition failed. You can add and edit materials manually." }
    }
    private func confirm(scanAnother: Bool = false) {
        guard ReceiptParser.canConfirm(rows), let image else { return }
        let filename: String
        do { filename = try PhotoStore.save(image) }
        catch { message = "Could not save the receipt. Please try again."; return }
        var record = ReceiptRecord(merchant: merchant, date: date, number: number, filename: filename, items: rows, confirmed: true)
        let confirmed = rows.map { row -> PriceItem in var item = row; item.sourceReceiptID = record.id; return item }
        record.items = confirmed
        var items = job.items; items.append(contentsOf: confirmed); job.items = items
        job.technicianConfirmed = false
        var receipts = job.receipts; receipts.append(record); job.receipts = receipts
        if scanAnother {
            savedNotice = "\(confirmed.count) items added to your job."
            rows = []; self.image = nil; item = nil; message = ""
        } else {
            rows = []; self.image = nil
            dismiss()
        }
    }
}

struct ReceiptCamera: View {
    let completion: (UIImage) -> Void
    let onError: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = ReceiptCaptureController()
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session).ignoresSafeArea()
            VStack {
                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Text("Scan Receipt").font(.headline)
                    Spacer()
                    Button(camera.automatic ? "Auto" : "Manual") { camera.automatic.toggle() }
                }.padding().background(.black.opacity(0.55))
                Spacer()
                HStack(spacing: 10) {
                    if camera.capturing { ProgressView().tint(.white) }
                    Text(camera.hint).font(.subheadline)
                }.multilineTextAlignment(.center).padding(12).background(.black.opacity(0.65), in: Capsule())
                Button { camera.capture() } label: {
                    Image(systemName: "circle.inset.filled").font(.system(size: 72))
                }.disabled(!camera.ready || camera.capturing).accessibilityLabel("Capture receipt").padding(24)
            }.foregroundStyle(.white)
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: camera.image) { _, image in
            if let image { completion(image); dismiss() }
        }
        .onChange(of: camera.error) { _, error in
            if let error { onError(error); dismiss() }
        }
    }
}

/// A single-page camera: both shutter and stable-document detection use the same capture path.
final class ReceiptCaptureController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    @Published var image: UIImage?
    @Published var error: String?
    @Published var hint = "Fit the receipt in view"
    @Published var automatic = true
    @Published var ready = false
    @Published var capturing = false
    private let queue = DispatchQueue(label: "com.fixrecord.receipt-camera")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var lastCheck = 0.0
    private var stableSince = 0.0
    private var previousBounds: CGRect?
    private var stopped = false
    @MainActor func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            error = "Allow camera access in Settings, or choose a receipt from Photos."; return
        }
        queue.async {
            guard !self.stopped else { return }
            do {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw CocoaError(.featureUnsupported) }
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input), self.session.canAddOutput(self.photoOutput), self.session.canAddOutput(self.videoOutput) else { throw CocoaError(.featureUnsupported) }
                self.session.addInput(input)
                self.session.addOutput(self.photoOutput)
                self.session.addOutput(self.videoOutput)
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.setSampleBufferDelegate(self, queue: self.queue)
                for output in [self.photoOutput as AVCaptureOutput, self.videoOutput as AVCaptureOutput] {
                    if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                }
                self.session.commitConfiguration()
                self.session.startRunning()
                DispatchQueue.main.async { self.ready = true }
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.error = "Could not open the camera. Choose a receipt from Photos or try again." }
            }
        }
    }
    func stop() {
        queue.async { self.stopped = true; self.session.stopRunning() }
    }
    @MainActor func capture() {
        guard ready, !capturing else { return }
        capturing = true
        hint = "Capturing…"
        queue.async {
            guard !self.stopped else { return }
            self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard !stopped, now - lastCheck > 0.3, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastCheck = now
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1; request.minimumConfidence = 0.65
        request.minimumAspectRatio = 0.08; request.minimumSize = 0.12
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
        var detectedBounds = request.results?.first?.boundingBox
        if detectedBounds.map(ReceiptAutoCapture.accepts) != true {
            // Pale paper on a light surface may have no detectable outline.
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .fast
            text.minimumTextHeight = 0.006
            text.usesLanguageCorrection = false
            try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([text])
            let observations = text.results ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            if ReceiptAutoCapture.looksLikeReceipt(lines) {
                detectedBounds = observations.reduce(CGRect.null) { $0.union($1.boundingBox) }
            } else { detectedBounds = nil }
        }
        guard let bounds = detectedBounds, ReceiptAutoCapture.accepts(bounds) else {
            previousBounds = nil; stableSince = now
            DispatchQueue.main.async { if !self.capturing { self.hint = "Fit the receipt in view · or tap to capture" } }
            return
        }
        if let previous = previousBounds,
           abs(previous.midX - bounds.midX) < 0.04, abs(previous.midY - bounds.midY) < 0.04,
           abs(previous.width - bounds.width) < 0.04, abs(previous.height - bounds.height) < 0.04 {
            let stable = now - stableSince > 1.5
            DispatchQueue.main.async {
                guard !self.capturing else { return }
                self.hint = self.automatic ? "Receipt detected · hold steady" : "Tap to capture"
                if stable && self.automatic { self.capture() }
            }
        } else { stableSince = now; previousBounds = bounds }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            DispatchQueue.main.async { self.error = "Could not capture the receipt. Please try again." }; return
        }
        DispatchQueue.main.async { self.image = image }
    }
}

enum ReceiptAutoCapture {
    static func accepts(_ bounds: CGRect) -> Bool {
        !bounds.isNull && bounds.width * bounds.height > 0.06 && bounds.width > 0.1 && bounds.height > 0.2
            && bounds.minX > 0.005 && bounds.maxX < 0.995 && bounds.minY > 0.005 && bounds.maxY < 0.995
    }
    static func looksLikeReceipt(_ lines: [String]) -> Bool {
        lines.count >= 4 && lines.filter {
            $0.range(of: #"\d+[.,]\d{2}\b"#, options: .regularExpression) != nil
        }.count >= 2
    }
}

/// All image preparation and recognition stays on the device. Keep the original for review.
enum ReceiptOCR {
    struct Scan {
        let fragments: [ReceiptParser.Fragment]
        let needsReview: Bool
    }
    static func read(_ image: CGImage, orientation: CGImagePropertyOrientation,
                     progress: @Sendable (String) -> Void = { _ in }) throws -> Scan {
        let original = CIImage(cgImage: image).oriented(orientation)
        let context = CIContext(options: [.cacheIntermediates: false])
        func recognise(_ input: CIImage) throws -> [ReceiptParser.Fragment] {
            guard let rendered = context.createCGImage(input, from: input.extent) else { return [] }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.minimumTextHeight = 0.004 // Keep small text on long receipts.
            try VNImageRequestHandler(cgImage: rendered).perform([request])
            return (request.results ?? []).compactMap { observation in
                guard let text = observation.topCandidates(1).first else { return nil }
                return ReceiptParser.Fragment(text: text.string, x: observation.boundingBox.midX,
                                              y: observation.boundingBox.midY, height: observation.boundingBox.height,
                                              confidence: text.confidence)
            }
        }
        progress("Reading the text…")
        let first = try recognise(original)
        progress("Straightening and enhancing…")
        var prepared = original
        let rectangle = VNDetectRectanglesRequest()
        rectangle.maximumObservations = 1; rectangle.minimumConfidence = 0.85
        rectangle.minimumAspectRatio = 0.1; rectangle.minimumSize = 0.3
        try? VNImageRequestHandler(ciImage: original).perform([rectangle])
        if let page = rectangle.results?.first,
           page.boundingBox.width * page.boundingBox.height > 0.3,
           first.allSatisfy({ page.boundingBox.insetBy(dx: -0.015, dy: -0.015).contains(CGPoint(x: $0.x, y: $0.y)) }) {
            let size = original.extent.size
            func point(_ value: CGPoint) -> CIVector { CIVector(x: value.x * size.width + original.extent.minX, y: value.y * size.height + original.extent.minY) }
            prepared = original.applyingFilter("CIPerspectiveCorrection", parameters: [
                "inputTopLeft": point(page.topLeft), "inputTopRight": point(page.topRight),
                "inputBottomLeft": point(page.bottomLeft), "inputBottomRight": point(page.bottomRight)
            ])
        }
        prepared = prepared.applyingFilter("CIColorControls", parameters: ["inputSaturation": 0, "inputContrast": 1.15])
        progress("Checking item names and prices…")
        let second = (try? recognise(prepared)) ?? []
        progress("Checking totals…")
        let a = ReceiptParser.parse(ReceiptParser.lines(from: first))
        let b = ReceiptParser.parse(ReceiptParser.lines(from: second))
        // Do not select an enhanced pass which loses items or changes the printed total.
        func confidence(_ fragments: [ReceiptParser.Fragment]) -> Float {
            fragments.isEmpty ? 0 : fragments.reduce(Float.zero) { $0 + $1.confidence } / Float(fragments.count)
        }
        let improved = b.items.count > a.items.count || (first.contains { $0.confidence < 0.5 } && confidence(second) > confidence(first) + 0.1)
        let useSecond = improved && b.items.count >= a.items.count && !b.items.isEmpty && (a.total.isEmpty || a.total == b.total)
        let selected = useSecond ? second : first
        let pricesChanged = a.items.map(\.total) != b.items.map(\.total)
        return Scan(fragments: selected, needsReview: pricesChanged || a.items.map(\.name) != b.items.map(\.name) || selected.contains { $0.confidence < 0.5 })
    }
}

enum ReceiptParser {
    struct Fragment {
        let text: String
        let x: CGFloat
        let y: CGFloat
        let height: CGFloat
        var confidence: Float = 1
    }

    static func lines(from fragments: [Fragment]) -> [String] {
        var rows: [[Fragment]] = []
        for fragment in fragments.sorted(by: { $0.y == $1.y ? $0.x < $1.x : $0.y > $1.y }) {
            if let index = rows.indices.last, let first = rows[index].first,
               abs(first.y - fragment.y) <= max(0.001, min(first.height, fragment.height) * 0.55) {
                rows[index].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { row in row.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ") }
    }

    static func canConfirm(_ rows: [PriceItem]) -> Bool {
        !rows.isEmpty && rows.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && Money.isValid($0.quantity) && Money.parse($0.quantity) > 0
                && Money.isValid($0.unitPrice)
        }
    }
    static func parse(_ inputLines: [String]) -> (merchant: String, number: String, date: Date?, total: String, items: [PriceItem], warning: String, uncertainItems: Set<UUID>) {
        let lines = inputLines.map { line in
            // OCR can merge a left-hand note with the totals column on the right.
            line.replacingOccurrences(of: #"(?i)^.*?\b((?:sub\s*total|grand\s*total|(?:sales\s+)?tax|vat|total)\s*:\s*(?:\p{Sc}\s*)?\d[\d., ]*)$"#, with: "$1", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"(?i)(\d[.,]\d{2})\s*[TFANX]$"#, with: "$1", options: .regularExpression)
        }
        let merchant = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        let number = lines.first(where: { $0.lowercased().contains("receipt") || $0.lowercased().contains("invoice") })?.components(separatedBy: .whitespaces).last ?? ""
        let amount = #"(?:\d+(?:[., ']\d{3})*[.,]\d{2}|[.,]\d{2})"#
        let currency = #"(?:\p{Sc}|ZAR|USD|EUR|GBP|CAD|AUD|R)"#
        let pricedLine = try! NSRegularExpression(pattern: "(?i)^(.+?)\\s+(?:\(currency)\\s*)?(\(amount))\\s*(?:USD|EUR|GBP|ZAR|CAD|AUD)?$" )
        let amountOnly = try! NSRegularExpression(pattern: "(?i)^(?:\(currency)\\s*)?(\(amount))\\s*(?:USD|EUR|GBP|ZAR|CAD|AUD)?$" )
        let quantityPrefix = try! NSRegularExpression(pattern: #"(?i)^(\d+(?:[.,]\d+)?)\s*[x×]\s+(.+)$"#)
        let unitPriceSuffix = try! NSRegularExpression(pattern: "(?i)^(.+?)\\s+@\\s*(?:\(currency)\\s*)?(\(amount))$" )
        let excluded = try! NSRegularExpression(pattern: #"(?i)^(?:sub\s*total|grand\s*total|total|tax|vat|change|balance|cash|card\b|payment|tender|discount|amount\s+(?:due|paid|tendered|charged)|paid|purchase\s+total|net\s+total|order\s+total|receipt|invoice|store\b|reg\b|cashier|transaction|register|trans\b|member\s+discount|loyalty|savings|refund|coupon|sales\s+tax|state\s+tax|local\s+tax|food\s+tax|taxable|non.?taxable|visa|mastercard|amex|debit|credit|auth|approval|tip|gratuity|thank|you\s+saved|items?\s+sold)\b"#)
        func capture(_ regex: NSRegularExpression, in text: String, at index: Int) -> String? {
            guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
                  let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func decimal(_ text: String) -> Decimal? { Money.decimal(text.replacingOccurrences(of: "'", with: "")) }
        let date = lines.compactMap { line -> Date? in
            for format in ["dd/MM/yyyy", "MM/dd/yyyy", "yyyy-MM-dd"] {
                let formatter = DateFormatter(); formatter.dateFormat = format; formatter.isLenient = false
                for token in line.components(separatedBy: .whitespaces) { if let value = formatter.date(from: token) { return value } }
            }
            return nil
        }.first
        let totalLine = lines.last(where: { $0.range(of: #"(?i)^(?:grand\s+)?total\b"#, options: .regularExpression) != nil }) ?? ""
        let total = totalLine.components(separatedBy: .whitespaces).last ?? ""
        // Strip explicit stock codes, including a wrapped SKU line, without removing sizes.
        let stockCode = try! NSRegularExpression(pattern: #"(?i)\s*(?:\(SKU\s*:?\s*[A-Z0-9-]+\)|#SKU\s*:?\s*[A-Z0-9-]+)"#)
        let cleaned = lines.map { stockCode.stringByReplacingMatches(in: $0, range: NSRange($0.startIndex..<$0.endIndex, in: $0), withTemplate: "").trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var itemLines: [String] = []
        for line in cleaned {
            if capture(amountOnly, in: line, at: 1) != nil,
               let previous = itemLines.last,
               capture(pricedLine, in: previous, at: 1) == nil,
               previous.rangeOfCharacter(from: .letters) != nil,
               excluded.firstMatch(in: previous, range: NSRange(previous.startIndex..<previous.endIndex, in: previous)) == nil {
                itemLines[itemLines.count - 1] = previous + " " + line
            } else { itemLines.append(line) }
        }
        let quantityDetail = try! NSRegularExpression(pattern: "(?i)^(\\d+(?:[.,]\\d+)?)\\s*(?:lb|lbs|kg|ea)?\\s*@\\s*(?:\(currency)\\s*)?(\(amount))(?:\\s*/\\s*(?:lb|lbs|kg|ea))?$" )
        let tableHeader = lines.first { line in
            line.range(of: #"(?i)\b(?:description|item)\b.*\b(?:qty|quantity)\b.*\b(?:price|rate)\b"#, options: .regularExpression) != nil
        }
        let numberedTable = tableHeader?.range(of: #"(?i)^(?:no\.?|#|item\s+no\.?)\s"#, options: .regularExpression) != nil
        let tableRow = try! NSRegularExpression(pattern: "(?i)^(.+?)\\s+(\\d+(?:[.,]\\d+)?)\\s+(?:\(currency)\\s*)?(\(amount))\\s+(?:\(currency)\\s*)?(\(amount))$")
        let missingQuantityRow = try! NSRegularExpression(pattern: "(?i)^(.+?)\\s+(?:\(currency)\\s*)?(\(amount))\\s+(?:\(currency)\\s*)?(\(amount))$")
        var inferredLines: Set<String> = []
        if tableHeader != nil {
            itemLines = itemLines.map { line in
                var name: String
                var count: Decimal
                var unit: Decimal
                var total: Decimal
                var inferred = false
                if let description = capture(tableRow, in: line, at: 1),
                   let q = capture(tableRow, in: line, at: 2).flatMap(decimal),
                   let u = capture(tableRow, in: line, at: 3).flatMap(decimal),
                   let t = capture(tableRow, in: line, at: 4).flatMap(decimal), q > 0 {
                    name = description; count = q; unit = u; total = t
                    if Money.rounded(count * unit) != Money.rounded(total) {
                        // Preserve the printed cost rather than invent a conflicting line total.
                        count = 1; unit = total; inferred = true
                    }
                } else if let description = capture(missingQuantityRow, in: line, at: 1),
                          let u = capture(missingQuantityRow, in: line, at: 2).flatMap(decimal),
                          let t = capture(missingQuantityRow, in: line, at: 3).flatMap(decimal), u > 0, t > 0 {
                    let ratio = t / u
                    var rounded = Decimal(); var value = ratio
                    NSDecimalRound(&rounded, &value, 0, .plain)
                    guard rounded > 0, rounded <= 10000, Money.rounded(rounded * u) == Money.rounded(t) else { return line }
                    name = description; count = rounded; unit = u; total = t; inferred = true
                } else { return line }
                if numberedTable { name = name.replacingOccurrences(of: #"^\d+\s+"#, with: "", options: .regularExpression) }
                func price(_ value: Decimal) -> String { NSDecimalNumber(decimal: Money.rounded(value)).description(withLocale: Locale(identifier: "en_US_POSIX")) }
                // Keep two decimal places so the normal receipt parser recognises the amounts.
                let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.numberStyle = .decimal; formatter.usesGroupingSeparator = false
                formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
                let unitText = formatter.string(from: NSDecimalNumber(decimal: unit)) ?? price(unit)
                let totalText = formatter.string(from: NSDecimalNumber(decimal: total)) ?? price(total)
                let normalized = "\(NSDecimalNumber(decimal: count).stringValue)x \(name) @ \(unitText) \(totalText)"
                if inferred { inferredLines.insert(normalized) }
                return normalized
            }
        }
        var uncertainItems: Set<UUID> = []
        let items = itemLines.enumerated().compactMap { index, line -> PriceItem? in
            guard quantityDetail.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)) == nil,
                  var name = capture(pricedLine, in: line, at: 1),
                  let totalText = capture(pricedLine, in: line, at: 2),
                  let total = decimal(totalText), total >= 0,
                  name.rangeOfCharacter(from: .letters) != nil,
                  excluded.firstMatch(in: name, range: NSRange(name.startIndex..<name.endIndex, in: name)) == nil else { return nil }

            // Negative lines are adjustments/returns, not positive material costs.
            guard name.range(of: #"[-−]\s*[$£€]?\s*$"#, options: .regularExpression) == nil else { return nil }
            name = name.replacingOccurrences(of: #"^\d{6,14}\s+"#, with: "", options: .regularExpression)
            var needsReview = inferredLines.contains(line)
            var quantity: Decimal = 1
            if let count = capture(quantityPrefix, in: name, at: 1),
               let parsed = decimal(count), parsed > 0,
               let description = capture(quantityPrefix, in: name, at: 2) {
                quantity = parsed
                name = description
            }

            var unitPrice = total
            // Common US layout: item total, followed by "2 @ 3.49" or "1.25 lb @ 4.00/lb".
            if index + 1 < itemLines.count,
               let countText = capture(quantityDetail, in: itemLines[index + 1], at: 1),
               let count = decimal(countText), count > 0,
               let priceText = capture(quantityDetail, in: itemLines[index + 1], at: 2),
               let price = decimal(priceText) {
                if Money.rounded(count * price) == Money.rounded(total) {
                    quantity = count; unitPrice = price
                } else { needsReview = true }
            }
            if let description = capture(unitPriceSuffix, in: name, at: 1),
               let amountText = capture(unitPriceSuffix, in: name, at: 2),
               let candidate = decimal(amountText), Money.rounded(candidate * quantity) == Money.rounded(total) {
                name = description
                unitPrice = candidate
            } else if unitPrice == total, quantity > 1, index + 1 < itemLines.count,
                      let amountText = capture(amountOnly, in: itemLines[index + 1], at: 1),
                      let candidate = decimal(amountText), Money.rounded(candidate * quantity) == Money.rounded(total) {
                unitPrice = candidate
            } else if unitPrice == total, quantity > 1 {
                var divided = total / quantity
                NSDecimalRound(&unitPrice, &divided, 4, .plain)
            }
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: " @"))
            guard !name.isEmpty else { return nil }
            let item = PriceItem(kind: .material, name: name,
                                 quantity: NSDecimalNumber(decimal: quantity).stringValue,
                                 unitPrice: NSDecimalNumber(decimal: unitPrice).stringValue)
            if needsReview { uncertainItems.insert(item.id) }
            return item
        }
        let itemTotal = items.reduce(Decimal.zero) { $0 + $1.total }
        let subtotalLine = lines.first { $0.lowercased().hasPrefix("subtotal") || $0.lowercased().hasPrefix("sub total") }
        let subtotal = subtotalLine.flatMap { capture(pricedLine, in: $0, at: 2) }.flatMap(decimal)
        let printedTotal = capture(pricedLine, in: totalLine, at: 2).flatMap(decimal)
        let hasAdjustments = lines.contains { $0.range(of: #"(?i)\b(tax|vat|discount|coupon|savings)\b"#, options: .regularExpression) != nil }
        func adjustmentTotal(_ pattern: String) -> Decimal {
            lines.filter { $0.range(of: pattern, options: .regularExpression) != nil }
                .compactMap { line in
                    let unsigned = line.replacingOccurrences(of: #"[-−](?=\s*(?:\p{Sc}|\d))"#, with: "", options: .regularExpression)
                    return capture(pricedLine, in: unsigned, at: 2).flatMap(decimal)
                }.reduce(.zero, +)
        }
        let discounts = adjustmentTotal(#"(?i)^(?:member\s+discount|discount|coupon)\b"#)
        let taxes = adjustmentTotal(#"(?i)^(?:(?:sales|state|local|food)\s+)?(?:tax|vat)\b"#)
        let netItems = Money.rounded(itemTotal - discounts)
        let warning: String
        if let subtotal, Money.rounded(itemTotal) != Money.rounded(subtotal), netItems != Money.rounded(subtotal) {
            warning = "Item totals differ from the receipt subtotal. Check the prices and any discounts before adding."
        } else if let printedTotal, Money.rounded(netItems + taxes) != Money.rounded(printedTotal) {
            warning = "Items do not match the receipt total. Check for missing items or prices."
        } else if !uncertainItems.isEmpty {
            warning = "Some quantities do not match their printed totals. Check the highlighted items."
        } else if hasAdjustments {
            warning = "Tax and discounts are not added to material prices."
        } else { warning = "" }
        return (merchant, number, date, total, items, warning, uncertainItems)
    }
}
