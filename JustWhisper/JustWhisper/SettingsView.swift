//
//  SettingsView.swift
//  JustWhisper
//
//  Created by Scott Soifer on 6/16/25.
//

import SwiftUI
import AVFoundation

/// SwiftUI view for user preferences and configuration
struct SettingsView: View {
    // Whisper Provider Selection
    @AppStorage("WhisperProvider") private var whisperProvider: String = "azure"

    // Azure Whisper Settings
    @AppStorage("AzureWhisperAPIKey") private var azureWhisperAPIKey: String = ""
    @AppStorage("AzureWhisperEndpoint") private var azureWhisperEndpoint: String = ""
    @AppStorage("AzureWhisperDeployment") private var azureWhisperDeployment: String = "whisper"
    @AppStorage("AzureWhisperAPIVersion") private var azureWhisperAPIVersion: String = "2024-08-01-preview"

    // OpenAI Whisper Settings
    @AppStorage("OpenAIWhisperAPIKey") private var openAIWhisperAPIKey: String = ""
    @AppStorage("OpenAIWhisperModel") private var openAIWhisperModel: String = "gpt-4o-mini-transcribe"
    @AppStorage("OpenAIWhisperBaseURL") private var openAIWhisperBaseURL: String = "https://api.openai.com/v1"

    // Azure OpenAI Settings
    @AppStorage("AzureOpenAIAPIKey") private var azureOpenAIAPIKey: String = ""
    @AppStorage("AzureOpenAIEndpoint") private var azureOpenAIEndpoint: String = ""
    @AppStorage("AzureOpenAIDeployment") private var azureOpenAIDeployment: String = "gpt-4o-mini"
    @AppStorage("AzureOpenAIAPIVersion") private var azureOpenAIAPIVersion: String = "2024-04-01-preview"

    // Standard OpenAI Settings
    @AppStorage("OpenAIAPIKey") private var openAIAPIKey: String = ""
    @AppStorage("OpenAIModel") private var openAIModel: String = "gpt-4o-mini"
    @AppStorage("OpenAIBaseURL") private var openAIBaseURL: String = "https://api.openai.com/v1"

    @AppStorage("JustWhisperEnabled") private var isEnabled: Bool = true
    @AppStorage("UseTestMode") private var useTestMode: Bool = false
    @AppStorage("AutoPauseMusic") private var autoPauseMusic: Bool = true
    @AppStorage("OverlayOpacity") private var overlayOpacity: Double = 0.85
    @AppStorage("OverlayPosition") private var overlayPosition: String = "center"

    // Overlay color settings
    @AppStorage("OverlayColorRed") private var overlayColorRed: Double = 0.2
    @AppStorage("OverlayColorGreen") private var overlayColorGreen: Double = 0.3
    @AppStorage("OverlayColorBlue") private var overlayColorBlue: Double = 0.5
    @AppStorage("OverlayColorAlpha") private var overlayColorAlpha: Double = 0.85

    // TranscriptCleaner options
    @AppStorage("RemoveFillerWords") private var removeFillerWords: Bool = true
    @AppStorage("ProcessLineBreakCommands") private var processLineBreakCommands: Bool = true
    @AppStorage("ProcessPunctuationCommands") private var processPunctuationCommands: Bool = true
    @AppStorage("ProcessFormattingCommands") private var processFormattingCommands: Bool = true
    @AppStorage("ApplySelfCorrection") private var applySelfCorrection: Bool = true
    @AppStorage("AutomaticCapitalization") private var automaticCapitalization: Bool = true
    @AppStorage("ApplyWordReplacements") private var applyWordReplacements: Bool = true
    @AppStorage("UseIntelligentWordReplacements") private var useIntelligentWordReplacements: Bool = true

    // OpenAI provider preference
    @AppStorage("UseAzureOpenAI") private var useAzureOpenAI: Bool = false
    @AppStorage("OpenAIProvider") private var openAIProvider: String = "azure"

