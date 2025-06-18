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
    // Azure Whisper Settings
    @AppStorage("AzureWhisperAPIKey") private var azureWhisperAPIKey: String = ""
    @AppStorage("AzureWhisperEndpoint") private var azureWhisperEndpoint: String = ""
    @AppStorage("AzureWhisperDeployment") private var azureWhisperDeployment: String = "whisper"
    @AppStorage("AzureWhisperAPIVersion") private var azureWhisperAPIVersion: String = "2024-08-01-preview"
    
    // Azure OpenAI Settings
    @AppStorage("AzureOpenAIAPIKey") private var azureOpenAIAPIKey: String = ""
    @AppStorage("AzureOpenAIEndpoint") private var azureOpenAIEndpoint: String = ""
    @AppStorage("AzureOpenAIDeployment") private var azureOpenAIDeployment: String = "gpt-4o-mini"
    @AppStorage("AzureOpenAIAPIVersion") private var azureOpenAIAPIVersion: String = "2024-04-01-preview"
    
    @AppStorage("JustWhisperEnabled") private var isEnabled: Bool = true
    @AppStorage("UseTestMode") private var useTestMode: Bool = false
    @AppStorage("OverlayOpacity") private var overlayOpacity: Double = 0.85
    @AppStorage("OverlayPosition") private var overlayPosition: String = "top-right"
    
    // Overlay color settings - stored as RGB components
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
    
    // Azure OpenAI preference
    @AppStorage("UseAzureOpenAI") private var useAzureOpenAI: Bool = false
    
    @State private var showingAPIKeyAlert = false
    @State private var showingTestView = false
    
    // Use the new PermissionManager
    @StateObject private var permissionManager = PermissionManager()
    
    // Audio recording/playback using proper controllers
    @StateObject private var recorder = RecorderController()
    @StateObject private var playback = PlaybackController()
    @StateObject private var whisperClient = WhisperClient()
    
    // Transcription state
    @State private var isTranscribing = false
    @State private var transcriptionResult = ""
    @State private var transcriptionError: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                
                generalSection
                
                audioTestSection
                
                whisperSection
                
                azureOpenAISection
                
                overlaySection
                
                advancedSection
                
                transcriptCleanerSection
                
                footerSection
            }
            .padding(24)
        }
        .frame(width: 480, height: 600)
        .alert("API Key Required", isPresented: $showingAPIKeyAlert) {
            Button("OK") { }
        } message: {
            Text("Please enter your Azure Whisper API key to use transcription features.")
        }
        .onAppear {
            permissionManager.checkPermissionStatus()
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("JustWhisper Preferences")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Text("Configure your voice transcription settings")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Version \(appVersion)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    private var generalSection: some View {
        GroupBox("General") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable JustWhisper", isOn: $isEnabled)
                    .help("Enable or disable global hotkey capturing")
                
                HStack {
                    Text("Status:")
                    Text(isEnabled ? "Active" : "Disabled")
                        .foregroundColor(isEnabled ? .green : .red)
                        .fontWeight(.medium)
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
        }
    }
    
    private var audioTestSection: some View {
        GroupBox("Audio Test") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Microphone Permission:")
                        Text(permissionManager.hasRecordPermission ? "Authorized" : "Not Authorized")
                            .foregroundColor(permissionManager.hasRecordPermission ? .green : .red)
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Button("Request Permission") {
                            permissionManager.requestPermission()
                        }
                        .buttonStyle(.bordered)
                        .help("Request microphone permission")
                        .disabled(permissionManager.isCheckingPermission)
                        
                        Button("Check Status") {
                            permissionManager.checkPermissionStatus()
                        }
                        .buttonStyle(.bordered)
                        .help("Check current permission status")
                    }
                    
                    if !permissionManager.hasRecordPermission {
                        Text("Microphone access is required for audio recording. Click 'Request Permission' to enable.")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                .font(.caption)
                
                Divider()
                
                HStack {
                    Button(action: {
                        if recorder.isRecording {
                            stopRecordingAndTranscribe()
                        } else {
                            do {
                                try recorder.startRecording()
                                // Clear previous transcription when starting new recording
                                transcriptionResult = ""
                                transcriptionError = nil
                            } catch {
                                print("Failed to start recording: \(error)")
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                                .foregroundColor(recorder.isRecording ? .red : .accentColor)
                            Text(recorder.isRecording ? "Stop Recording" : "Start Recording")
                        }
                    }
                    .disabled(!canRecord || isTranscribing)
                    
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
                        HStack {
                            Image(systemName: playback.isPlaying ? "stop.fill" : "play.fill")
                            Text(playback.isPlaying ? "Stop" : "Play")
                        }
                    }
                    .disabled(!recorder.hasRecording || recorder.isRecording || isTranscribing)
                    .buttonStyle(.bordered)
                }
                
                if !canRecord {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Microphone permission is required to test audio recording")
                            .font(.caption)
                            .foregroundColor(.orange)
                        
                        Text("Click 'Request Permission' to enable microphone access")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Transcription status
                if isTranscribing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Transcribing audio...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
                
                // Transcription result
                if !transcriptionResult.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transcription:")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Text(transcriptionResult)
                            .font(.caption)
                            .padding(8)
                            .background(.quaternary)
                            .cornerRadius(6)
                    }
                    .padding(.top, 4)
                }
                
                // Transcription error
                if let error = transcriptionError {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transcription Error:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                        
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(8)
                            .background(.red.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 4)
        }
        .onAppear {
            permissionManager.checkPermissionStatus()
        }
    }
    
    private var canRecord: Bool {
        permissionManager.hasRecordPermission
    }
    
    private var whisperSection: some View {
        GroupBox("Azure Whisper API") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    SecureField("Enter your Azure Whisper API key", text: $azureWhisperAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .help("Your Azure Whisper API key for transcription")
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Endpoint URL")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    TextField("https://your-resource.openai.azure.com/", text: $azureWhisperEndpoint)
                        .textFieldStyle(.roundedBorder)
                        .help("Azure Whisper endpoint URL")
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Deployment")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        TextField("whisper", text: $azureWhisperDeployment)
                            .textFieldStyle(.roundedBorder)
                            .help("Azure Whisper deployment name")
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Version")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        TextField("2024-08-01-preview", text: $azureWhisperAPIVersion)
                            .textFieldStyle(.roundedBorder)
                            .help("Azure API version")
                    }
                }
                
                Button("Test Connection") {
                    testAPIConnection()
                }
                .disabled(azureWhisperAPIKey.isEmpty || azureWhisperEndpoint.isEmpty || azureWhisperDeployment.isEmpty)
            }
            .padding(.vertical, 4)
        }
    }
    
    private var azureOpenAISection: some View {
        GroupBox("Azure OpenAI API (for Enhanced Transcript Processing)") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    SecureField("Enter your Azure OpenAI API key", text: $azureOpenAIAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .help("Your Azure OpenAI API key for transcript enhancement")
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Endpoint URL")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    TextField("https://your-resource.openai.azure.com/", text: $azureOpenAIEndpoint)
                        .textFieldStyle(.roundedBorder)
                        .help("Azure OpenAI endpoint URL")
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Deployment")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        TextField("gpt-4o-mini", text: $azureOpenAIDeployment)
                            .textFieldStyle(.roundedBorder)
                            .help("Azure OpenAI deployment name")
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Version")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        TextField("2024-04-01-preview", text: $azureOpenAIAPIVersion)
                            .textFieldStyle(.roundedBorder)
                            .help("Azure OpenAI API version")
                    }
                }
                
                Toggle("Use Azure OpenAI for Enhanced Formatting", isOn: $useAzureOpenAI)
                    .disabled(azureOpenAIAPIKey.isEmpty || azureOpenAIEndpoint.isEmpty || azureOpenAIDeployment.isEmpty)
                    .help("Uses Azure OpenAI to intelligently format and clean transcripts")
                
                if azureOpenAIAPIKey.isEmpty || azureOpenAIEndpoint.isEmpty || azureOpenAIDeployment.isEmpty {
                    Text("Complete all fields above to enable Azure OpenAI transcript enhancement")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private var overlaySection: some View {
        GroupBox("Overlay Appearance") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Position")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Picker("Position", selection: $overlayPosition) {
                        Text("Top Left").tag("top-left")
                        Text("Top Right").tag("top-right")
                        Text("Bottom Left").tag("bottom-left")
                        Text("Bottom Right").tag("bottom-right")
                    }
                    .pickerStyle(.menu)
                    .help("Position of the recording overlay on screen")
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Opacity")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text("\(Int(overlayOpacity * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $overlayOpacity, in: 0.3...1.0)
                        .help("Transparency level of the recording overlay")
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Background Color")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        // Color preview circle
                        Circle()
                            .fill(Color(red: overlayColorRed, green: overlayColorGreen, blue: overlayColorBlue))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(Color.gray, lineWidth: 1)
                            )
                    }
                    
                    ColorPicker("Background Color", selection: Binding(
                        get: {
                            Color(red: overlayColorRed, green: overlayColorGreen, blue: overlayColorBlue, opacity: overlayColorAlpha)
                        },
                        set: { newColor in
                            if let components = newColor.cgColor?.components {
                                overlayColorRed = Double(components[0])
                                overlayColorGreen = Double(components[1])
                                overlayColorBlue = Double(components[2])
                                if components.count > 3 {
                                    overlayColorAlpha = Double(components[3])
                                }
                            }
                        }
                    ), supportsOpacity: true)
                    .labelsHidden()
                    .help("Choose the background color for the recording overlay")
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private var advancedSection: some View {
        GroupBox("Advanced") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Test Mode", isOn: $useTestMode)
                    .help("Use dummy responses for testing without API calls")
                
                if useTestMode {
                    Text("Using simulated responses for testing")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                Divider()
                
                Button("Reset to Defaults") {
                    resetToDefaults()
                }
                .foregroundColor(.red)
            }
            .padding(.vertical, 4)
        }
    }
    
    private var transcriptCleanerSection: some View {
        GroupBox("Transcript Processing") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Remove Filler Words", isOn: $removeFillerWords)
                    .help("Remove words like 'um', 'uh', 'like', etc.")
                
                Toggle("Process Line Break Commands", isOn: $processLineBreakCommands)
                    .help("Convert commands like 'new line', 'bullet point', 'paragraph' to proper formatting")
                
                Toggle("Process Punctuation Commands", isOn: $processPunctuationCommands)
                    .help("Convert spoken punctuation like 'period', 'comma' to actual punctuation marks")
                
                Toggle("Process Formatting Commands", isOn: $processFormattingCommands)
                    .help("Process commands like 'quote', 'all caps', etc.")
                
                Toggle("Apply Self-Correction", isOn: $applySelfCorrection)
                    .help("Handle corrections like 'I think... Actually, I believe'")
                
                Toggle("Automatic Capitalization", isOn: $automaticCapitalization)
                    .help("Automatically capitalize the first letter of sentences")
                
                Divider()
                
                Text("Voice Commands:")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text("Say 'new line', 'period', 'bullet point', etc. to format your text")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
    
    private var footerSection: some View {
        VStack(spacing: 8) {
            Divider()
            
            HStack {
                Text("Hold Fn key to start recording")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("JustWhisper v1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func testAPIConnection() {
        // Basic validation
        guard !azureWhisperAPIKey.isEmpty else {
            showingAPIKeyAlert = true
            return
        }
        
        // TODO: Implement actual API test
        print("Testing Azure Whisper API connection with endpoint: \(azureWhisperEndpoint)")
        print("Using deployment: \(azureWhisperDeployment)")
    }
    
    private func resetToDefaults() {
        // Azure Whisper settings
        azureWhisperAPIKey = ""
        azureWhisperEndpoint = ""
        azureWhisperDeployment = "whisper"
        azureWhisperAPIVersion = "2024-08-01-preview"
        
        // Azure OpenAI settings
        azureOpenAIAPIKey = ""
        azureOpenAIEndpoint = ""
        azureOpenAIDeployment = "gpt-4o-mini"
        azureOpenAIAPIVersion = "2024-04-01-preview"
        
        // General settings
        isEnabled = true
        useTestMode = false
        overlayOpacity = 0.85
        overlayPosition = "top-right"
        
        // Reset transcript cleaner options
        removeFillerWords = true
        processLineBreakCommands = true
        processPunctuationCommands = true
        processFormattingCommands = true
        applySelfCorrection = true
        automaticCapitalization = true
        useAzureOpenAI = false
    }
    
    private func stopRecordingAndTranscribe() {
        // Stop the recording first
        recorder.stopRecording()
        
        // Get the recorded audio file
        guard let recordingURL = recorder.getRecordingURL() else {
            transcriptionError = "No recording found"
            return
        }
        
        // Start transcription
        Task {
            await transcribeAudio(from: recordingURL)
        }
    }
    
    @MainActor
    private func transcribeAudio(from url: URL) async {
        isTranscribing = true
        transcriptionError = nil
        transcriptionResult = ""
        
        do {
            // Read the audio file data
            let audioData = try Data(contentsOf: url)
            
            // Send to Whisper for transcription
            let result = try await whisperClient.transcribe(audioData: audioData)
            
            // Update UI with result
            transcriptionResult = result
            print("Transcription successful: \(result)")
            
        } catch {
            // Handle transcription error
            transcriptionError = "Failed to transcribe: \(error.localizedDescription)"
            print("Transcription failed: \(error)")
        }
        
        isTranscribing = false
    }
}

#Preview {
    SettingsView()
}
