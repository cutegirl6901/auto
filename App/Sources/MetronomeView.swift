import SwiftUI
import TuneCore
import UIKit

struct MetronomeView: View {
    @EnvironmentObject private var metronome: MetronomeViewModel
    @State private var bpmInput = ""
    @State private var isShowingBPMInput = false
    @State private var bpmInputError: String?
    @FocusState private var isBPMInputFocused: Bool
    @State private var isShowingFavorites = false
    @State private var isShowingTimer = false

    private var timeSignatureBinding: Binding<TimeSignature> {
        Binding(
            get: { metronome.configuration.timeSignature },
            set: { metronome.configuration.timeSignature = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    speedReadout
                    // The two settings used while playing, side by side.
                    HStack(spacing: 12) {
                        TimeSignatureSwipeSelector(selection: timeSignatureBinding)
                        FavoriteTempoSwipeRow { isShowingFavorites = true }
                    }
                    // Everything else, in one compact row.
                    secondaryActions
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)

            transportControls
                // AirPlay-style bars sit ~30pt above the home indicator so a
                // thumb resting naturally does not hit the system gesture area.
                .padding(.bottom, 32)
        }
        .navigationTitle("节拍器")
        // A right-aligned confirm bar sits directly above the number pad,
        // matching how the system keyboard places "完成".
        // Message-composer style: the text field and its confirm button share
        // one row pinned directly above the keyboard, so "确定" sits where the
        // send button is in a chat app.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Show on isShowingBPMInput alone. Requiring focus too was a
            // deadlock: the field only appeared once focus was set, but focus
            // could only be set on a field that already existed, so the bar
            // never appeared and no keyboard came up.
            if isShowingBPMInput {
                VStack(spacing: 6) {
                    if let bpmInputError {
                        Text(verbatim: bpmInputError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(verbatim: "输入错误"))
                            .accessibilityValue(Text(verbatim: bpmInputError))
                    }
                    HStack(spacing: 10) {
                    TextField("输入 20 到 300", text: $bpmInput)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($isBPMInputFocused)
                        .submitLabel(.done)
                        .onAppear { isBPMInputFocused = true }
                        .onSubmit { applyManualBPMInput() }
                        .accessibilityLabel(Text(verbatim: "手动输入速度"))
                        .accessibilityHint(Text(verbatim: "请输入 20 到 300 的整数 BPM，然后点确定"))
                        .onChange(of: bpmInput) { _, _ in
                            bpmInputError = nil
                        }

                    Button {
                        cancelManualBPMInput()
                    } label: {
                        Text(verbatim: "取消")
                            .frame(minWidth: 48, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityLabel(Text(verbatim: "取消输入"))
                    .accessibilityHint(Text(verbatim: "放弃这次输入并关闭输入框"))

                    Button {
                        applyManualBPMInput()
                    } label: {
                        Text(verbatim: "确定")
                            .fontWeight(.semibold)
                            .frame(minWidth: 56, minHeight: 36)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityLabel(Text(verbatim: "确定并应用速度"))
                }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(.bar)
            }
        }
        // Dismissing the keyboard must also dismiss the input bar. Otherwise
        // the field stays pinned at the bottom with no way to close it except
        // leaving the screen.
        .onChange(of: isBPMInputFocused) { _, focused in
            guard !focused, isShowingBPMInput else { return }
            withAnimation { isShowingBPMInput = false }
        }
        .sheet(isPresented: $isShowingFavorites) {
            FavoriteTempoListView()
        }
        .sheet(isPresented: $isShowingTimer) {
            MetronomeTimerView()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    BeatSettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(Text(verbatim: "节拍器设置"))
                .accessibilityHint(Text(verbatim: "包含拍号、重音、细分拍、音色、触觉、测速提示和帮助"))
            }

        }
    }

    private var speedReadout: some View {
        VStack(spacing: 6) {
            Text(verbatim: "\(Int(metronome.configuration.bpm))")
                .font(.system(size: 112, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(verbatim: "BPM")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(.secondary)

            HStack(spacing: 7) {
                Circle()
                    .fill(metronome.isPlaying ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(verbatim: metronome.statusText)
                    .font(.subheadline)
            }
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "速度"))
        .accessibilityValue(Text(verbatim: "\(Int(metronome.configuration.bpm)) BPM，\(metronome.statusText)"))
    }

    /// The less-used controls, in one row of three so they take a single line
    /// instead of three.
    private var secondaryActions: some View {
        HStack(spacing: 10) {
            toolButton("定时", systemImage: "timer", value: timerButtonValue) {
                isShowingTimer = true
            }

            NavigationLink {
                TapTempoView()
            } label: {
                toolLabel("测速", systemImage: "metronome")
            }
            .buttonStyle(.bordered)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "测速"))
            .accessibilityHint(Text(verbatim: "打开测速页面，按拍子算出速度"))

            Button {
                openManualInput()
            } label: {
                toolLabel("输入速度", systemImage: "keyboard")
            }
            .buttonStyle(.bordered)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "输入速度"))
            .accessibilityHint(Text(verbatim: "手动输入 20 到 300 之间的速度"))
        }
    }