    @State private var showingAPIKeyAlert = false
    @State private var showingTestView = false
    @State private var hasAccessibilityPermission = false
    @State private var showDebuggingSection = false
    @State private var isColorPickerOpen = false

    @StateObject private var permissionManager = PermissionManager()
    @StateObject private var recorder = RecorderController()
    @StateObject private var playback = PlaybackController()
    @StateObject private var whisperClient = WhisperClient()
    @ObservedObject private var stats = UsageStats.shared

    @State private var isTranscribing = false
    @State private var transcriptionResult = ""
    @State private var transcriptionError: String?

    @State private var wordReplacements: [String: String] = [:]
    @State private var newSearchTerm = ""
    @State private var newReplacement = ""
    private let transcriptCleaner = TranscriptCleaner()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                // Row 1: General + Permissions
                HStack(alignment: .top, spacing: 16) {
                    generalSection
                    permissionsSection
                }

                // Row 2: Whisper API + OpenAI API
                HStack(alignment: .top, spacing: 16) {
                    whisperSection
                    openAISection
                }

                // Row 3: Audio + Overlay
                HStack(alignment: .top, spacing: 16) {
                    audioTestSection
                    overlaySection
                }

                // Full-width sections
                statsSection

                transcriptCleanerSection

                wordReplacementSection

                advancedSection

