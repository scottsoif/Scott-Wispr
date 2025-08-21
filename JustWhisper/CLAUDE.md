# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

JustWhisper is a macOS menu bar application that provides voice-to-text transcription using Azure Whisper API. Users press the Fn key to start/stop recording, and the transcribed text is automatically pasted into the currently focused application.

## Build and Development Commands

### Building the Application
```bash
# Build from Xcode (preferred)
# Open JustWhisper.xcodeproj in Xcode and use Cmd+B

# Or build from command line
xcodebuild -project JustWhisper.xcodeproj -scheme JustWhisper -configuration Debug build
```

### Running Tests
```bash
# Run unit tests
xcodebuild test -project JustWhisper.xcodeproj -scheme JustWhisper -destination 'platform=macOS'

# Run UI tests
xcodebuild test -project JustWhisper.xcodeproj -scheme JustWhisper -destination 'platform=macOS' -only-testing:JustWhisperUITests
```

### Clean Build
```bash
xcodebuild clean -project JustWhisper.xcodeproj -scheme JustWhisper
```

## Architecture Overview

### Core Components

- **AppDelegate**: Main application coordinator that manages menu bar status item, hotkey controller, overlay window, and permissions
- **HotkeyController**: Captures global Fn key events using CGEventTap and accessibility permissions for toggle recording behavior
- **OverlayWindow**: Transparent floating window that shows recording UI, waveform visualization, thinking animation, and error messages
- **RecorderController**: Audio recording using AVAudioEngine with real-time level monitoring and CAF file output
- **WhisperClient**: Azure Whisper API integration with comprehensive logging, audio format conversion (32-bit float PCM to 16-bit WAV), and error handling
- **TranscriptCleaner**: Post-processing of transcripts with configurable options (filler word removal, punctuation commands, formatting) and optional Azure OpenAI enhancement

### Key Design Patterns

- **Protocol-based testing**: AudioRecorderProtocol enables DummyRecorder for testing without actual audio hardware
- **ObservableObject**: SwiftUI reactive patterns for real-time UI updates during recording and transcription
- **Task-based async/await**: Modern Swift concurrency for API calls and background processing with proper cancellation support
- **UserDefaults configuration**: All user settings stored in UserDefaults with real-time updates

### Audio Processing Flow

1. User presses Fn key → HotkeyController detects global key event
2. AppDelegate triggers OverlayWindow.showRecording()
3. RecorderController starts AVAudioEngine recording to CAF file
4. Real-time audio level monitoring drives WaveView animation
5. User presses Fn key again → Recording stops, overlay switches to "thinking" mode
6. Audio data read from file → WhisperClient converts to WAV and sends to Azure API
7. Transcript returned → TranscriptCleaner processes text → Result pasted via CGEvent simulation

### Permission Requirements

- **Microphone Access**: Required for audio recording (handled via entitlements)
- **Accessibility Permissions**: Required for global hotkey capture and text pasting
- **Network Access**: Required for Azure Whisper API calls

### Configuration

All settings stored in UserDefaults:
- `AzureWhisperAPIKey`, `AzureWhisperEndpoint`, `AzureWhisperDeployment`: API configuration
- `JustWhisperEnabled`: Global enable/disable toggle
- `UseAzureOpenAI`: Enable enhanced transcript processing
- Transcript cleaning options: `RemoveFillerWords`, `ProcessLineBreakCommands`, etc.
- Overlay appearance: `OverlayColorRed/Green/Blue/Alpha`

### Error Handling

- Comprehensive error logging in WhisperClient with LogEntry system for debugging
- User-friendly error messages in overlay (network errors, permission issues, etc.)
- Graceful fallbacks (Azure OpenAI → local processing, empty transcripts → error display)
- Task cancellation support for escape key interruption

## Development Notes

- Target: macOS 14.2+, Swift 5.0
- No external dependencies (uses system frameworks only)
- Menu bar app architecture (LSUIElement = true, no dock icon)
- Sandboxed with required entitlements for microphone, network, and AppleEvents
- Uses modern SwiftUI for settings UI, AppKit for system integration