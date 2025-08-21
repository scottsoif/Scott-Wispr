# JustWhisper - Voice-to-Text with Global Hotkeys

A macOS menu bar application that provides voice-to-text transcription using Azure Whisper API. Record your voice, get accurate transcriptions, and automatically paste them into any application.

## Features

### Global Hotkey System

- **Fn Key**: Start/stop recording with GPT-enhanced auto-paste
- **Ctrl Key**: Stop recording and paste without GPT enhancement
- **Escape Key**: Cancel recording at any time
- Uses low-level `CGEventTap` for system-wide detection
- Requires accessibility permissions for global functionality

### Advanced Audio Management

- **Microphone Selection**: Choose from any available audio input device (Built-in, AirPods, USB mics)
- **Device Switching**: Automatically handles device changes and reconnections
- **Real-time Level Monitoring**: Live waveform visualization during recording
- **Persistent Device Memory**: Remembers your preferred microphone

### Intelligent Text Processing

- **AI Enhancement**: Optional OpenAI/Azure OpenAI integration for improved transcript quality
- **Smart Cleaning**: Removes filler words (um, uh, like, etc.)
- **Voice Commands**: Process "new line", "period", "bullet point" commands
- **Self-Correction**: Handles "Actually..." corrections automatically
- **Custom Dictionary**: Add word replacements for common transcription errors
- **Auto-Capitalization**: Proper sentence formatting

### Customizable Overlay

- **Flexible Positioning**: Top-left, top-right, bottom-left, bottom-right, or center
- **Live Color Updates**: Customize background color and opacity with instant preview
- **Real-time Waveform**: Visual feedback during recording
- **Thinking Animation**: Progress indicator during transcription
- **Error Messages**: Clear feedback for issues

### Dual API Support

- **Azure OpenAI**: Full Azure Whisper integration with deployment configuration
- **Standard OpenAI**: Direct OpenAI API support with custom models
- **Fallback Processing**: Local text cleaning when APIs unavailable
- **Smart Provider Switching**: Choose your preferred AI service

## Quick Start

### Prerequisites

1. **Azure Whisper API**: Azure OpenAI resource with Whisper deployment
2. **macOS Permissions**: Microphone and accessibility permissions required

### Setup

1. **Install**: Place JustWhisper.app in Applications folder
2. **Launch**: App appears in menu bar with microphone icon
3. **Configure API**: Open Settings → Azure Whisper API:

   - API Key
   - Endpoint URL (e.g., `https://your-resource.openai.azure.com/`)
   - Deployment name (usually `whisper`)
   - API Version (e.g., `2024-08-01-preview`)

4. **Grant Permissions**:

   - **Microphone**: Required for audio recording
   - **Accessibility**: Required for global hotkeys and text pasting

5. **Select Microphone**: Choose your preferred audio input device in settings

## Usage

### Keyboard Shortcuts

| Key                           | Action                                    |
| ----------------------------- | ----------------------------------------- |
| **Fn**                        | Start/Stop recording with auto-paste      |
| **Ctrl** (during recording)   | Stop recording and copy to clipboard only |
| **Escape** (during recording) | Cancel recording                          |

### Recording Modes

**Standard Mode (Auto-Paste)**

1. Press **Fn key** to start recording
2. Speak your text
3. Press **Fn key** again to stop
4. Text automatically pastes into focused application

**Copy-Only Mode**

1. Press **Fn key** to start recording
2. Speak your text
3. Press **Ctrl key** to stop and copy to clipboard
4. Green "Copied to clipboard" confirmation appears

**Cancel Recording**

- Press **Escape** anytime during recording to cancel

### Menu Bar Interface

- Click microphone icon for manual controls
- Access settings and preferences
- Check permission status
- Test recording functionality

## Settings & Configuration

### Audio Settings

- **Microphone Device**: Dropdown to select input device
- **Device Refresh**: Update available devices list
- **Permission Management**: Check and request microphone access
- **Audio Test**: Record and playback test functionality

### API Configuration

**Azure Whisper (Required)**

- API Key, Endpoint, Deployment name, API Version
- Connection testing available

**OpenAI Enhancement (Optional)**
Choose between:

- **Azure OpenAI**: API Key, Endpoint, Deployment, API Version
- **Standard OpenAI**: API Key, Model (gpt-4o-mini), Base URL

### Overlay Appearance

