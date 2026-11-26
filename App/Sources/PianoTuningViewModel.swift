import AVFoundation
import Foundation
import TuneCore

/// Curve-based tuning for a piano, one key at a time.
///
/// Unlike the general tuner, the target here is not equal temperament: it is
/// the selected stretch curve's frequency for the key, optionally pushed past
/// the target by the overpull amount when the string is flat. The user plays a
/// string, the app reports how far off it is, and the estimate is spoken in
/// words.
@MainActor
final class PianoTuningViewModel: ObservableObject {
    /// How a key currently reads.
    enum Verdict: Equatable {
        case waiting
        case tooFlat(Double)   // cents below target
        case tooSharp(Double)  // cents above target
        case inTune(Double)    // cents, within tolerance
        case uncertain
    }

    @Published private(set) var verdict: Verdict = .waiting
    @Published private(set) var isListening = false
    @Published private(set) var errorMessage: String?
    @Published var selectedMIDI: Int = 69
    @Published var useOverpull: Bool = true
    /// When on, the app works out which key is being played instead of relying
    /// on the user having picked it first.
    @Published var isAutoDetecting: Bool = false

    /// True when this device cancels the speaker's echo in the microphone, so
    /// listening can continue while the app speaks. Read after the session is
    /// configured; it stays false on devices that cannot do it.
    @Published private(set) var hasEchoCancellation = false

    /// Tolerance in cents for calling a string in tune.
    var toleranceCents: Double = 3

    /// How far a reading may sit from the chosen key and still count as that
    /// key. Half a semitone is the natural boundary: inside it the current key
    /// is still the nearest note, so switching there would only cause the
    /// target to flicker while a string is being brought into tune.
    var autoSwitchThresholdCents: Double = 50

    private let audioEngine = TunerAudioEngine()
    private let speech = SpeechFeedback()
    private var lastSpokenVerdict: String?
    private var lastSoundAt: Date?

    /// True while our own voice is playing.
    ///
    /// The microphone is ignored completely during this window. A level
    /// threshold cannot separate the two: a quiet piano note and a loud
    /// announcement overlap in volume, and the speaker feeds straight back
    /// into the microphone. Any frame analysed while speaking risks being
    /// reported as a string, so none are.
    private var isSpeaking = false

    /// Guards against two permission prompts being requested at once.
    private var isRequestingPermission = false

    /// Audio is ignored until this moment after speech ends, so the tail of the
    /// sentence, which is still inside the capture buffer, cannot be read as a
    /// note. The buffer is about 370 ms long.
    private var speechCooldownUntil: Date = .distantPast

    private static let speechCooldown: TimeInterval = 0.5

    var noteName: String { Note(midi: selectedMIDI).displayName }

    var canStart: Bool { !isListening }

    /// Frequency of the key under the curve, before any overpull.
    func targetFrequency(curve: StretchCurve, concertA: Double = 440) -> Double {
        curve.stretchedFrequency(forMIDI: selectedMIDI, concertA: concertA)
    }

    /// Frequency to aim for right now: the curve target plus overpull when the
    /// string is flat and overpull is enabled.
    func aimingFrequency(curve: StretchCurve, concertA: Double = 440) -> Double {
        let target = targetFrequency(curve: curve, concertA: concertA)
        guard useOverpull else { return target }
        let flatCents = flatnessCents(from: verdict)
        guard flatCents > 0 else { return target }
        return Overpull.targetFrequency(forKey: selectedMIDI, stretchedTarget: target, flatCents: flatCents)
    }

