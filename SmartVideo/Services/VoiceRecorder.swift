import Foundation
import AVFoundation

@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published var errorText: String?
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.errorText = "Vui lòng cho phép sử dụng micro trong Cài đặt iOS."
                    return
                }
                self.begin()
            }
        }
    }

    private func begin() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
            let url = MediaStorage.mediaDirectory.appendingPathComponent("ThuyetMinh-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record() else {
                throw SmartVideoError.invalidMedia("Micro không thể bắt đầu ghi.")
            }
            recordingURL = url
            self.recorder = recorder
            isRecording = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    func stop() -> URL? {
        guard isRecording else { return nil }
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return recordingURL
    }
}
