# JustWhisper - Voice-to-Text with Global Hotkey

A macOS menu bar app that provides instant voice-to-text transcription with a global Command key hotkey.

## Features

### Global Command Hotkey

- **Hold ⌘ (Command)** to start recording
- **Release ⌘** to stop recording and transcribe
- Debounced to avoid accidental taps (<150ms)
- Uses low-level `CGEventTap` for system-wide detection

### Screen-Center Overlay

- Semi-transparent glass-morph popup appears when recording
- Real-time waveform visualization during recording
- Thinking dots animation during transcription
- Smooth fade in/out animations

### Intelligent Text Processing

- Removes filler words (um, uh, like, etc.)
- Processes voice commands:
  - "new line" → `\n`
  - "bullet point" → `•`
  - "quote...end quote" → `"..."`
- "Actually..." self-correction (keeps last clause)
- Toggle on/off in settings

### Azure Whisper Integration

- Uses Azure OpenAI Whisper API for transcription
- Automatic text insertion at cursor position
- Error handling and retry logic

## Setup

### 1. Configure Azure Whisper API

Edit `Configuration.swift` and replace the placeholder values:

```swift
static func setupExampleConfiguration() {
    configureAzureWhisper(
        apiKey: "your-azure-api-key-here",
        deployment: "your-deployment-name-here",
        endpoint: "https://your-resource-name.openai.azure.com"
    )
}
```

### 2. Grant Permissions

The app requires two permissions:

**Microphone Access**

- Automatically requested on first launch
- Required for audio recording

**Accessibility Access**

- Required for global hotkey detection and text insertion
- App will prompt to open System Preferences
- Go to: **System Preferences > Security & Privacy > Privacy > Accessibility**
- Add and enable **JustWhisper**

### 3. Build and Run

1. Open `JustWhisper.xcodeproj` in Xcode
2. Build and run (⌘+R)
3. Look for the microphone icon in your menu bar

## Usage

### Menu Bar Interface

- Click the microphone icon to access recording controls
- Manual record/play buttons available
- Settings gear icon to toggle text cleaning

### Global Hotkey

1. **Hold ⌘** anywhere in macOS to start recording
2. Speak your text while holding the key
3. **Release ⌘** to stop and transcribe
4. Text automatically appears at your cursor position

### Voice Commands

While recording, use these commands for formatting:

- **"new line"** - Inserts a line break
- **"bullet point"** - Inserts a bullet (•)
- **"quote [text] end quote"** - Wraps text in quotes
- **"Actually, [new text]"** - Replaces everything before with new text

## Architecture

### Key Components

- **`CmdHotkeyController`** - Global Command key detection
- **`RecordingOverlay`** - Screen-center UI overlay
- **`TextProcessor`** - Transcript cleaning and formatting
- **`TranscriptionService`** - Azure Whisper API integration
- **`RecorderController`** - Audio recording management

### File Structure

```
JustWhisper/
├── CmdHotkeyController.swift    # Global hotkey detection
├── RecordingOverlay.swift       # Screen overlay UI
├── TextProcessor.swift          # Text cleaning logic
├── TranscriptionService.swift   # Azure API integration
├── Configuration.swift          # API configuration
├── RecorderController.swift     # Audio recording
├── WaveView.swift              # Waveform visualization
├── PopoverView.swift           # Menu bar interface
├── StatusBarController.swift    # Menu bar management
└── AppDelegate.swift           # App lifecycle
```

## Testing

The project includes comprehensive unit tests for text processing:

```bash
# Run tests in Xcode
⌘+U
```

Test coverage includes:

- Filler word removal
- Voice command processing
- "Actually..." correction handling
- Nested quote scenarios
- Enable/disable functionality

## Troubleshooting

### Hotkey Not Working

- Check Accessibility permissions in System Preferences
- Restart the app after granting permissions

### Transcription Fails

- Verify Azure API configuration in `Configuration.swift`
- Check network connectivity
- Ensure microphone permissions are granted

### Audio Quality Issues

- Check microphone input levels in System Preferences
- Ensure quiet environment for better recognition
- Hold Command key steady during recording

## Requirements

- macOS 12.0+
- Xcode 14.0+
- Azure OpenAI account with Whisper deployment
- Microphone access
- Accessibility permissions

## License

MIT License - see LICENSE file for details.

- **Instant Playback**: Play back your last recording immediately
- **Permission Management**: Automatic microphone permission handling with System Preferences integration
- **Persistent Storage**: Recordings saved to `~/Library/Application Support/JustWhisper/recording.caf`

