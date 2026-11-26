import SwiftUI
import TuneCore

/// The piano tuning module: a self-contained area for professional piano
/// tuning, kept separate from the general tuner used for other instruments.
///
/// Everything here works on a stretch curve rather than plain equal
/// temperament, because that is what a piano needs. Grouping it in one place
/// keeps the general tuner simple for guitars, strings and the like.
struct PianoTuningHomeView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var curveModel = PianoCurveViewModel()
    @StateObject private var speech = SpeechFeedback()

    var body: some View {
        List {
            startSection
            curveSummarySection
            settingsSection
        }
        .navigationTitle("钢琴调律")
        .onAppear {
            speak(curveModel.spokenSummary)
        }
    }

    // MARK: - Sections

    private var curveSummarySection: some View {
        Section("当前曲线") {
            Button {
                speak(curveModel.spokenSummary)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: curveModel.spokenSummary)
                    Text(verbatim: "轻点重听")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "当前调律曲线"))
            .accessibilityValue(Text(verbatim: curveModel.spokenSummary))
            .accessibilityHint(Text(verbatim: "轻点重新朗读"))
        }
    }

    /// The one thing this screen is for.
    private var startSection: some View {
        Section {
            NavigationLink {
                PianoTuningView()
                    .environmentObject(curveModel)
            } label: {
                Text(verbatim: "开始调律")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "开始调律"))
            .accessibilityHint(Text(verbatim: "按当前曲线逐音调律"))
        }
    }

    /// Preparing the piano and inspecting the curve are occasional jobs, so they
    /// sit behind one entry rather than filling the first screen.
    private var settingsSection: some View {
        Section {
            NavigationLink {
                PianoSetupView()
                    .environmentObject(curveModel)
            } label: {
                Text(verbatim: "设置")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "设置"))
            .accessibilityHint(Text(verbatim: "测量这架琴、查看曲线、选择琴型"))
        }
    }

    private func speak(_ text: String) {
        speech.speak(text, settings: appModel.speechSettings)
    }
}
