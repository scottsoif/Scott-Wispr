<!-- Use this file to provide workspace-specific custom instructions to Copilot. For more details, visit https://code.visualstudio.com/docs/copilot/copilot-customization#_use-a-githubcopilotinstructionsmd-file -->

# JustWhisper - Native macOS Swift Menu Bar App

This is a native macOS application built with Swift 5.10+ targeting macOS 13+. The app provides global hotkey recording with audio transcription and text processing.

## Architecture Guidelines

- Use SwiftUI for settings/preferences UI
- Use AppKit (NSWindow) for overlay transparency effects
- Implement global hotkey capture with CGEventTap
- Use AVAudioEngine for audio recording
- Follow @MainActor pattern for UI updates
- Use async/await for background tasks
- Store preferences in ~/Library/Preferences/com.mycompany.justWhisper.plist

## Key Components

- AppDelegate: Main app coordinator
- HotkeyController: Global Fn key capture
- OverlayWindow: Transparent recording UI
- WaveView: Real-time audio visualization
- WhisperClient: Audio transcription service
- TranscriptCleaner: Text post-processing
- SettingsView: User preferences

## UX Guidelines

- Overlay: 240×120px, cornerRadius=20, glass opacity=0.85
- Animations: 150ms easeOut for scale+fade
- Use NSVisualEffectView with .hudWindow material
- Implement ignoresMouseEvents=true for overlay