                footerSection
            }
            .padding(28)
        }
        .frame(minWidth: 720, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .alert("API Key Required", isPresented: $showingAPIKeyAlert) {
            Button("OK") { }
        } message: {
            Text("Please enter your API key to use transcription features.")
        }
        .onAppear {
            checkPermissions()
            loadWordReplacements()
        }
        .onDisappear {
            if isColorPickerOpen {
                hideOverlayPreview()
                isColorPickerOpen = false
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center) {
            Image(systemName: "mic.fill")
                .font(.title2)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("JustWhisper Preferences")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Configure your voice transcription settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("v\(appVersion)")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.5))
                .cornerRadius(4)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    // MARK: - General

    private var generalSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("General", systemImage: "gearshape")
                    .font(.headline)
                    .foregroundColor(.primary)

                Divider()

                Toggle("Enable JustWhisper", isOn: $isEnabled)
                    .help("Enable or disable global hotkey capturing")

                Toggle("Mute audio while recording", isOn: $autoPauseMusic)
                    .help("Mute system audio when recording starts and unmute when done")

                Toggle("Test Mode", isOn: $useTestMode)
                    .help("Use dummy responses for testing without API calls")

                HStack(spacing: 6) {
                    Circle()
                        .fill(isEnabled ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(isEnabled ? "Active" : "Disabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Permissions", systemImage: "lock.shield")
                    .font(.headline)
                    .foregroundColor(.primary)

                Divider()

                permissionRow(
                    name: "Accessibility",
                    granted: hasAccessibilityPermission,
                    action: {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                    }
                )

                permissionRow(
                    name: "Microphone",
                    granted: permissionManager.hasRecordPermission,
                    action: { permissionManager.requestPermission() }
                )

                Button("Refresh") {
                    checkPermissions()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func permissionRow(name: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(granted ? .green : .red)
                .font(.body)

            Text(name)
                .font(.callout)

            Spacer()

            if !granted {
                Button("Grant") { action() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Whisper API

    private var whisperSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Whisper API", systemImage: "waveform")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("Speech-to-text transcription")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Picker("Provider", selection: $whisperProvider) {
                    Text("Azure").tag("azure")
                    Text("OpenAI").tag("openai")
                }
                .pickerStyle(.segmented)

                if whisperProvider == "azure" {
                    azureWhisperFields
                } else {
                    openAIWhisperFields
                }

                Button("Test Connection") {
                    testWhisperConnection()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canTestWhisper)
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var azureWhisperFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("API Key")
            SecureField("Azure Whisper API key", text: $azureWhisperAPIKey)
                .textFieldStyle(.roundedBorder)

            fieldLabel("Endpoint URL")
            TextField("https://your-resource.openai.azure.com/", text: $azureWhisperEndpoint)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Deployment")
                    TextField("whisper", text: $azureWhisperDeployment)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("API Version")
                    TextField("2024-08-01-preview", text: $azureWhisperAPIVersion)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var openAIWhisperFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("API Key")
            SecureField("OpenAI API key", text: $openAIWhisperAPIKey)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Model")
                    TextField("gpt-4o-mini-transcribe", text: $openAIWhisperModel)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Base URL")
                    TextField("https://api.openai.com/v1", text: $openAIWhisperBaseURL)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var canTestWhisper: Bool {
        if whisperProvider == "azure" {
            return !azureWhisperAPIKey.isEmpty && !azureWhisperEndpoint.isEmpty && !azureWhisperDeployment.isEmpty
        } else {
            return !openAIWhisperAPIKey.isEmpty && !openAIWhisperModel.isEmpty
        }
    }

    // MARK: - OpenAI API

    private var openAISection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("OpenAI API", systemImage: "brain")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("Enhanced transcript processing")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Picker("Provider", selection: $openAIProvider) {
                    Text("Azure").tag("azure")
                    Text("OpenAI").tag("openai")
                }
                .pickerStyle(.segmented)

                if openAIProvider == "azure" {
                    azureOpenAIFields
                } else {
                    standardOpenAIFields
                }

                Toggle("Use for enhanced formatting", isOn: $useAzureOpenAI)
                    .disabled(!canEnableOpenAI)

                if !canEnableOpenAI {
                    Text("Complete all fields above to enable")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var azureOpenAIFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("API Key")
            SecureField("Azure OpenAI API key", text: $azureOpenAIAPIKey)
                .textFieldStyle(.roundedBorder)

            fieldLabel("Endpoint URL")
            TextField("https://your-resource.openai.azure.com/", text: $azureOpenAIEndpoint)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Deployment")
                    TextField("gpt-4o-mini", text: $azureOpenAIDeployment)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("API Version")
                    TextField("2024-04-01-preview", text: $azureOpenAIAPIVersion)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var standardOpenAIFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("API Key")
            SecureField("OpenAI API key", text: $openAIAPIKey)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Model")
                    TextField("gpt-4o-mini", text: $openAIModel)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Base URL")
                    TextField("https://api.openai.com/v1", text: $openAIBaseURL)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var canEnableOpenAI: Bool {
        if openAIProvider == "azure" {
            return !azureOpenAIAPIKey.isEmpty && !azureOpenAIEndpoint.isEmpty && !azureOpenAIDeployment.isEmpty
        } else {
            return !openAIAPIKey.isEmpty && !openAIModel.isEmpty
        }
    }

    // MARK: - Audio Test

    private var audioTestSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Audio & Microphone", systemImage: "mic.badge.plus")
                    .font(.headline)
                    .foregroundColor(.primary)

                Divider()

                // Microphone selection
                HStack {
                    fieldLabel("Device")
                    Spacer()

                    Picker("Device", selection: $recorder.selectedDevice) {
                        ForEach(recorder.availableDevices) { device in
                            Text(device.name).tag(device)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .onChange(of: recorder.selectedDevice) { _, newDevice in
                        do {
                            try recorder.setInputDevice(newDevice)
                        } catch {
                            print("Failed to change microphone: \(error)")
                        }
                    }

                    Button(action: { recorder.refreshDevices() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if !recorder.availableDevices.isEmpty {
                    Text("\(recorder.availableDevices.count) device\(recorder.availableDevices.count == 1 ? "" : "s") found")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Record / Play controls
                HStack {
                    Button(action: {
                        if recorder.isRecording {
                            stopRecordingAndTranscribe()
                        } else {
                            do {
                                try recorder.startRecording()
                                transcriptionResult = ""
                                transcriptionError = nil
                            } catch {
                                print("Failed to start recording: \(error)")
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                                .foregroundColor(recorder.isRecording ? .red : .accentColor)
                            Text(recorder.isRecording ? "Stop" : "Record")
                        }
                    }
                    .disabled(!canRecord || isTranscribing)
                    .controlSize(.small)

                    if recorder.isRecording {
                        Text("\(String(format: "%.1f", recorder.duration))s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        if playback.isPlaying {
                            playback.stop()
                        } else if let url = recorder.getRecordingURL() {
                            playback.play(from: url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: playback.isPlaying ? "stop.fill" : "play.fill")
                            Text(playback.isPlaying ? "Stop" : "Play")
                        }
                    }
                    .disabled(!recorder.hasRecording || recorder.isRecording || isTranscribing)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if isTranscribing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Transcribing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !transcriptionResult.isEmpty {
                    Text(transcriptionResult)
                        .font(.caption)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary)
                        .cornerRadius(6)
                }

                if let error = transcriptionError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            permissionManager.checkPermissionStatus()
        }
    }

    private var canRecord: Bool {
        permissionManager.hasRecordPermission
    }

    // MARK: - Overlay Appearance

    private var overlaySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Overlay Appearance", systemImage: "rectangle.on.rectangle")
                    .font(.headline)
                    .foregroundColor(.primary)

                Divider()

                HStack {
                    fieldLabel("Position")
                    Spacer()
                    Picker("Position", selection: $overlayPosition) {
                        Text("Top Left").tag("top-left")
                        Text("Top Right").tag("top-right")
                        Text("Bottom Left").tag("bottom-left")
                        Text("Bottom Right").tag("bottom-right")
                        Text("Center").tag("center")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .onChange(of: overlayPosition) { _, _ in
                        if !isColorPickerOpen {
                            isColorPickerOpen = true
                            showOverlayPreview()
                        }
                    }
                }

                HStack {
                    fieldLabel("Color")
                    Spacer()
                    Circle()
                        .fill(Color(red: overlayColorRed, green: overlayColorGreen, blue: overlayColorBlue))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.gray, lineWidth: 1))

                    ColorPicker("", selection: Binding(
                        get: {
                            Color(red: overlayColorRed, green: overlayColorGreen, blue: overlayColorBlue, opacity: overlayColorAlpha)
                        },
                        set: { newColor in
                            if !isColorPickerOpen {
                                isColorPickerOpen = true
                                showOverlayPreview()
                            }
                            let nsColor = NSColor(newColor)
                            if let rgbColor = nsColor.usingColorSpace(.deviceRGB) {
                                overlayColorRed = Double(rgbColor.redComponent)
                                overlayColorGreen = Double(rgbColor.greenComponent)
                                overlayColorBlue = Double(rgbColor.blueComponent)
                                overlayColorAlpha = Double(rgbColor.alphaComponent)
                                UserDefaults.standard.synchronize()
                            }
                        }
                    ), supportsOpacity: true)
                    .labelsHidden()
                    .frame(width: 44)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        fieldLabel("Opacity")
                        Spacer()
                        Text("\(Int(overlayOpacity * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $overlayOpacity, in: 0.3...1.0)
                        .onChange(of: overlayOpacity) { _, _ in
                            if !isColorPickerOpen {
                                isColorPickerOpen = true
                                showOverlayPreview()
                            }
                        }
                }

                HStack {
                    Button(isColorPickerOpen ? "Hide Preview" : "Preview") {
                        if isColorPickerOpen {
                            hideOverlayPreview()
                            isColorPickerOpen = false
                        } else {
                            showOverlayPreview()
                            isColorPickerOpen = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Usage Stats

    private var statsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Usage Statistics", systemImage: "chart.bar")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    if stats.totalTranscriptions > 0 {
                        Button("Reset") {
                            stats.resetStats()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.red)
                    }
                }

                Divider()

                if stats.totalTranscriptions == 0 {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("No transcriptions yet")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            Text("Start recording to see your stats")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                } else {
                    // Stats grid - 3 columns
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        statCard(
                            value: "\(stats.totalWords)",
                            label: "Words Transcribed",
                            icon: "text.word.spacing"
                        )
                        statCard(
                            value: String(format: "%.1f", stats.totalRecordingMinutes),
                            label: "Minutes Recorded",
                            icon: "clock"
                        )
                        statCard(
                            value: "\(stats.totalTranscriptions)",
                            label: "Transcriptions",
                            icon: "number"
                        )
                        statCard(
                            value: String(format: "%.0f", stats.averageWordsPerTranscription),
                            label: "Avg Words/Session",
                            icon: "textformat.abc"
                        )
                        statCard(
                            value: String(format: "%.0f", stats.wordsPerMinute),
                            label: "Words/Minute",
                            icon: "speedometer"
                        )
                        statCard(
                            value: String(format: "%.0f", stats.longestRecordingSeconds) + "s",
                            label: "Longest Recording",
                            icon: "timer"
                        )
                    }

                    if let days = stats.daysSinceFirstUse, days > 0 {
                        HStack {
                            Spacer()
                            Text("Using JustWhisper for \(days) day\(days == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.accentColor)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .fontDesign(.rounded)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Transcript Processing

    private var transcriptCleanerSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Transcript Processing", systemImage: "text.badge.checkmark")
                    .font(.headline)
                    .foregroundColor(.primary)

                Divider()

                // Two-column toggles
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Remove filler words", isOn: $removeFillerWords)
                        Toggle("Line break commands", isOn: $processLineBreakCommands)
                        Toggle("Punctuation commands", isOn: $processPunctuationCommands)
                        Toggle("Formatting commands", isOn: $processFormattingCommands)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Self-correction", isOn: $applySelfCorrection)
                        Toggle("Auto-capitalization", isOn: $automaticCapitalization)
                        Toggle("Word replacements", isOn: $applyWordReplacements)
                    }
                }
                .font(.callout)

                Divider()

                Text("Voice commands: say 'new line', 'period', 'bullet point', etc.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Word Replacements

    private var wordReplacementSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Word Replacements", systemImage: "arrow.left.arrow.right")
                    .font(.headline)
                    .foregroundColor(.primary)

                Divider()

                if applyWordReplacements {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            fieldLabel("Search for")
                            TextField("e.g., nearchat", text: $newSearchTerm)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            fieldLabel("Replace with")
                            TextField("e.g., Ner Chat", text: $newReplacement)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: addWordReplacement) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(newSearchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                 newReplacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .padding(.top, 16)
                    }

                    if !wordReplacements.isEmpty {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(wordReplacements.keys).sorted(), id: \.self) { searchTerm in
                                    if let replacement = wordReplacements[searchTerm] {
                                        HStack {
                                            Text("\"\(searchTerm)\"")
                                                .font(.caption)
                                            Image(systemName: "arrow.right")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text("\"\(replacement)\"")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Button(action: { removeWordReplacement(searchTerm: searchTerm) }) {
                                                Image(systemName: "minus.circle.fill")
                                                    .foregroundColor(.red)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.vertical, 3)
                                        .padding(.horizontal, 8)
                                        .background(.quaternary.opacity(0.5))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 100)

                        HStack {
                            Text("\(wordReplacements.count) replacement\(wordReplacements.count == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Clear All") { clearAllReplacements() }
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                } else {
                    Text("Enable word replacements in Transcript Processing above")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                DisclosureGroup("Troubleshooting & Advanced", isExpanded: $showDebuggingSection) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Use these if the overlay is stuck or hotkeys stop working:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Button("Force Hide Overlay") {
                                if let appDelegate = NSApp.delegate as? AppDelegate {
                                    appDelegate.forceHideOverlay()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Restart Hotkeys") {
                                if let appDelegate = NSApp.delegate as? AppDelegate {
                                    appDelegate.restartHotkeys()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Spacer()

                            Button("Reset to Defaults") {
                                resetToDefaults()
                            }
                            .foregroundColor(.red)
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.headline)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Text("Hold Fn key to start recording")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
    }

    private func checkPermissions() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        permissionManager.checkPermissionStatus()
    }

    private func testWhisperConnection() {
        if whisperProvider == "azure" {
            guard !azureWhisperAPIKey.isEmpty else {
                showingAPIKeyAlert = true
                return
            }
            print("Testing Azure Whisper API connection with endpoint: \(azureWhisperEndpoint)")
        } else {
            guard !openAIWhisperAPIKey.isEmpty else {
                showingAPIKeyAlert = true
                return
            }
            print("Testing OpenAI Whisper API connection with base URL: \(openAIWhisperBaseURL)")
        }
    }

    private func resetToDefaults() {
        whisperProvider = "azure"
        azureWhisperAPIKey = ""
        azureWhisperEndpoint = ""
        azureWhisperDeployment = "whisper"
        azureWhisperAPIVersion = "2024-08-01-preview"
        openAIWhisperAPIKey = ""
        openAIWhisperModel = "gpt-4o-mini-transcribe"
        openAIWhisperBaseURL = "https://api.openai.com/v1"
        azureOpenAIAPIKey = ""
        azureOpenAIEndpoint = ""
        azureOpenAIDeployment = "gpt-4o-mini"
        azureOpenAIAPIVersion = "2024-04-01-preview"
        openAIAPIKey = ""
        openAIModel = "gpt-4o-mini"
        openAIBaseURL = "https://api.openai.com/v1"
        openAIProvider = "azure"
        isEnabled = true
        useTestMode = false
        autoPauseMusic = true
        overlayOpacity = 0.85
        overlayPosition = "center"
        overlayColorRed = 0.2
        overlayColorGreen = 0.3
        overlayColorBlue = 0.5
        overlayColorAlpha = 0.85
        removeFillerWords = true
        processLineBreakCommands = true
        processPunctuationCommands = true
        processFormattingCommands = true
        applySelfCorrection = true
        automaticCapitalization = true
        applyWordReplacements = true
        useAzureOpenAI = false
    }

    private func stopRecordingAndTranscribe() {
        recorder.stopRecording()
        guard let recordingURL = recorder.getRecordingURL() else {
            transcriptionError = "No recording found"
            return
        }
        Task { await transcribeAudio(from: recordingURL) }
    }

    @MainActor
    private func transcribeAudio(from url: URL) async {
        isTranscribing = true
        transcriptionError = nil
        transcriptionResult = ""

        do {
            let audioData = try Data(contentsOf: url)
            let result = try await whisperClient.transcribe(audioData: audioData)
            transcriptionResult = result
        } catch {
            transcriptionError = "Failed to transcribe: \(error.localizedDescription)"
        }

        isTranscribing = false
    }

    // MARK: - Word Replacement Methods

    private func loadWordReplacements() {
        wordReplacements = transcriptCleaner.getWordReplacements()
    }

    private func addWordReplacement() {
        let searchTerm = newSearchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = newReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchTerm.isEmpty && !replacement.isEmpty else { return }
        transcriptCleaner.addWordReplacement(searchTerm: searchTerm, replacement: replacement)
        loadWordReplacements()
        newSearchTerm = ""
        newReplacement = ""
    }

    private func removeWordReplacement(searchTerm: String) {
        transcriptCleaner.removeWordReplacement(searchTerm: searchTerm)
        loadWordReplacements()
    }

    private func clearAllReplacements() {
        transcriptCleaner.clearWordReplacements()
        loadWordReplacements()
    }

    // MARK: - Overlay Preview Methods

    private func showOverlayPreview() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showOverlayPreview()
        }
    }

    private func hideOverlayPreview() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.hideOverlayPreview()
        }
    }
}

#Preview {
    SettingsView()
}
