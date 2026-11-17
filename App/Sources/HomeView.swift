import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var metronome: MetronomeViewModel

    var body: some View {
        List {
            if metronome.isPlaying {
                Section {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: "节拍器正在播放")
                                .font(.headline)
                            Text(verbatim: "\(Int(metronome.configuration.bpm)) BPM，拍号 \(metronome.configuration.timeSignature.id)")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            metronome.stop()
                        } label: {
                            Text(verbatim: "停止")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: "停止节拍器"))
                    }
                }
            }

            Section("工具") {
                NavigationLink {
                    TunerView()
                } label: {
                    Text(verbatim: "调音器")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "调音器"))

                NavigationLink {
                    PianoTuningHomeView()
                } label: {
                    Text(verbatim: "钢琴调律")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "钢琴调律"))
                .accessibilityHint(Text(verbatim: "专业钢琴调律，按拉伸曲线逐音调音"))

                NavigationLink {
                    MetronomeView()
                } label: {
                    Text(verbatim: "节拍器")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "节拍器"))

                NavigationLink {
                    HelpView()
                } label: {
                    Text(verbatim: "帮助")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "帮助"))

                NavigationLink {
                    SettingsView()
                } label: {
                    Text(verbatim: "设置")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "设置"))
            }

            // One block for the two status lines. The version keeps its
            // accessibility identifier, which the build checks for.
            Section {
                Text(verbatim: "\(appModel.selectedPreset.displayName)\(appModel.selectedTargetDisplayName.map { "，" + $0 } ?? "")")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "当前乐器"))
                    .accessibilityValue(Text(verbatim: "\(appModel.selectedPreset.displayName)\(appModel.selectedTargetDisplayName.map { "，" + $0 } ?? "")"))

                Text(verbatim: "0.10.2 节拍器布局重排 2026-11-17")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "版本 0.10.2，节拍器布局重排，构建日期 2026 年 11 月 17 日"))
                    .accessibilityIdentifier("NOTE_BOUNDARY_2026_11_17_B")
            }
        }
        .navigationTitle("调音节拍器")
    }
}