    private func toolButton(
        _ title: String,
        systemImage: String,
        value: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            toolLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: value))
        .accessibilityHint(Text(verbatim: "打开定时设置，可以让节拍器播放指定时长后自动停止"))
    }

    private func toolLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
            Text(verbatim: title)
                .font(.caption2)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
    }

    /// Opens the manual tempo bar with an empty field.
    private func openManualInput() {
        bpmInput = ""
        bpmInputError = nil
        if !isShowingBPMInput {
            withAnimation { isShowingBPMInput = true }
        }
        Task { @MainActor in
            await Task.yield()
            isBPMInputFocused = true
        }
    }
    /// What the timer button says. While a countdown runs it shows the time
    /// left, so a sighted user can glance at it.
    private var timerButtonTitle: String {
        if let remaining = metronome.remainingSeconds {
            return Self.formatRemaining(remaining)
        }
        // Stopped with time still owed: show that, not the original length, so
        // the user can see a paused countdown has kept their place.
        if let timer = metronome.runTimer, timer.duration > 0 {
            let pending = timer.remainingOrPending()
            if pending < timer.duration {
                return "还剩 " + Self.formatShort(pending)
            }
            return Self.formatDuration(timer.duration)
        }
        return "定时"
    }

    /// Spoken value for the timer button.
    private var timerButtonValue: String {
        if metronome.remainingSeconds != nil {
            return metronome.spokenRemainingTime()
        }
        if let timer = metronome.runTimer, timer.duration > 0 {
            let pending = timer.remainingOrPending()
            guard pending < timer.duration else {
                return "已设为 " + Self.formatDuration(timer.duration)
            }
            // The metronome has no pause, only stop, so say what is really
            // happening: the countdown is frozen or still running.
            let running = metronome.timerPauseBehaviour == .wallClock
            return running
                ? "计时中，还剩 " + Self.formatDuration(pending)
                : "已停止，还剩 " + Self.formatDuration(pending)
        }
        return "未设置"
    }

    /// "10 分钟" style text for a configured length.
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        if minutes >= 60, minutes % 60 == 0 { return "\(minutes / 60) 小时" }
        if minutes > 0, total % 60 == 0 { return "\(minutes) 分钟" }
        return "\(minutes) 分 \(total % 60) 秒"
    }

    /// "还剩 3 分 20 秒" style text for a running countdown.
    static func formatRemaining(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total >= 60 { return "还剩 \(total / 60) 分 \(total % 60) 秒" }
        return "还剩 \(total) 秒"
    }

    /// "3 分 20 秒" without a prefix.
    static func formatShort(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total >= 60 { return "\(total / 60) 分 \(total % 60) 秒" }
        return "\(total) 秒"
    }


    private var transportControls: some View {
        // Wider spacing than before reduces accidental taps next to the
        // play/stop button, which matters most for blind users.
        HStack(spacing: 22) {
            transportButton(systemName: "minus", label: "减小速度", enabled: metronome.configuration.bpm > MetronomeTempo.validBPMRange.lowerBound) {
                metronome.stepBPM(by: -1)
            }

            Button {
                metronome.toggle()
            } label: {
                Text(verbatim: metronome.isPlaying ? "停止" : "开始")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: metronome.isPlaying ? "停止" : "开始"))

            transportButton(systemName: "plus", label: "增大速度", enabled: metronome.configuration.bpm < MetronomeTempo.validBPMRange.upperBound) {
                metronome.stepBPM(by: 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private func transportButton(
        systemName: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2.weight(.bold))
                .frame(width: 64, height: 64)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!enabled)
        .accessibilityLabel(Text(verbatim: label))
        // No accessibilityValue here. Naming the current tempo alongside
        // "increase speed" made it read as "increase speed 100", which is
        // ambiguous: 100 could be where it is or where it is going. The new
        // tempo is announced after the change instead.
    }

    /// Abandons the current input without changing the tempo.
    private func cancelManualBPMInput() {
        bpmInputError = nil
        bpmInput = ""
        metronome.announce("已取消输入")
        isBPMInputFocused = false
    }

    private func applyManualBPMInput() {
        switch BPMInput.parse(bpmInput) {
        case .success(let bpm):
            bpmInputError = nil
            bpmInput = "\(bpm)"
            // Apply the tempo first, so the change takes effect immediately.
            metronome.applyManualBPM(Double(bpm))
            // Dropping focus closes the keyboard, and the focus observer above
            // removes the input bar once that has happened.
            isBPMInputFocused = false
        case .failure(let error):
            let message: String
            switch error {
            case .empty:
                message = "请输入速度，范围是 20 到 300 BPM。"
            case .notAnInteger:
                message = "速度必须是整数，范围是 20 到 300 BPM。"
            case .outOfRange:
                message = "速度超出范围，请输入 20 到 300 BPM。"
            }
            bpmInputError = message
            isBPMInputFocused = true
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
    }
}

/// The saved tempo row: tap to open the list, or swipe up and down to step
/// through the saved tempos directly. Mirrors how the time signature is
/// chosen, so both controls behave the same way under VoiceOver.
/// A saved-tempo card: the label on top, the value underneath, and the whole
/// thing adjustable. Laid out like the time signature beside it so the two
/// read as a pair.
private struct FavoriteTempoSwipeRow: View {
    @EnvironmentObject private var metronome: MetronomeViewModel
    let onOpenList: () -> Void

    private var tempos: [FavoriteTempo] { metronome.favorites.sortedTempos }

    private var currentIndex: Int? {
        tempos.firstIndex { $0.bpm == Int(metronome.configuration.bpm) }
    }

    private var valueText: String {
        guard !tempos.isEmpty else { return "无常用速度" }
        if let index = currentIndex {
            return "\(tempos[index].bpm) BPM，第 \(index + 1) 个，共 \(tempos.count) 个"
        }
        return "未选中，共 \(tempos.count) 个"
    }

    /// What the card shows: the position when it is a saved tempo, otherwise
    /// how many are saved.
    private var displayValue: String {
        guard !tempos.isEmpty else { return "—" }
        guard let index = currentIndex else { return "\(tempos.count) 个" }
        return "\(index + 1)/\(tempos.count)"
    }

    var body: some View {
        Button {
            onOpenList()
        } label: {
            card
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "常用速度"))
        .accessibilityValue(Text(verbatim: valueText))
        .accessibilityHint(Text(verbatim: "双击打开列表，或上下清扫直接切换"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
    }

    private var card: some View {
        VStack(spacing: 2) {
            Text(verbatim: "常用速度")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(verbatim: displayValue)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .contentShape(Rectangle())
    }

    /// Steps to the next or previous saved tempo.
    ///
    /// Wrapping rather than clamping: with only a few saved tempos, hitting the
    /// end and being unable to continue is more confusing than looping round.
    private func step(_ delta: Int) {
        guard !tempos.isEmpty else { return }
        let count = tempos.count
        let next: Int
        if let index = currentIndex {
            next = (index + delta + count) % count
        } else {
            next = delta > 0 ? 0 : count - 1
        }
        let bpm = tempos[next].bpm
        guard bpm != Int(metronome.configuration.bpm) else { return }

        metronome.applyFavoriteTempo(bpm)
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
private struct TimeSignatureSwipeSelector: View {
    @Binding var selection: TimeSignature
    @State private var isShowingPicker = false

    private var presets: [TimeSignature] { TimeSignature.presets }

    var body: some View {
        Button {
            isShowingPicker = true
        } label: {
            // A stacked card matching the saved-tempo card beside it: label on
            // top, value underneath, one chevron to show it opens something.
            VStack(spacing: 2) {
                Text(verbatim: "拍号")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(verbatim: selection.id)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isShowingPicker) {
            TimeSignaturePicker(selection: $selection)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: selection.accessibilityTitle))
        .accessibilityHint(Text(verbatim: "双击选择，或上下清扫直接调整"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
    }

    private func step(_ delta: Int) {
        guard let index = presets.firstIndex(of: selection) else { return }
        let nextIndex = (index + delta + presets.count) % presets.count
        let next = presets[nextIndex]
        guard next != selection else { return }

        selection = next
        UISelectionFeedbackGenerator().selectionChanged()

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: next.accessibilityTitle)
        }
    }
}

private struct TimeSignaturePicker: View {
    @Binding var selection: TimeSignature
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(TimeSignature.presets) { signature in
                Button {
                    selection = signature
                    dismiss()
                } label: {
                    HStack {
                        Text(verbatim: signature.id)
                            .font(.title3)
                            .monospacedDigit()
                        Spacer()
                        if signature == selection {
                            Image(systemName: "checkmark")
                                .font(.headline)
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: signature.accessibilityTitle))
                .accessibilityAddTraits(signature == selection ? [.isSelected] : [])
            }
            .navigationTitle("选择拍号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: "取消")
                    }
                }
            }
        }
        // Full height, matching the saved tempo list, so both pickers open the
        // same way instead of one appearing as a half sheet.
        .presentationDetents([.large])
    }
}
