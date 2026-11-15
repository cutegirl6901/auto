import AVFoundation
import UIKit

@MainActor
final class SpeechFeedback: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var voiceOverFinishTask: Task<Void, Never>?
    private var currentUtterance: AVSpeechUtterance?
    var onFinish: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks a line.
    ///
    /// `forceAppVoice` bypasses the VoiceOver announcement path. Screens that
    /// listen to the microphone need it: an announcement gives no completion
    /// callback, so there is no reliable moment at which listening may resume,
    /// and the announcement itself would be picked up as input. The app's own
    /// synthesizer reports exactly when it has finished.
    func speak(
        _ text: String,
        language: String = "zh-CN",
        settings: SpeechSettings? = nil,
        forceAppVoice: Bool = false
    ) {
        let settings = settings ?? SpeechSettings.load()
        // VoiceOver announcements never touch the synthesizer, so an active
        // announcement must also count as "speaking" or the new one is posted
        // too early and its opening words get dropped.
        let wasSpeaking = synthesizer.isSpeaking || voiceOverFinishTask != nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        voiceOverFinishTask?.cancel()
        voiceOverFinishTask = nil
        let shouldUseVoiceOver: Bool
        if forceAppVoice {
            shouldUseVoiceOver = false
        } else {
            switch settings.outputMode {
            case .appVoice:
                shouldUseVoiceOver = false
            case .automatic:
                shouldUseVoiceOver = UIAccessibility.isVoiceOverRunning
            case .voiceOver:
                shouldUseVoiceOver = UIAccessibility.isVoiceOverRunning
            }
        }
        if shouldUseVoiceOver {
            speakWithVoiceOver(text, interrupting: wasSpeaking)
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        // AVSpeechUtterance.rate is 0...1; keep the scale explicit so
        // higher user settings actually produce faster speech.
        utterance.rate = Float(min(1.0, max(0.0, settings.rate)))
        utterance.pitchMultiplier = Float(settings.pitch)
        utterance.volume = Float(settings.volume)
        // Stopping and immediately speaking can clip the first syllables.
        // Give the synthesizer one run-loop turn to finish cancelling.
        currentUtterance = utterance
        if wasSpeaking {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.synthesizer.speak(utterance)
            }
        } else {
            synthesizer.speak(utterance)
        }
    }

    func speakWithVoiceOver(_ text: String, interrupting: Bool = false) {
        voiceOverFinishTask?.cancel()
        guard !text.isEmpty else {
            onFinish?()
            return
        }
        let announcement = NSAttributedString(
            string: text,
            attributes: [
                .accessibilitySpeechQueueAnnouncement: false,
                .accessibilitySpeechLanguage: "zh-CN"
            ]
        )
        if interrupting {
            // VoiceOver needs a moment to cancel the previous announcement;
            // posting immediately can drop the new utterance's opening words.
            let voiceOverText = text
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(60))
                guard let self else { return }
                UIAccessibility.post(
                    notification: .announcement,
                    argument: NSAttributedString(
                        string: voiceOverText,
                        attributes: [
                            .accessibilitySpeechQueueAnnouncement: false,
                            .accessibilitySpeechLanguage: "zh-CN"
                        ]
                    )
                )
                self.startVoiceOverFinishTimer(for: voiceOverText)
            }
            return
        }
        UIAccessibility.post(notification: .announcement, argument: announcement)
        startVoiceOverFinishTimer(for: text)
    }

    private func startVoiceOverFinishTimer(for text: String) {
        // VoiceOver gives no completion callback, so the duration is an
        // estimate. Chinese speech runs slower than the old per-character
        // figure allowed for, and finishing early let the app treat a
        // still-speaking announcement as done and start listening again.
        // The multiplier is deliberately generous; running slightly long only
        // delays the next announcement.
        let estimatedDuration = min(12.0, 1.0 + Double(text.count) * 0.20)
        voiceOverFinishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(estimatedDuration))
            guard !Task.isCancelled, let self else { return }
            self.voiceOverFinishTask = nil
            self.onFinish?()
        }
    }

    func stop() {
        voiceOverFinishTask?.cancel()
        voiceOverFinishTask = nil
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // A superseded utterance must not clear the state of the newer one.
        guard utterance === currentUtterance else { return }
        currentUtterance = nil
        onFinish?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Cancellation is expected during interruption. Only clear the slot if
        // this was still the active utterance, and never report completion:
        // the caller already moved on to the newer result.
        if utterance === currentUtterance {
            currentUtterance = nil
        }
    }
}
