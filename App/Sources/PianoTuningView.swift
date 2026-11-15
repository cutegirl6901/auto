import SwiftUI
import TuneCore

/// Curve-based piano tuning. Shows one key at a time and reports the deviation
/// in words, because the user cannot see a needle.
struct PianoTuningView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var curveModel: PianoCurveViewModel
    @StateObject private var model = PianoTuningViewModel()
    @StateObject private var speech = SpeechFeedback()
    @Environment(\.scenePhase) private var scenePhase

    private var curve: StretchCurve { curveModel.curve }

    var body: some View {
        List {
            keySection
            controlSection
            readingSection
            overpullSection
            speechSection
        }
        .navigationTitle("钢琴调律")
        .onChange(of: model.verdict) { _, _ in
            model.announceIfChanged(settings: appModel.speechSettings)
        }
        // Automatic detection can change the key without changing the shape of
        // the reading (still flat, still sharp), so the verdict alone would
        // miss it and the user would not hear which note was picked up.
        .onChange(of: model.selectedMIDI) { _, _ in
            guard model.isAutoDetecting, model.isListening else { return }
            model.announceDetectedNote(settings: appModel.speechSettings)
        }
        .onDisappear {
            model.stop(settings: appModel.speechSettings)
        }
    }

    // MARK: - Sections

    private var keySection: some View {
        Section("当前音") {
            Toggle(isOn: $model.isAutoDetecting) {
                Text(verbatim: "自动识别音")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "自动识别音"))
            .accessibilityValue(Text(verbatim: model.isAutoDetecting ? "已开启" : "已关闭"))
            .accessibilityHint(Text(verbatim: "开启后弹哪个音就自动切到那个音，不用先手动选"))

            if !model.isAutoDetecting {
                Stepper(value: $model.selectedMIDI, in: 21...108) {
                    Text(verbatim: "\(model.noteName)")
                }
                .accessibilityLabel(Text(verbatim: "选择要调的音"))
                .accessibilityValue(Text(verbatim: model.noteName))
            }

            Button {
                stepOctave(by: 12)
            } label: {
                Text(verbatim: "向上一个八度")
            }
            .disabled(model.isAutoDetecting || model.selectedMIDI + 12 > 108)
            .accessibilityLabel(Text(verbatim: "向上一个八度"))

            Button {
                stepOctave(by: -12)
            } label: {
                Text(verbatim: "向下一个八度")
            }
            .disabled(model.isAutoDetecting || model.selectedMIDI - 12 < 21)
            .accessibilityLabel(Text(verbatim: "向下一个八度"))
        }
    }

    private var controlSection: some View {
        Section {
            Button {
                toggleListening()
            } label: {
                Text(verbatim: model.isListening ? "停止聆听" : "开始聆听")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: model.isListening ? "停止聆听" : "开始聆听"))

            if let error = model.errorMessage {
                Text(verbatim: error)
                    .foregroundStyle(.red)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "错误"))
                    .accessibilityValue(Text(verbatim: error))
            }
        }
    }

    private var readingSection: some View {
        Section("读数") {
            Button {
                speak(model.spokenVerdict())
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: model.spokenVerdict())
                    Text(verbatim: "目标 \(targetText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "读数"))
            .accessibilityValue(Text(verbatim: model.spokenVerdict()))
            .accessibilityHint(Text(verbatim: "轻点重新朗读"))
        }
    }

    private var overpullSection: some View {
        Section {
            Toggle(isOn: $model.useOverpull) {
                Text(verbatim: "过拉补偿")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "过拉补偿"))
            .accessibilityValue(Text(verbatim: model.useOverpull ? "已开启" : "已关闭"))
            .accessibilityHint(Text(verbatim: "开启后，音偏低时会先拉过头一点，回弹后正好准"))
        } footer: {
            Text(verbatim: "整架琴需要整体升音时开启；只微调单根弦时可以关闭")
        }
    }

    /// Explains whether this device can keep listening while it speaks.
    private var speechSection: some View {
        Section {
            Text(verbatim: speechCompatibilityText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "语音兼容"))
                .accessibilityValue(Text(verbatim: speechCompatibilityText))
        }
    }

    private var speechCompatibilityText: String {
        model.hasEchoCancellation
            ? "这台设备支持回声消除，播报时也能继续检测。"
            : "这台设备不支持回声消除。播报期间会暂停检测，播完自动恢复。"
    }

    // MARK: - Helpers

    private var targetText: String {
        let frequency = model.targetFrequency(curve: curve, concertA: appModel.concertA)
        return String(format: "%.1f 赫兹", frequency)
    }

    private func stepOctave(by semitones: Int) {
        let target = min(108, max(21, model.selectedMIDI + semitones))
        guard target != model.selectedMIDI else { return }
        model.selectedMIDI = target
        speak(model.noteName)
    }

    private func toggleListening() {
        if model.isListening {
            model.stop(settings: appModel.speechSettings)
        } else {
            model.start(curve: curve, settings: appModel.speechSettings)
        }
    }

    private func speak(_ text: String) {
        speech.speak(text, settings: appModel.speechSettings)
    }
}
