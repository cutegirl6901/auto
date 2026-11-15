# 调音时排除手机自身语音干扰：方案调研

## 问题

钢琴调律界面开着麦克风时，手机播报的声音会被麦克风收回，被当成琴弦音高分析，
导致读数乱跳。用户提出一个推想：能否"知道旁白的频率，检测到该频率就忽略"。

## 结论先说

按频率避开**不可行**。系统层面有更合适的方案，但受 iOS 版本和机型限制。

## 一、为什么"按频率避开"行不通

### 语音与钢琴的频率区间完全重叠

| 声源 | 基频范围 |
|---|---|
| 中文语音（成年男） | 85 – 180 Hz |
| 中文语音（成年女） | 165 – 255 Hz |
| 中文语音（儿童） | 180 – 300 Hz |
| 钢琴 A0（最低） | 27.5 Hz |
| 钢琴 C4（中央 C） | 261.6 Hz |
| 钢琴 A4 | 440 Hz |
| 钢琴 C8（最高） | 4186 Hz |

语音的 85–300 Hz 完全落在钢琴 A1–E4 区间内。**任何按频率过滤的做法都会同时删掉真实的低中音区琴音**。

更麻烦的是，语音不只在一个频率上——它有基频加一串整数倍谐波，以及 F1/F2/F3 共振峰
（约 500 / 1500 / 2500 Hz）。这些谐波会和琴音的高次泛音混在一起。

### 理论上可以靠声学特征区分，但代价大

语音和钢琴确实有可分辨的差异：

| 特征 | 语音 | 钢琴 | 可分性 |
|---|---|---|---|
| 非谐性 | 整数倍谐波 | 泛音偏高（非整数倍） | 可区分 |
| 起音 | 无打击瞬态 | 明显击弦瞬态 | **最可靠** |
| 时变性 | 音节 4–8 Hz 快速变化 | 音高稳定、缓慢衰减 | 可区分 |
| 共振峰 | 有固定 F1/F2/F3 | 无 | 可区分 |

但要实现就得跑实时音频分类器，问题有三个：

1. **复杂度高**：需要训练/调参，本仓库没有条件做真机验证。
2. **会误判**：说话时弹琴可能被整段丢掉。
3. **增加延迟**：少说也要多积累几帧才能判断，调音本来就嫌慢。

所以这条路不作为首选。

## 二、iOS 系统级方案（推荐）

### 1. 回声消除输入：AVAudioSession.setPrefersEchoCancelledInput

Apple 在 **iOS 18.2** 加入，专门解决"一边外放一边录音"的场景。

```swift
// 系统支持性查询
session.isEchoCancelledInputAvailable

// 开启
try session.setPrefersEchoCancelledInput(true)

// 激活音频会话后，确认系统是否真的启用了
session.isEchoCancelledInputEnabled
```

官方说明要点：

- 用于**内置麦克风 + 内置扬声器**同时工作的场景。
- 与"语音处理"不同：**它针对更宽频段的音频做了优化**，不只是人声，
  更适合调音这种需要准确捕捉乐器泛音的场景。
- 限制：仅在 `playAndRecord` 类别 + 特定 mode 下有效，
  且**仅部分 2024 年及以后的 iPhone 机型支持**。
- 兼容性风险：如果与正在录音的其他会话冲突，可能会中断对方。

**这正是当前问题最匹配的官方解法**，但覆盖面有限。

### 2. 语音处理（Voice Processing）

`AVAudioInputNode` 自带的语音处理单元，历史更久（iOS 13+），
系统会自动对通话类路由做回声消除。

```swift
inputNode.isVoiceProcessingInputMuted   // 静音输入
inputNode.isVoiceProcessingBypassed     // 绕过全部上行处理
inputNode.isVoiceProcessingAGCEnabled   // 自动增益
```

注意：**这套是为人声调优的**，用在调音上可能削弱乐器声音的细节
（官方文档的原话是对比两者：voice processing 面向语音，
setPrefersEchoCancelledInput 面向更宽的音频信号）。

### 3. 输入静音：isVoiceProcessingInputMuted

可以把输入直接静音。但它没有"只在播报时静音"的粒度，
且同样依赖语音处理链路。

## 三、当前实现的做法（已上线）

| 做法 | 说明 |
|---|---|
| 播报期间完全丢弃麦克风采样 | 不只是提高音量门槛 |
| 播报结束后静默 0.5 秒 | 捕获缓冲约 370 ms，里面还留着句尾 |
| 调音页强制用「应用语音」 | 旁白播报没有结束回调，无法知道何时说完 |

这是不依赖设备型号、不依赖 iOS 版本的做法，代价是播报期间不能检测。

## 四、后续可选优化

按优先级：

1. **检测 `isEchoCancelledInputAvailable`**，可用时开启回声消除。
   不可用时保持现有行为。这样可以覆盖新机型，老机型不受影响。
2. **播报结束后用 0.3–0.5 秒做"静音确认"**，已有。
3. 若将来仍不够：考虑用起音检测（attack transient）作为额外门槛。
   钢琴有击弦瞬态，语音没有。这是最可靠的声学区分特征。
4. **不建议**做频率过滤：会误删真实琴音。

## 五、参考

- `AVAudioSession.isEchoCancelledInputAvailable`（iOS 18.2+）
- `AVAudioSession.setPrefersEchoCancelledInput(_:)`（iOS 18.2+）
- `AVAudioSession.isEchoCancelledInputEnabled`（iOS 18.2+）
- `AVAudioInputNode.isVoiceProcessingInputMuted` / `isVoiceProcessingBypassed`
- Apple Developer Documentation: AVAudioSession → Configuring echo cancellation
