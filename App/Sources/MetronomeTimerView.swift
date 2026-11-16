import SwiftUI
import TuneCore
import UIKit

/// Picks how long the metronome should play.
///
/// Deliberately flat: turn-off first, then the preset lengths, then a custom
/// entry. Section headings were removed because a screen-reader user hears
/// every one of them while swiping, and they add nothing over the row labels.
struct MetronomeTimerView: View {
    @EnvironmentObject private var metronome: MetronomeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingCustomInput = false
    @State private var customMinutes = ""
    @State private var customError: String?
    @FocusState private var isCustomFieldFocused: Bool

    private var currentDuration: TimeInterval? { metronome.runTimer?.duration }

    var body: some View {
        NavigationStack {
            List {
                offRow
                presetRows
                customRow
            }
            .navigationTitle("定时")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: "取消")
                    }
                    .accessibilityLabel(Text(verbatim: "关闭定时设置"))
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isShowingCustomInput {
                customInputBar
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Rows

    /// First row, so turning the timer off is the quickest thing to reach.
    private var offRow: some View {
        let isOff = metronome.runTimer == nil
        return Button {
            metronome.clearRunTimer()
            announceAndClose("定时已关闭")
        } label: {
            checkRow(title: "不设定时", isSelected: isOff)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "不设定时"))
        .accessibilityValue(Text(verbatim: isOff ? "已选中" : ""))
        .accessibilityHint(Text(verbatim: "双击关闭定时，节拍器会一直播放"))
        .accessibilityAddTraits(isOff ? [.isSelected] : [])
    }

    private var presetRows: some View {
        ForEach(TimerDurations.presets) { option in
            presetRow(option)
        }
    }

    private func presetRow(_ option: TimerDurationOption) -> some View {
        let isSelected = currentDuration == option.seconds
        return Button {
            choose(seconds: option.seconds, spoken: option.spokenTitle)
        } label: {
            checkRow(title: option.spokenTitle, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: option.spokenTitle))
        .accessibilityValue(Text(verbatim: isSelected ? "已选中" : ""))
        .accessibilityHint(Text(verbatim: "双击选择 " + option.spokenTitle))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func checkRow(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(verbatim: title)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }

    private var customRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                customMinutes = ""
                customError = nil
                isShowingCustomInput = true
            } label: {
                Text(verbatim: "自定义时长")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "自定义时长"))
            .accessibilityHint(Text(verbatim: "输入 1 到 999 之间的整数分钟"))

            if let customError {
                Text(verbatim: customError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var customInputBar: some View {
        HStack(spacing: 10) {
            TextField("输入 1 到 999", text: $customMinutes)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .focused($isCustomFieldFocused)
                .submitLabel(.done)
                .onAppear { isCustomFieldFocused = true }
                .onSubmit { applyCustomInput() }
                .accessibilityLabel(Text(verbatim: "输入分钟数"))

            Button {
                applyCustomInput()
            } label: {
                Text(verbatim: "确定")
                    .fontWeight(.semibold)
                    .frame(minWidth: 56, minHeight: 36)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel(Text(verbatim: "确定并设置定时"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Actions

    private func choose(seconds: TimeInterval, spoken: String) {
        metronome.setRunDuration(seconds)
        announceAndClose("定时设为 " + spoken)
    }

    private func applyCustomInput() {
        switch TimerDurations.parse(minutes: customMinutes) {
        case .success(let minutes):
            isCustomFieldFocused = false
            customError = nil
            metronome.setRunDuration(Double(minutes) * 60)
            announceAndClose("定时设为 " + TimerDurations.spoken(minutes: minutes))
        case .failure(let error):
            let message: String
            switch error {
            case .empty: message = "请输入分钟数。"
            case .notAnInteger: message = "请输入整数分钟。"
            case .outOfRange: message = "范围是 1 到 999 分钟。"
            }
            customError = message
            isCustomFieldFocused = true
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
    }

    /// Says what was chosen, waits long enough for it to be heard, then closes.
    private func announceAndClose(_ text: String) {
        metronome.announce(text)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            dismiss()
        }
    }
}