## Technical Stack

- **Language**: Swift 5.10
- **Target**: macOS 13.0+
- **UI Framework**: SwiftUI with NSStatusBar integration
- **Audio**: AVAudioEngine for recording, AVAudioPlayer for playback
- **Architecture**: MVVM with protocol-based recorder for testability

## Build & Run

### Prerequisites

- Xcode 16.0+
- macOS 13.0+ development target

### Steps

1. Clone the repository:

   ```bash
   git clone <repository-url>
   cd justWhisper2
   ```

2. Open the project in Xcode:

   ```bash
   open JustWhisper.xcodeproj
   ```

3. Build and run:
   - Select your development team in the project settings
   - Choose "My Mac" as the destination
   - Press Cmd+R to build and run

### First Launch

1. The app will appear as a microphone icon in your menu bar
2. Click the icon to open the popover
3. If prompted, grant microphone permission
4. Start recording by clicking the "Record" button

## File Structure

```
JustWhisper/
├── AppDelegate.swift           # App lifecycle and StatusBarController setup
├── StatusBarController.swift   # NSStatusItem management and popover control
├── RecorderController.swift    # AVAudioEngine recording with protocol for testing
├── PlaybackController.swift    # AVAudioPlayer playback management
├── WaveView.swift             # Real-time waveform visualization
├── PermissionManager.swift     # Microphone permission handling
├── PopoverView.swift          # Main SwiftUI popover interface
└── JustWhisper.entitlements       # Sandbox permissions for microphone access
```

## UI Components

### Popover Layout

- **Waveform Display**: 12 animated bars showing real-time audio levels
- **Record Button**: Red when recording, blue when stopped
- **Play Button**: Green when enabled, gray when disabled
- **Duration Label**: Live timer showing recording length in "X.X s" format
- **Permission Button**: Orange button to enable microphone access

### Animations

- **Popover**: 0.15s fade+scale animation on open/close
- **Waveform**: Smooth Core Animation transitions for level changes
- **Buttons**: Color transitions and state changes

## Recording Details

### File Location

Recordings are saved to:

```
~/Library/Application Support/JustWhisper/recording.caf
```

### Audio Format

- **Format**: Core Audio Format (.caf)
- **Quality**: Uses input device's native format
- **Overwrite**: Each new recording overwrites the previous one

### Permissions

The app requires microphone access and will:

1. Request permission on first use
2. Show "Enable Microphone" button if denied
3. Open System Preferences → Security & Privacy → Microphone on denial

## Testing

### Unit Tests

Run tests with Cmd+U or:

```bash
xcodebuild test -scheme JustWhisperTests
```

### Test Coverage

- PermissionManager initialization and state
- DummyRecorder functionality for integration testing
- PlaybackController and RecorderController initialization
- Protocol conformance testing

### DummyRecorder

For testing and development, use `DummyRecorder` instead of `RecorderController`:

```swift
@StateObject private var recorder = DummyRecorder() // Instead of RecorderController()
```

## Architecture

### Protocol-Based Design

The `AudioRecorderProtocol` enables easy testing and mocking:

```swift
protocol AudioRecorderProtocol: ObservableObject {
    var isRecording: Bool { get }
    var duration: TimeInterval { get }
    var audioLevel: Float { get }
    var hasRecording: Bool { get }

    func startRecording() throws
    func stopRecording()
    func getRecordingURL() -> URL?
}
```

### State Management

- **ObservableObject**: All controllers conform for SwiftUI integration
- **@Published**: Properties automatically update UI
- **Combine**: Reactive programming for smooth state transitions

## Troubleshooting

### Common Issues

1. **No microphone permission**

   - Click "Enable Microphone" in the popover
   - Manual: System Preferences → Security & Privacy → Microphone

2. **No audio input detected**

   - Check system audio input device
   - Verify microphone is not muted
   - Check other apps aren't using the microphone

3. **Recording not playing back**
   - Ensure recording was completed successfully
   - Check audio output device
   - Verify file exists at recording location

### Debug Mode

For development, uncomment debug logging in:

- `RecorderController.swift` - audio engine status
- `PlaybackController.swift` - playback errors
- `PermissionManager.swift` - permission state changes

## Screenshots

![JustWhisper Popover](screenshot-popover.png)
_The popover interface showing waveform visualization and control buttons_

![Menu Bar Icon](screenshot-menubar.png)  
_The microphone icon in the macOS menu bar_

## License

[Add your license here]

## Contributing

[Add contribution guidelines here]
