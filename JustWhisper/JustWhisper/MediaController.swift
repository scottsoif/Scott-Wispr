//
//  MediaController.swift
//  JustWhisper
//
//  Created by Scott Soifer on 2/7/26.
//

import Cocoa
import CoreAudio

/// Controls system audio muting during recording
class MediaController {
    static let shared = MediaController()

    /// Whether we muted audio and should unmute it later
    private var didMuteAudio = false

    private init() {}

    /// Mute system audio if the setting is enabled.
    /// Call this when recording starts.
    func pauseIfEnabled() {
        guard UserDefaults.standard.bool(forKey: "AutoPauseMusic") else { return }

        // Only mute if not already muted by us
        guard !didMuteAudio else { return }

        // Check if already muted by the user — don't touch it if so
        if isSystemMuted() {
            print("🔇 MediaController: System already muted, skipping")
            return
        }

        didMuteAudio = true
        setSystemMute(true)
        print("🔇 MediaController: Muted system audio")
    }

    /// Unmute system audio if we previously muted it.
    /// Call this when recording/processing is complete.
    func resumeIfNeeded() {
        guard didMuteAudio else { return }
        didMuteAudio = false
        setSystemMute(false)
        print("🔊 MediaController: Unmuted system audio")
    }

    /// Cancel unmute (e.g. if recording was canceled via escape)
    func cancelResume() {
        didMuteAudio = false
    }

    // MARK: - CoreAudio System Mute

    /// Gets the default output audio device ID
    private func getDefaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size, &deviceID
        )

        guard status == noErr else {
            print("❌ MediaController: Failed to get default output device: \(status)")
            return nil
        }

        return deviceID
    }

    /// Checks if system audio is currently muted
    private func isSystemMuted() -> Bool {
        guard let deviceID = getDefaultOutputDeviceID() else { return false }

        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)

        guard status == noErr else { return false }

        return muted != 0
    }

    /// Sets system audio mute state
    private func setSystemMute(_ mute: Bool) {
        guard let deviceID = getDefaultOutputDeviceID() else { return }

        var muted: UInt32 = mute ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &muted)

        if status != noErr {
            print("❌ MediaController: Failed to set mute state: \(status)")
        }
    }
}