- **Position**: 5 positioning options with live preview
- **Background Color**: Full color picker with opacity control
- **Real-time Updates**: All changes apply immediately

### Transcript Processing

- **Filler Word Removal**: Toggle um, uh, like removal
- **Voice Commands**: Process formatting commands
- **Auto-Capitalization**: Sentence case formatting
- **Custom Word Replacements**: Personal transcription dictionary
- **Self-Correction**: Handle speaker corrections

## Troubleshooting

### Recording Issues

1. **No Audio Input**

   - Check microphone selection in settings
   - Try different input device (Built-in vs AirPods)
   - Verify microphone permissions

2. **Device Switching Problems**
   - Use refresh button in microphone settings
   - Switch to different device and back
   - Restart app if device not recognized

### Hotkey Issues

1. **Global Keys Not Working**

   - Verify accessibility permissions in System Preferences
   - Toggle JustWhisper enabled/disabled in settings
   - Check conflicting apps using same keys

2. **Function Key Conflicts**
   - Some apps intercept Fn key
   - Check System Preferences → Keyboard → Function Keys
   - Try in different applications

### Overlay Issues

1. **Position Not Updating**

   - Settings now update immediately
   - Try different position options
   - Check for multiple displays

2. **Color Not Changing**
   - Use color picker in settings
   - Opacity slider affects visibility
   - Changes apply without restart

### API & Transcription

1. **Poor Quality**

   - Check microphone quality and positioning
   - Enable AI enhancement in settings
   - Record in quiet environment
   - Add common errors to word replacements

2. **API Errors**
   - Verify API credentials in settings
   - Test connection using built-in test
   - Check network connectivity
   - Try switching between Azure/OpenAI providers

## System Requirements

- **macOS**: 14.2 or later
- **Architecture**: Apple Silicon (ARM64) or Intel x64
- **Internet**: Required for API calls
- **Permissions**: Microphone access, Accessibility permissions
- **Hardware**: Any microphone (built-in, USB, Bluetooth)

## Privacy & Security

- **Local Processing**: Audio processing when possible
- **Temporary Storage**: Recordings deleted after processing
- **API Security**: Secure HTTPS connections only
- **Sandboxed**: App runs in macOS security sandbox
- **No Persistent Storage**: Audio not saved permanently

## Technical Architecture

### Core Components

- **HotkeyController**: Global Fn/Ctrl/Escape key detection
- **RecorderController**: Audio recording with device management
- **OverlayWindow**: Transparent UI with positioning system
- **WhisperClient**: Azure Whisper API integration
- **TranscriptCleaner**: Text processing with AI enhancement
- **SettingsView**: Comprehensive configuration interface

### Audio Pipeline

1. **Device Selection**: Core Audio device enumeration
2. **Recording**: AVAudioEngine with tap monitoring
3. **Processing**: CAF to WAV conversion for API
4. **Transcription**: Azure Whisper or local fallback
5. **Enhancement**: Optional OpenAI processing
6. **Output**: Paste via CGEvent or clipboard

### Development Stack

- **Swift 5.0** with **SwiftUI**
- **AVAudioEngine** for recording
- **Core Audio** for device management
- **CGEvent** for global hotkeys and text insertion
- **UserDefaults** for persistent configuration

## File Structure

```
JustWhisper/
├── AppDelegate.swift           # App lifecycle and coordination
├── HotkeyController.swift      # Global hotkey detection (Fn/Ctrl/Esc)
├── RecorderController.swift    # Audio recording with device management
├── OverlayWindow.swift         # Recording UI with positioning
├── WhisperClient.swift         # Azure Whisper API integration
├── TranscriptCleaner.swift     # Text processing and AI enhancement
├── SettingsView.swift          # Complete settings interface
├── PermissionManager.swift     # Microphone permission handling
├── WaveView.swift             # Real-time waveform visualization
└── CLAUDE.md                  # Development documentation
```

## Contributing

When contributing:

1. Follow existing Swift coding conventions
2. Test with multiple microphone types
3. Verify accessibility permissions work
4. Test overlay positioning on multiple screens
5. Check API integrations with both providers

## License

See LICENSE file for details.

## Support

For issues or questions:

1. Check this README for troubleshooting steps
2. Verify system permissions in macOS Settings
3. Test with different microphone devices
4. Confirm API credentials and connectivity

---

**Version 1.0** - Enhanced voice-to-text with comprehensive device support and flexible output options
