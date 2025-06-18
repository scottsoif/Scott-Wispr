//
//  PlaybackController.swift
//  JustWhisper
//
//  Created by Scott Soifer on 6/17/25.
//

import AVFoundation
import Foundation

/**
 * Manages audio playback using AVAudioPlayer
 */
class PlaybackController: NSObject, ObservableObject {
    @Published var isPlaying = false
    
    private var audioPlayer: AVAudioPlayer?
    
    /**
     * Plays audio from the specified file URL
     */
    func play(from url: URL) {
        guard !isPlaying else { return }
        
        do {
            // No AVAudioSession configuration needed on macOS
            // Audio routing is handled automatically by the system
            
            // Create and configure player
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            
            // Start playback
            if audioPlayer?.play() == true {
                isPlaying = true
            }
        } catch {
            print("Failed to play audio: \(error)")
        }
    }
    
    /**
     * Stops current playback
     */
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }
}

// MARK: - AVAudioPlayerDelegate
extension PlaybackController: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.audioPlayer = nil
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.audioPlayer = nil
        }
        if let error = error {
            print("Audio player decode error: \(error)")
        }
    }
}
