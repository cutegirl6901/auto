import AVFoundation
import Foundation
import TuneCore

/// Drives the piano measurement flow: the user picks a key, plays it, and the
/// app measures that string's inharmonicity.
///
/// This is separate from TunerViewModel on purpose. Tuning wants a continuous
/// running estimate; measurement wants one good capture per key and then a
/// definite answer. Mixing the two made both harder to reason about.
@MainActor
final class PianoMeasureViewModel: ObservableObject {
    enum Stage: Equatable {
        case idle
        case listening
        case measuring
        case done
        case failed(String)
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var lastMeasurement: InharmonicityMeasurement?
    @Published private(set) var measurements: [Int: InharmonicityMeasurement] = [:]
    @Published var selectedMIDI: Int = 69

    private let audioEngine = TunerAudioEngine()
    private let speech = SpeechFeedback()
    private var isListening = false
    private var capturedSamples: [Float] = []
    private var capturedSampleRate: Double = 48000
    private var captureStartedAt: Date?
    private var captureTask: Task<Void, Never>?

    /// True while we are talking. The speaker leaks into the microphone, so a
    /// capture must not start or continue while our own voice is playing.
    private var isSpeaking = false

    /// Audio stays ignored for a moment after speech ends: the capture buffer
    /// is about 370 ms long and still holds the tail of the sentence.
    private var speechCooldownUntil: Date = .distantPast

    private static let speechCooldown: TimeInterval = 0.5

    /// How long to listen after the string is played before analysing.
    private let captureWindow: TimeInterval = 0.45

    var canMeasure: Bool { !isListening }

    /// Number of keys measured so far, for the summary.
    var measuredCount: Int { measurements.count }

    var profile: InharmonicityProfile {
        InharmonicityProfile(measurements: Array(measurements.values), name: "实测")
    }

    var expectedFrequency: Double {
        PitchMath.frequency(forMIDI: Double(selectedMIDI))
    }

    /// Starts listening for one string. Called when the user taps Measure.
    func startMeasure(settings: SpeechSettings) {
        guard !isListening else { return }
        lastMeasurement = nil
        capturedSamples.removeAll(keepingCapacity: true)
        captureStartedAt = nil

        // Ask for microphone access first. Without this the prompt never
        // appears on a fresh install and the capture silently fails.
        if AVAudioSession.sharedInstance().recordPermission == .undetermined {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] _ in
                DispatchQueue.main.async {
                    self?.beginCapture(settings: settings)
                }
            }
            return
        }
        beginCapture(settings: settings)
    }

    /// Starts capturing once permission is known.
    private func beginCapture(settings: SpeechSettings) {
        if AVAudioSession.sharedInstance().recordPermission == .denied {
            stage = .failed("麦克风权限未开启，请到系统设置里允许调音节拍器使用麦克风")
            speech.speak("麦克风权限未开启", settings: settings, forceAppVoice: true)
            return
        }
        do {
            speech.onFinish = { [weak self] in
                guard let self else { return }
                self.isSpeaking = false
                self.speechCooldownUntil = Date().addingTimeInterval(Self.speechCooldown)
            }
            try audioEngine.start { [weak self] estimate, samples, sampleRate in
                self?.handle(estimate: estimate, samples: samples, sampleRate: sampleRate)
            }
            isListening = true
            stage = .listening
            isSpeaking = true
            speech.speak("请弹奏 \(Note(midi: selectedMIDI).displayName)", settings: settings, forceAppVoice: true)
        } catch {
            isListening = false
            stage = .failed(TunerAudioEngineError.chineseMessage(for: error))
            speech.speak("麦克风无法开启", settings: settings, forceAppVoice: true)
        }
    }

    func cancel(settings: SpeechSettings) {
        captureTask?.cancel()
        captureTask = nil
        stopEngine()
        stage = .idle
        isSpeaking = true
        speech.speak("已取消", settings: settings, forceAppVoice: true)
    }

    func reset(settings: SpeechSettings) {
        captureTask?.cancel()
        captureTask = nil
        stopEngine()
        measurements.removeAll()
        lastMeasurement = nil
        stage = .idle
        isSpeaking = true
        speech.speak("已清除全部测量", settings: settings, forceAppVoice: true)
    }

    private func stopEngine() {
        audioEngine.stop()
        isListening = false
        isSpeaking = false
    }

    private func handle(estimate: PitchEstimate, samples: [Float], sampleRate: Double) {
        guard isListening else { return }

        // With echo cancellation the speaker's output is subtracted from the
        // input, so a prompt playing does not need to block the capture.
        // Without it, the microphone is ignored for the whole prompt and for a
        // moment afterwards while its tail is still buffered.
        if !AudioSessionManager.isEchoCancellationActive {
            guard !isSpeaking, Date() >= speechCooldownUntil else { return }
        }

        // Wait for a real attack. A quiet room should not start a measurement.
        guard estimate.frequency != nil, estimate.rms >= 0.006 else { return }

        if captureStartedAt == nil {
            captureStartedAt = Date()
            capturedSampleRate = sampleRate
        }
        capturedSamples = samples

        guard let started = captureStartedAt else { return }
        let elapsed = Date().timeIntervalSince(started)
        if elapsed >= captureWindow {
            finishMeasurement()
        }
    }

    private func finishMeasurement() {
        stopEngine()
        stage = .measuring

        let samples = capturedSamples
        let sampleRate = capturedSampleRate
        let midi = selectedMIDI
        let expected = expectedFrequency

        captureTask = Task { @MainActor [weak self] in
            let measurement = Inharmonicity.measure(
                midi: midi,
                samples: samples,
                sampleRate: sampleRate,
                expectedF1: expected
            )
            guard let self else { return }
            guard !Task.isCancelled else { return }
            self.apply(measurement)
        }
    }

    private func apply(_ measurement: InharmonicityMeasurement?) {
        guard let measurement else {
            stage = .failed("没有测到清晰的泛音，请再弹一次")
            return
        }
        lastMeasurement = measurement
        measurements[measurement.midi] = measurement
        stage = .done
    }

    /// Spoken summary of a finished measurement, graded rather than numeric,
    /// because a coefficient like 0.00021 means nothing to a player.
    func describe(_ measurement: InharmonicityMeasurement) -> String {
        let grade: String
        if measurement.confidence < 0.4 {
            grade = "结果不太可靠，建议再测一次"
        } else if measurement.b >= 3e-4 {
            grade = "非谐性大"
        } else if measurement.b >= 1e-4 {
            grade = "非谐性中等"
        } else {
            grade = "非谐性小"
        }
        return "\(Note(midi: measurement.midi).displayName) 测好了，\(grade)"
    }
}