    func start(curve: StretchCurve, settings: SpeechSettings) {
        guard !isListening else { return }
        errorMessage = nil
        verdict = .waiting

        // Ask for microphone access before starting the engine. The engine only
        // refuses a denied permission; on an undetermined one the system would
        // never show the prompt and the engine would fail silently.
        if AVAudioSession.sharedInstance().recordPermission == .undetermined {
            guard !isRequestingPermission else { return }
            isRequestingPermission = true
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isRequestingPermission = false
                    self.beginListening(curve: curve, settings: settings)
                }
            }
            return
        }
        beginListening(curve: curve, settings: settings)
    }

    /// Starts the engine once permission is known.
    private func beginListening(curve: StretchCurve, settings: SpeechSettings) {
        if AVAudioSession.sharedInstance().recordPermission == .denied {
            errorMessage = "麦克风权限未开启，请到系统设置里允许调音节拍器使用麦克风"
            speech.speak(errorMessage ?? "", settings: settings, forceAppVoice: true)
            return
        }
        do {
            speech.onFinish = { [weak self] in
                self?.finishSpeaking(settings: settings)
            }
            try audioEngine.start { [weak self] estimate, _, _ in
                self?.handle(estimate: estimate, curve: curve)
            }
            isListening = true
            hasEchoCancellation = AudioSessionManager.isEchoCancellationActive
            speak(isAutoDetecting ? "开始调律，请弹奏琴弦" : "开始调律 \(noteName)", settings: settings)
        } catch {
            isListening = false
            errorMessage = TunerAudioEngineError.chineseMessage(for: error)
            speech.speak("麦克风无法开启", settings: settings, forceAppVoice: true)
        }
    }

    func stop(settings: SpeechSettings) {
        speech.stop()
        audioEngine.stop()
        isListening = false
        isSpeaking = false
        speechCooldownUntil = .distantPast
        lastSpokenVerdict = nil
        lastSoundAt = nil
        verdict = .waiting
        let _ = settings
    }

    /// Spoken form of the current verdict.
    func spokenVerdict() -> String {
        switch verdict {
        case .waiting:
            return isAutoDetecting ? "等待弹奏" : "等待弹奏 \(noteName)"
        case .inTune:
            return "\(noteName) 准了"
        case .tooFlat(let cents):
            return "\(noteName) 偏低 \(Int(cents.rounded())) 音分"
        case .tooSharp(let cents):
            return "\(noteName) 偏高 \(Int(cents.rounded())) 音分"
        case .uncertain:
            return "信号不清，请再弹一次"
        }
    }

    /// Minimum level to treat a frame as a struck string.
    private static let quietThreshold: Double = 0.006

    private static let minimumConfidence: Double = 0.6

    private func handle(estimate: PitchEstimate, curve: StretchCurve) {
        guard isListening else { return }

        let now = Date()

        // Echo cancellation removes the speaker's output from the input, so
        // nothing needs to be muted and no extra threshold is needed while
        // speaking: the string alone is what the analyser sees.
        //
        // Without it there is nothing to separate our own voice from a string.
        // The microphone is then ignored for the whole announcement and for a
        // moment afterwards, while the tail of it is still buffered.
        if !AudioSessionManager.isEchoCancellationActive {
            guard !isSpeaking, now >= speechCooldownUntil else { return }
        }

        guard let frequency = estimate.frequency,
              estimate.confidence >= Self.minimumConfidence,
              estimate.rms >= Self.quietThreshold else {
            let silence = lastSoundAt.map { now.timeIntervalSince($0) } ?? .infinity
            if silence >= 0.35 { verdict = .waiting }
            return
        }
        lastSoundAt = now

        if isAutoDetecting {
            adoptDetectedNote(for: frequency)
        }

        let target = targetFrequency(curve: curve)
        guard target > 0, let cents = PitchMath.cents(from: frequency, to: target) else {
            verdict = .uncertain
            return
        }

        if abs(cents) <= toleranceCents {
            verdict = .inTune(cents)
        } else if cents < 0 {
            verdict = .tooFlat(-cents)
        } else {
            verdict = .tooSharp(cents)
        }
    }

    /// Decides which key is being played while auto-detecting.
    ///
    /// A reading stays with the currently selected key until it is clearly a
    /// different note. Snapping to the nearest semitone every frame would make
    /// the target jump around whenever a string sits near the boundary or the
    /// detector slips by an octave for a moment.
    private func adoptDetectedNote(for frequency: Double) {
        let currentTarget = PitchMath.frequency(forMIDI: Double(selectedMIDI))
        if currentTarget > 0,
           let cents = PitchMath.cents(from: frequency, to: currentTarget),
           abs(cents) <= autoSwitchThresholdCents {
            return
        }
        guard let nearest = PitchMath.nearestNote(to: frequency) else { return }
        guard nearest.note.midi != selectedMIDI else { return }
        selectedMIDI = nearest.note.midi
    }

    /// Announces the verdict once, and only when it changes.
    ///
    /// Nothing is spoken while our own voice is playing: a reading taken then
    /// would trigger another announcement, and the two would feed each other.
    func announceIfChanged(settings: SpeechSettings) {
        let text = spokenVerdict()
        guard text != lastSpokenVerdict else { return }
        lastSpokenVerdict = text

        guard !isSpeaking else { return }
        guard case .waiting = verdict else {
            speak(text, settings: settings)
            return
        }
    }

    /// Announces which note automatic detection has settled on.
    ///
    /// Spoken only after speech has finished, so it cannot be mistaken for a
    /// string by the analyser.
    func announceDetectedNote(settings: SpeechSettings) {
        guard !isSpeaking else { return }
        guard noteName != lastSpokenVerdict else { return }
        lastSpokenVerdict = noteName
        speak(noteName, settings: settings)
    }

    /// Speaks and marks the microphone as busy for the duration.
    private func speak(_ text: String, settings: SpeechSettings) {
        isSpeaking = true
        // Tuner screens must use the app's synthesizer: it reports when speech
        // finishes, and a VoiceOver announcement would be recorded by the
        // microphone as if it were a string.
        speech.speak(text, settings: settings, forceAppVoice: true)
    }

    /// Called when our voice finishes.
    ///
    /// The microphone stays muted for a further moment so the audio already in
    /// the capture buffer, which still holds the end of the sentence, is
    /// discarded rather than analysed as a note.
    private func finishSpeaking(settings: SpeechSettings) {
        isSpeaking = false
        speechCooldownUntil = Date().addingTimeInterval(Self.speechCooldown)
        guard isListening else { return }
        let current = spokenVerdict()
        guard current != lastSpokenVerdict else { return }
        guard case .waiting = verdict else {
            lastSpokenVerdict = current
            speak(current, settings: settings)
            return
        }
    }

    private func flatnessCents(from verdict: Verdict) -> Double {
        if case .tooFlat(let cents) = verdict { return cents }
        return 0
    }
}
