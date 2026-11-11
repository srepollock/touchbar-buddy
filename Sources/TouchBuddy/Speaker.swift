import AVFoundation
import TouchBuddyCore

@MainActor
final class Speaker {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ line: String, voice: String?) {
        let text = stripEmoji(line)
        guard !text.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        if let voice, let installed = AVSpeechSynthesisVoice(identifier: voice) {
            utterance.voice = installed
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
