import AVFoundation
import os

enum AudioSessionManager {
    /// Whether the system actually applied echo cancellation to the tuner
    /// session. Read from the audio path, which is not bound to the main actor,
    /// so the flag is guarded by a lock rather than being actor-isolated.
    private static let echoLock = NSLock()
    nonisolated(unsafe) private static var echoActive = false

    static var isEchoCancellationActive: Bool {
        echoLock.lock()
        defer { echoLock.unlock() }
        return echoActive
    }

    private static func setEchoActive(_ value: Bool) {
        echoLock.lock()
        echoActive = value
        echoLock.unlock()
    }

    private static let log = Logger(subsystem: "com.shm06.TuneMetronome", category: "audio")

    static func configureForTuner() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )

        // iOS 18.2 can subtract the speaker's output from the microphone. That
        // is exactly the problem the tuner has: its own announcements are
        // picked up and analysed as if they were strings. Unlike voice
        // processing, this is tuned for a wide range of audio rather than the
        // human voice, so it suits instruments.
        //
        // Availability is limited to certain 2024 and later iPhones, so this is
        // an enhancement rather than a requirement. Anything unsupported keeps
        // the previous behaviour of muting the microphone while speaking.
        setEchoActive(false)
        if #available(iOS 18.2, *) {
            if session.isEchoCancelledInputAvailable {
                do {
                    try session.setPrefersEchoCancelledInput(true)
                    setEchoActive(true)
                } catch {
                    // A rejection here is not fatal: tuning still works, it
                    // just has to duck the microphone while speaking.
                    log.info("Echo cancellation was refused: \(error.localizedDescription)")
                }
            }
        }

        try session.setActive(true)

        // The preference is only honoured once the session is active, so the
        // real answer has to be read afterwards.
        if #available(iOS 18.2, *) {
            setEchoActive(isEchoCancellationActive && session.isEchoCancelledInputEnabled)
        }
        log.info("Tuner echo cancellation active: \(isEchoCancellationActive)")
    }

    static func configureForMetronome() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .default,
            options: [.mixWithOthers]
        )
        try session.setActive(true)
    }

    static func configureForTapTempo() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .ambient,
            mode: .default,
            options: [.mixWithOthers]
        )
        try session.setActive(true)
    }

    static func deactivate() {
        setEchoActive(false)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
    }
}
