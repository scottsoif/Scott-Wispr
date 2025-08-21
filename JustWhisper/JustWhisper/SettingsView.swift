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
    @AppStorage("OpenAIWhisperModel") private var openAIWhisperModel: String = "whisper-1"
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
    @AppStorage("OverlayOpacity") private var overlayOpacity: Double = 0.85
    @AppStorage("OverlayPosition") private var overlayPosition: String = "center"
    
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
    @AppStorage("ApplyWordReplacements") private var applyWordReplacements: Bool = true
    @AppStorage("UseIntelligentWordReplacements") private var useIntelligentWordReplacements: Bool = true
    
    // OpenAI provider preference
    @AppStorage("UseAzureOpenAI") private var useAzureOpenAI: Bool = false
    @AppStorage("OpenAIProvider") private var openAIProvider: String = "azure" // "azure" or "openai"
    
    @State private var showingAPIKeyAlert = false
    @State private var showingTestView = false
    @State private var hasAccessibilityPermission = false
    @State private var showDebuggingSection = false
    @State private var isColorPickerOpen = false
    
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
    
    // Word replacement management
    @State private var wordReplacements: [String: String] = [:]
    @State private var newSearchTerm = ""
    @State private var newReplacement = ""
    private let transcriptCleaner = TranscriptCleaner()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                
                generalSection
                
                permissionsSection
                
                debuggingSection
                
                audioTestSection
                
                whisperSection
                
                openAISection
                
                overlaySection
                
                advancedSection
                
                transcriptCleanerSection
                
                wordReplacementSection
                
                footerSection
            }
            .padding(24)
        }
        .frame(minWidth: 480, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .alert("API Key Required", isPresented: $showingAPIKeyAlert) {
            Button("OK") { }
        } message: {
            Text("Please enter your Azure Whisper API key to use transcription features.")
        }
        .onAppear {
            checkPermissions()
            loadWordReplacements()
        }
        .onDisappear {
            // Hide overlay preview when settings window closes
            if isColorPickerOpen {
                print("🎨 Settings window closing - hiding overlay preview")
                hideOverlayPreview()
                isColorPickerOpen = false
            }
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
    
    private var permissionsSection: some View {
        GroupBox("Permission Status") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Current permissions:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    
                    // Accessibility Permission
                    HStack {
                        Image(systemName: hasAccessibilityPermission ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(hasAccessibilityPermission ? .green : .red)
                        
                        Text("Accessibility: \(hasAccessibilityPermission ? "Granted" : "Not Granted")")
                            .font(.system(.body, design: .monospaced))
                        
                        Spacer()
                        
                        Button("Refresh") {
                            checkPermissions()
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.blue)
                        .help("Check current permission status")
                    }
                    
                    // Microphone Permission
                    HStack {
                        Image(systemName: permissionManager.hasRecordPermission ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(permissionManager.hasRecordPermission ? .green : .red)
                        
                        Text("Microphone: \(permissionManager.hasRecordPermission ? "Granted" : "Not Granted")")
                            .font(.system(.body, design: .monospaced))
                        
                        Spacer()
                    }
                }
                
                if !hasAccessibilityPermission || !permissionManager.hasRecordPermission {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if !hasAccessibilityPermission {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Accessibility permission is required for the Fn key to work globally (even when JustWhisper is not the active app).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Button("Grant Accessibility Permission") {
                                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                                    NSWorkspace.shared.open(url)
                                }
                                .buttonStyle(.borderedProminent)
                                .help("Opens System Preferences to grant accessibility permission")
                            }
                        }
                        
                        if !permissionManager.hasRecordPermission {
                            Button("Grant Microphone Permission") {
                                permissionManager.requestPermission()
                            }
                            .buttonStyle(.borderedProminent)
                            .help("Request microphone permission")
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private var debuggingSection: some View {
        GroupBox("Troubleshooting") {
            VStack(alignment: .leading, spacing: 12) {
                DisclosureGroup("Debug Controls", isExpanded: $showDebuggingSection) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Use these controls if the overlay is stuck visible or the Fn key is not working:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            Button("Force Hide Overlay") {
                                // Need to access the overlay window through AppDelegate
                                if let appDelegate = NSApp.delegate as? AppDelegate {
                                    appDelegate.forceHideOverlay()
                                }
                            }
                            .buttonStyle(.bordered)
                            .help("Forcefully hide the overlay if it's stuck visible")
                            
                            Button("Restart Hotkeys") {
                                if let appDelegate = NSApp.delegate as? AppDelegate {
                                    appDelegate.restartHotkeys()
                                }
                            }
                            .buttonStyle(.bordered)
                            .help("Restart the global hotkey system")
                        }
                    }
                }
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
                    
                    // Microphone selection dropdown
                    HStack {
                        Text("Microphone Device:")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Picker("Microphone Device", selection: $recorder.selectedDevice) {
                            ForEach(recorder.availableDevices) { device in
                                Text(device.name).tag(device)
                            }
                        }
                        .pickerStyle(.menu)
                        .help("Select which microphone to use for recording")
                        .onChange(of: recorder.selectedDevice) { _, newDevice in
                            do {
                                try recorder.setInputDevice(newDevice)
                                print("✅ Successfully changed microphone to: \(newDevice.name)")
                            } catch {
                                print("❌ Failed to change microphone: \(error)")
                                // Show user feedback for device switching issues
                                if newDevice.name.contains("AirPods") {
                                    print("💡 Tip: Make sure AirPods are connected and set as input device in System Preferences")
                                }
                            }
                        }
                        
                        Button(action: {
                            recorder.refreshDevices()
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .help("Refresh available microphones")
                    }
                    
                    if !recorder.availableDevices.isEmpty {
                        Text("Found \(recorder.availableDevices.count) microphone device\(recorder.availableDevices.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
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
        GroupBox("Whisper API (for Transcription)") {
            VStack(alignment: .leading, spacing: 12) {
                // Provider selection
                VStack(alignment: .leading, spacing: 4) {
                    Text("Whisper Provider")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Picker("Whisper Provider", selection: $whisperProvider) {
                        Text("Azure Whisper").tag("azure")
                        Text("OpenAI Whisper").tag("openai")
                    }
                    .pickerStyle(.segmented)
                    .help("Choose between Azure Whisper or OpenAI Whisper API")
                }
                
                Divider()
                
                if whisperProvider == "azure" {
                    azureWhisperFields
                } else {
                    openAIWhisperFields
                }
                
                Button("Test Connection") {
                    testWhisperConnection()
                }
                .disabled(!canTestWhisper)
            }
            .padding(.vertical, 4)
        }
    }
    
    private var azureWhisperFields: some View {
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
        }
    }
    
    private var openAIWhisperFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.caption)
                    .fontWeight(.medium)
                
                SecureField("Enter your OpenAI API key", text: $openAIWhisperAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .help("Your OpenAI API key for transcription")
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    TextField("whisper-1", text: $openAIWhisperModel)
                        .textFieldStyle(.roundedBorder)
                        .help("OpenAI Whisper model (whisper-1 is the standard model)")
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Base URL")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    TextField("https://api.openai.com/v1", text: $openAIWhisperBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .help("OpenAI API base URL (change for custom endpoints)")
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
    
    private var openAISection: some View {
        GroupBox("OpenAI API (for Enhanced Transcript Processing)") {
            VStack(alignment: .leading, spacing: 12) {
                // Provider selection
                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Picker("OpenAI Provider", selection: $openAIProvider) {
                        Text("Azure OpenAI").tag("azure")
                        Text("Standard OpenAI").tag("openai")
                    }
                    .pickerStyle(.segmented)
                    .help("Choose between Azure OpenAI or standard OpenAI API")
                }
                
                Divider()
                
                if openAIProvider == "azure" {
                    azureOpenAIFields
                } else {
                    standardOpenAIFields
                }
                
                Toggle("Use OpenAI for Enhanced Formatting", isOn: $useAzureOpenAI)
                    .disabled(!canEnableOpenAI)
                    .help("Uses OpenAI to intelligently format and clean transcripts")
                
                if !canEnableOpenAI {
                    Text("Complete all fields above to enable OpenAI transcript enhancement")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private var azureOpenAIFields: some View {
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
        }
    }
    
    private var standardOpenAIFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.caption)
                    .fontWeight(.medium)
                
                SecureField("Enter your OpenAI API key", text: $openAIAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .help("Your OpenAI API key for transcript enhancement")
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    TextField("gpt-4o-mini", text: $openAIModel)
                        .textFieldStyle(.roundedBorder)
                        .help("OpenAI model to use (e.g., gpt-4o-mini, gpt-4, gpt-3.5-turbo)")
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Base URL")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    TextField("https://api.openai.com/v1", text: $openAIBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .help("OpenAI API base URL (change for custom endpoints)")
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
                        Text("Center").tag("center")
                    }
                    .pickerStyle(.menu)
                    .help("Position of the recording overlay on screen")
                    .onChange(of: overlayPosition) { _, _ in
                        // Show overlay preview when position changes
                        if !isColorPickerOpen {
                            print("📍 Position changed - showing overlay preview")
                            isColorPickerOpen = true
                            showOverlayPreview()
                        }
                    }
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
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ColorPicker("Background Color", selection: Binding(
                            get: {
                                Color(red: overlayColorRed, green: overlayColorGreen, blue: overlayColorBlue, opacity: overlayColorAlpha)
                            },
                            set: { newColor in
                                // Show overlay preview when color changes (if not already shown)
                                if !isColorPickerOpen {
                                    print("🎨 Color picker interaction detected - showing overlay preview")
                                    isColorPickerOpen = true
                                    showOverlayPreview()
                                }
                                
                                // Convert to RGB color space to ensure consistent component extraction
                                let nsColor = NSColor(newColor)
                                if let rgbColor = nsColor.usingColorSpace(.deviceRGB) {
                                    overlayColorRed = Double(rgbColor.redComponent)
                                    overlayColorGreen = Double(rgbColor.greenComponent)
                                    overlayColorBlue = Double(rgbColor.blueComponent)
                                    overlayColorAlpha = Double(rgbColor.alphaComponent)
                                    
                                    print("🎨 Color picker updated: R:\(overlayColorRed) G:\(overlayColorGreen) B:\(overlayColorBlue) A:\(overlayColorAlpha)")
                                    
                                    // Force save UserDefaults immediately to prevent loss on window close
                                    UserDefaults.standard.synchronize()
                                }
                            }
                        ), supportsOpacity: true)
                        .labelsHidden()
                        .help("Choose the background color for the recording overlay")
                        
                        // Opacity slider also triggers preview
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
                                .onChange(of: overlayOpacity) { _, _ in
                                    // Show preview when opacity changes
                                    if !isColorPickerOpen {
                                        print("🎨 Opacity changed - showing overlay preview")
                                        isColorPickerOpen = true
                                        showOverlayPreview()
                                    }
                                }
                        }
                        
                        // Manual preview buttons (backup controls)
                        HStack {
                            Button(isColorPickerOpen ? "Hide Preview" : "Show Preview") {
                                if isColorPickerOpen {
                                    hideOverlayPreview()
                                    isColorPickerOpen = false
                                } else {
                                    showOverlayPreview()
                                    isColorPickerOpen = true
                                }
                            }
                            .buttonStyle(.bordered)
                            .help(isColorPickerOpen ? "Hide the overlay preview" : "Show overlay window to preview color changes")
                            
                            if isColorPickerOpen {
                                Button("Close Preview") {
                                    hideOverlayPreview()
                                    isColorPickerOpen = false
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                                .help("Close the overlay preview")
                            }
                        }
                    }
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
                Toggle("Apply Word Replacements", isOn: $applyWordReplacements)
                    .help("Apply custom word replacements to fix common transcription errors")
                
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
    
    private var wordReplacementSection: some View {
        GroupBox("Word Replacements") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Apply Word Replacements", isOn: $applyWordReplacements)
                    .help("Apply custom word replacements to fix common transcription errors")
                
                if applyWordReplacements {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add New Replacement:")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Search for:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                TextField("e.g., nearchat", text: $newSearchTerm)
                                    .textFieldStyle(.roundedBorder)
                                    .help("The word or phrase to search for")
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Replace with:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                TextField("e.g., Ner Chat", text: $newReplacement)
                                    .textFieldStyle(.roundedBorder)
                                    .help("The replacement word or phrase")
                            }
                            
                            Button(action: addWordReplacement) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(newSearchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                     newReplacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help("Add word replacement")
                        }
                        
                        if !wordReplacements.isEmpty {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Current Replacements:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 4) {
                                        ForEach(Array(wordReplacements.keys).sorted(), id: \.self) { searchTerm in
                                            if let replacement = wordReplacements[searchTerm] {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text("\"\(searchTerm)\"")
                                                            .font(.caption)
                                                            .foregroundColor(.primary)
                                                        Text("→ \"\(replacement)\"")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    
                                                    Spacer()
                                                    
                                                    Button(action: {
                                                        removeWordReplacement(searchTerm: searchTerm)
                                                    }) {
                                                        Image(systemName: "minus.circle.fill")
                                                            .foregroundColor(.red)
                                                    }
                                                    .buttonStyle(.plain)
                                                    .help("Remove replacement")
                                                }
                                                .padding(.vertical, 2)
                                                .padding(.horizontal, 8)
                                                .background(.quaternary.opacity(0.5))
                                                .cornerRadius(6)
                                            }
                                        }
                                    }
                                }
                                .frame(maxHeight: 120)
                                
                                if wordReplacements.count > 0 {
                                    HStack {
                                        Text("\(wordReplacements.count) replacement\(wordReplacements.count == 1 ? "" : "s")")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                        
                                        Button("Clear All") {
                                            clearAllReplacements()
                                        }
                                        .font(.caption)
                                        .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("Word replacements are disabled. Enable to fix common transcription errors like 'near chat' → 'ner chat'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
    
    private func checkPermissions() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        permissionManager.checkPermissionStatus()
    }
    
    private func testWhisperConnection() {
        if whisperProvider == "azure" {
            // Basic validation
            guard !azureWhisperAPIKey.isEmpty else {
                showingAPIKeyAlert = true
                return
            }
            
            // TODO: Implement actual API test
            print("Testing Azure Whisper API connection with endpoint: \(azureWhisperEndpoint)")
            print("Using deployment: \(azureWhisperDeployment)")
        } else {
            // Basic validation
            guard !openAIWhisperAPIKey.isEmpty else {
                showingAPIKeyAlert = true
                return
            }
            
            // TODO: Implement actual API test
            print("Testing OpenAI Whisper API connection with base URL: \(openAIWhisperBaseURL)")
            print("Using model: \(openAIWhisperModel)")
        }
    }
    
    private func resetToDefaults() {
        // Whisper provider
        whisperProvider = "azure"
        
        // Azure Whisper settings
        azureWhisperAPIKey = ""
        azureWhisperEndpoint = ""
        azureWhisperDeployment = "whisper"
        azureWhisperAPIVersion = "2024-08-01-preview"
        
        // OpenAI Whisper settings
        openAIWhisperAPIKey = ""
        openAIWhisperModel = "whisper-1"
        openAIWhisperBaseURL = "https://api.openai.com/v1"
        
        // Azure OpenAI settings
        azureOpenAIAPIKey = ""
        azureOpenAIEndpoint = ""
        azureOpenAIDeployment = "gpt-4o-mini"
        azureOpenAIAPIVersion = "2024-04-01-preview"
        
        // Standard OpenAI settings
        openAIAPIKey = ""
        openAIModel = "gpt-4o-mini"
        openAIBaseURL = "https://api.openai.com/v1"
        openAIProvider = "azure"
        
        // General settings
        isEnabled = true
        useTestMode = false
        overlayOpacity = 0.85
        overlayPosition = "center"
        
        // Reset overlay color settings to defaults
        overlayColorRed = 0.2
        overlayColorGreen = 0.3
        overlayColorBlue = 0.5
        overlayColorAlpha = 0.85
        
        // Reset transcript cleaner options
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
        
        // Clear the input fields
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
        // Access the overlay window through AppDelegate
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showOverlayPreview()
        }
    }
    
    private func hideOverlayPreview() {
        // Access the overlay window through AppDelegate
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.hideOverlayPreview()
        }
    }
}

#Preview {
    SettingsView()
}
