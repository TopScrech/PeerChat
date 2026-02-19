import SwiftUI
import ScrechKit
import AVFoundation

struct VoiceMessageBubble: View {
    let audioData: Data?
    let duration: TimeInterval?
    let isCurrentUser: Bool
    
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackTask: Task<Void, Never>?
    
    var body: some View {
        HStack(spacing: 8) {
            Button(isPlaying ? "Stop" : "Play", systemImage: isPlaying ? "stop.fill" : "play.fill") {
                togglePlayback()
            }
            .buttonStyle(.plain)
            .disabled(audioData == nil)
            
            Text(durationText)
                .monospacedDigit()
                .callout()
        }
        .foregroundStyle(isCurrentUser ? .white : .primary)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            isCurrentUser ? .blue : .secondary,
            in: .rect(cornerRadius: 20, style: .continuous)
        )
        .onDisappear(perform: stopPlayback)
    }
    
    private var durationText: String {
        let seconds = Int(duration ?? 0)
        let minutesPart = seconds / 60
        let secondsPart = seconds % 60
        return "\(minutesPart):\(String(format: "%02d", secondsPart))"
    }
    
    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
            return
        }
        
        guard let audioData else {
            return
        }
        
        do {
            let newPlayer = try AVAudioPlayer(data: audioData)
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            isPlaying = true
            
            let durationInNanoseconds = UInt64(max(newPlayer.duration, 0) * 1_000_000_000)
            playbackTask?.cancel()
            playbackTask = Task {
                try? await Task.sleep(nanoseconds: durationInNanoseconds)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isPlaying = false
                    player = nil
                }
            }
        } catch {
            print("Could not play audio")
            stopPlayback()
        }
    }
    
    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        player?.stop()
        player = nil
        isPlaying = false
    }
}
