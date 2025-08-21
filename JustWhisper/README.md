# JustWhisper

A macOS menu bar application that provides voice-to-text transcription using Azure Whisper API. Record your voice, get accurate transcriptions, and automatically paste them into any application.

---

> **Hey everyone! This is Scott just having some fun with Claude Code and Cursor + ChatGPT-5!**
>
> This project was purely vibe-coded because I wanted a quick tool that works with my personal HIPAA-compliant API models so I don't have to worry about data privacy. No corporate overlords snooping on my voice notes! 🕵️‍♂️
>
> Built this during late-night coding sessions fueled by questionable amounts of coffee ☕ and the occasional existential crisis about whether AI will replace us all (spoiler: it's helping me code faster, so... maybe? 🤖).
>
> Feel free to:
>
> - 🐛 **Create issues** if something breaks
> - 🚀 **Make PRs** if you want to add cool features
> - 💬 **Leave feedback** or just say hi!
> - ⭐ **Star this repo** if it saved you from typing (your wrists will thank you)
>
> _P.S. - Yes, I know there are other transcription apps. But this one is MINE and it does exactly what I want. Sometimes that's all that matters. 🎯_

---

## Features

- **Dual Whisper Support**: Choose between Azure Whisper or OpenAI Whisper for transcription
- **Global Hotkeys**: Press Fn key to start/stop recording from anywhere on macOS
- **Smart Text Processing**: Automatic filler word removal, punctuation, and formatting
- **Flexible Output**: Choose between pasting text directly or copying to clipboard
- **Microphone Selection**: Pick from any available audio input device
- **AI Enhancement**: Optional OpenAI/Azure OpenAI integration for improved transcript quality
- **Customizable Overlay**: Position, color, and preview your recording indicator
- **Privacy First**: Use your own API keys - your data stays with your chosen provider

## Quick Start

### Prerequisites

1. **Whisper API Access**: You'll need either:
   - **Azure Whisper**: Azure OpenAI resource with Whisper deployment, OR
   - **OpenAI Whisper**: Standard OpenAI API account with Whisper access
2. **macOS Permissions**: The app requires microphone and accessibility permissions

### Setup

1. **Download and Install**: Place JustWhisper.app in your Applications folder
2. **Launch**: Run the app - it will appear in your menu bar
3. **Configure API**: Open Preferences and choose your Whisper provider:

   **For Azure Whisper:**

   - API Key
   - Endpoint URL (e.g., `https://your-resource.openai.azure.com/`)
   - Deployment name (usually `whisper`)
   - API Version (e.g., `2024-08-01-preview`)

   **For OpenAI Whisper:**

   - API Key
   - Model (usually `whisper-1`)
   - Base URL (default: `https://api.openai.com/v1`)

4. **Grant Permissions**:
   - **Microphone**: Required for audio recording
   - **Accessibility**: Required for global hotkeys and text pasting

## Usage

### Basic Recording

1. **Start Recording**: Press the **Fn key** to begin recording
2. **Stop Recording**: Press **Fn key** again to stop and process
3. **Auto-Paste**: Transcribed text is automatically pasted into the focused application

### Copy-Only Mode

1. **Start Recording**: Press **Fn key** to begin recording
2. **Copy to Clipboard**: Press **Ctrl key** to stop recording and copy text to clipboard (no paste)

### Cancel Recording

- **Escape Key**: Press **Escape** while recording to cancel and hide the overlay

## Settings & Configuration

### Audio Settings

- **Microphone Device**: Choose which microphone to use for recording
- **Permission Status**: Check and request microphone permissions

### API Configuration

#### Whisper Provider (Required)

Choose between Azure Whisper or OpenAI Whisper for speech-to-text conversion.

**Azure Whisper:**

- Requires Azure OpenAI resource with Whisper deployment
- Enterprise-grade with custom endpoints
- Good for HIPAA compliance and data residency requirements

**OpenAI Whisper:**

- Direct OpenAI API access
- Simple setup with just an API key
- Pay-per-use pricing model

#### OpenAI Enhancement (Optional)

Choose between Azure OpenAI or standard OpenAI for enhanced transcript processing:

**Azure OpenAI:**

- API Key, Endpoint, Deployment name, API Version

**Standard OpenAI:**

- API Key, Model (e.g., `gpt-4o-mini`), Base URL

### Overlay Appearance

- **Position**: Top-left, top-right, bottom-left, bottom-right, or center
- **Color**: Customize background color and opacity
- **Real-time Updates**: Changes apply immediately without app restart

### Transcript Processing

- **Filler Word Removal**: Remove "um", "uh", "like", etc.
- **Voice Commands**: Process "new line", "period", "bullet point" commands
- **Auto-Capitalization**: Capitalize first letters of sentences
- **Word Replacements**: Custom dictionary for fixing common transcription errors

## Keyboard Shortcuts

| Key                           | Action                                            |
| ----------------------------- | ------------------------------------------------- |
| **Fn**                        | Start/Stop recording with GPT-enhanced auto-paste |
| **Ctrl** (during recording)   | Stop recording and paste without GPT enhancement  |
| **Escape** (during recording) | Cancel recording                                  |

## Troubleshooting

### Recording Not Working

1. **Check Permissions**: Verify microphone and accessibility permissions in System Preferences
2. **Try Different Microphone**: Use the microphone selector in settings
3. **Check API Configuration**: Ensure Azure Whisper credentials are correct

### Hotkeys Not Responding

1. **Accessibility Permission**: Make sure JustWhisper has accessibility permission
2. **Enable/Disable**: Use the toggle in settings to restart the hotkey system
3. **Check Other Apps**: Some apps may intercept function keys

### Overlay Not Positioning Correctly

1. **Settings Update**: Change the position setting - it updates immediately
2. **Screen Changes**: Overlay repositions automatically when changing displays

### Poor Transcription Quality

1. **Microphone Quality**: Ensure you're using a good microphone
2. **Background Noise**: Record in a quiet environment
3. **Enable AI Enhancement**: Use OpenAI processing for better results
4. **Custom Word Replacements**: Add common transcription errors to the word replacement dictionary

## System Requirements

- **macOS**: 14.2 or later
- **Architecture**: Apple Silicon (ARM64) or Intel x64
- **Internet**: Required for Azure Whisper API calls
- **Permissions**: Microphone access, Accessibility permissions

## Privacy & Security

- **Local Processing**: Audio processing and text cleaning happen locally when possible
- **API Calls**: Audio data is sent to Azure Whisper API for transcription only
- **No Storage**: Audio recordings are temporary and deleted after processing
- **Sandboxed**: App runs in macOS sandbox for security

## Development

Built with:

- **Swift 5.0** and **SwiftUI**
- **AVAudioEngine** for audio recording
- **CGEvent** for global hotkeys and text insertion
- **Core Audio** for device management

## License

See LICENSE file for details.

## Support

For issues, feature requests, or questions, please check:

1. This README for common solutions
2. System preferences for permission issues
3. API provider documentation for credential setup

---

**Version 1.0** - Made with ❤️ for efficient voice-to-text on macOS
