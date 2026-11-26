import SwiftUI
import TuneCore

/// The occasional piano jobs: measuring the instrument, looking at the curve,
/// and picking a piano type. Kept off the main screen so it stays focused on
/// starting a tuning.
struct PianoSetupView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var curveModel: PianoCurveViewModel
    @StateObject private var speech = SpeechFeedback()

    var body: some View {
        List {
            measureSection
            curveSection
            modelSection
        }
        .navigationTitle("设置")
    }

    // MARK: - Sections

    private var measureSection: some View {
        Section {
            NavigationLink {
                PianoMeasureView()
                    .environmentObject(curveModel)
            } label: {
                Text(verbatim: "测量这架琴")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "测量这架琴"))
            .accessibilityHint(Text(verbatim: "逐根弹奏琴弦，测出这架琴的非谐性"))
        } footer: {
            Text(verbatim: "测过之后，曲线会按这架琴的实测数据生成，比通用模板更准。")
        }
    }

    private var curveSection: some View {
        Section {
            NavigationLink {
                PianoCurveView()
                    .environmentObject(curveModel)
            } label: {
                Text(verbatim: "查看调律曲线")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "查看调律曲线"))
            .accessibilityHint(Text(verbatim: "分区和逐音听曲线偏差"))
        }
    }

    private var modelSection: some View {
        Section("琴型") {
            ForEach(PianoModelTemplate.all) { template in
                templateRow(template)
            }
        }
    }

    private func templateRow(_ template: PianoModelTemplate) -> some View {
        let isSelected = curveModel.selectedTemplateID == template.id
        return Button {
            curveModel.selectTemplate(template)
            speech.speak(StretchCurveNarration.summary(for: curveModel.curve), settings: appModel.speechSettings)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: template.displayName)
                    Text(verbatim: template.spokenDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: template.displayName))
        .accessibilityValue(Text(verbatim: isSelected ? "已选择" : "未选择"))
        .accessibilityHint(Text(verbatim: template.spokenDescription))
    }
}
