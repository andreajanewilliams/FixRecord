import SwiftUI
import Speech
import AVFoundation

struct SpeechTranscriptAccumulator {
    private var completed = ""
    private var current = ""
    private var firstSegmentTime: TimeInterval?
    private var lastSegmentEnd: TimeInterval?
    private var lastUpdateTime: TimeInterval?

    mutating func update(_ hypothesis: String, firstSegmentAt start: TimeInterval?, lastSegmentEnd end: TimeInterval?, receivedAt time: TimeInterval) -> String {
        let next = hypothesis.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty else { return joined(completed, current) }

        let old = current.lowercased()
        let new = next.lowercased()
        let oldWords = old.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let newWords = new.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let oldPairs = Set(zip(oldWords, oldWords.dropFirst()).map { "\($0) \($1)" })
        let newPairs = Set(zip(newWords, newWords.dropFirst()).map { "\($0) \($1)" })
        let overlaps = new.contains(old) || old.contains(new) || !oldPairs.isDisjoint(with: newPairs)
        let laterAudio: Bool
        let resetAudio: Bool
        if let start, let previousStart = firstSegmentTime, let previousEnd = lastSegmentEnd {
            laterAudio = start > previousStart + 0.25 && start >= previousEnd - 0.25
            resetAudio = start <= previousStart + 0.25 && end.map { $0 < previousEnd - 0.25 } == true
        } else {
            laterAudio = false
            resetAudio = false
        }
        let newPhraseAfterPause = lastUpdateTime != nil && time - lastUpdateTime! > 1.5 && oldWords.count >= 2 && !overlaps

        if !current.isEmpty && ((laterAudio && !new.contains(old)) || resetAudio || newPhraseAfterPause) {
            completed = joined(completed, current)
        }
        current = next
        firstSegmentTime = start
        lastSegmentEnd = end
        lastUpdateTime = time
        return joined(completed, current)
    }

    private func joined(_ first: String, _ second: String) -> String {
        first.isEmpty ? second : second.isEmpty ? first : first + " " + second
    }
}

@MainActor final class SpeechInputService: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var finalising = false
    @Published var message = ""
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var activeSession: UUID?
    private var transcript = SpeechTranscriptAccumulator()

    func start(onTranscript: @escaping (String) -> Void) async {
        guard !listening && !finalising else { return }
        let speechPermission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechPermission == .authorized else { message = "Allow speech recognition in Settings, or type your note."; return }
        let microphonePermission = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard microphonePermission else { message = "Allow microphone access in Settings, or type your note."; return }
        guard let recogniser = SFSpeechRecognizer(locale: .current), recogniser.isAvailable, recogniser.supportsOnDeviceRecognition else {
            message = "On-device speech recognition is unavailable for this language. You can type instead."
            return
        }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            self.request = request
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }
            engine.prepare()
            try engine.start()
            let session = UUID()
            activeSession = session
            transcript = SpeechTranscriptAccumulator()
            listening = true
            message = "Listening… Tap the microphone to stop."
            task = recogniser.recognitionTask(with: request) { result, error in
                Task { @MainActor in
                    guard self.activeSession == session else { return }
                    if let result {
                        let segments = result.bestTranscription.segments
                        let text = self.transcript.update(result.bestTranscription.formattedString,
                                                          firstSegmentAt: segments.first?.timestamp,
                                                          lastSegmentEnd: segments.last.map { $0.timestamp + $0.duration },
                                                          receivedAt: ProcessInfo.processInfo.systemUptime)
                        onTranscript(text)
                    }
                    if let error { self.message = error.localizedDescription; self.stop() }
                    else if result?.isFinal == true { self.stop() }
                }
            }
        } catch {
            message = "Could not start recording. You can type instead."
            stop()
        }
    }

    func stop() {
        activeSession = nil
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        listening = false
        finalising = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func finish() {
        guard listening else { return }
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        request?.endAudio()
        task?.finish()
        listening = false
        finalising = true
        message = "Finalising transcript…"
        let session = activeSession
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if activeSession == session && finalising { stop() }
        }
    }
}

struct VoiceTextInput: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var minEditorHeight: CGFloat = 95
    @StateObject private var speech = SpeechInputService()
    @State private var initialText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.bold()).foregroundStyle(Brand.navy)
                Spacer()
                Button {
                    if speech.listening { speech.finish() }
                    else {
                        initialText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await speech.start { transcript in
                            text = initialText.isEmpty ? transcript : initialText + " " + transcript
                        } }
                    }
                } label: { Image(systemName: speech.listening ? "stop.circle.fill" : "mic.fill").font(.title3).foregroundStyle(speech.listening ? .red : Brand.blue) }
                    .accessibilityLabel(speech.listening ? "Stop dictation" : "Dictate \(title)")
                    .disabled(speech.finalising)
            }
            ZStack(alignment: .topLeading) {
                if text.isEmpty { Text(placeholder).foregroundStyle(.secondary).padding(.top, 8).padding(.leading, 5) }
                TextEditor(text: $text).scrollContentBackground(.hidden).frame(minHeight: minEditorHeight)
            }
            if !speech.message.isEmpty { Text(speech.message).font(.caption).foregroundStyle(speech.listening ? Brand.blue : .secondary) }
        }.onDisappear { speech.stop() }
    }
}
