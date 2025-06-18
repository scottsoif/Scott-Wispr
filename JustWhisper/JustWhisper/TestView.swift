//
//  TestView.swift
//  JustWhisper
//
//  Created by Scott Soifer on 6/16/25.
//

import SwiftUI
import AVFoundation
import AppKit

/// Audio player manager for TestView
class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    private var audioPlayer: AVAudioPlayer?
    
    func playAudio(data: Data) throws {
        // Convert PCM data to WAV for playback
        let wavData = try convertPCMToWAVForPlayback(data)
        
        // Create a temporary file for playback
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorded_audio.wav")
        
        try wavData.write(to: tempURL)
        
        // Play the audio
        audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
        audioPlayer?.delegate = self
        audioPlayer?.play()
        isPlaying = true
        
        // Clean up the temp file after playback
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
    
    func togglePlayback() {
        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
        } else {
            audioPlayer?.play()
            isPlaying = true
        }
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }
    
    private func convertPCMToWAVForPlayback(_ pcmData: Data) throws -> Data {
        // Same as the existing convertPCMToWAV function
        let sampleRate: UInt32 = 16000
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample: UInt16 = bitsPerSample / 8
        let blockAlign: UInt16 = numChannels * bytesPerSample
        let byteRate: UInt32 = sampleRate * UInt32(blockAlign)
        
        var wavData = Data()
        
        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: UInt32(36 + pcmData.count).littleEndian) { Data($0) })
        wavData.append("WAVE".data(using: .ascii)!)
        
        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        
        // data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: UInt32(pcmData.count).littleEndian) { Data($0) })
        wavData.append(pcmData)
        
        return wavData
    }
}

/// Test view for Whisper client with live logging
struct TestView: View {
    @StateObject private var whisperClient = WhisperClient()
    @StateObject private var dummyClient = DummyWhisperClient()
    @StateObject private var audioPlayerManager = AudioPlayerManager()
    @State private var isRecording = false
    @State private var audioEngine = AVAudioEngine()
    @State private var audioData = Data()
    @State private var transcriptionResult = ""
    @State private var isTranscribing = false
    @State private var useRealAPI = false
    @State private var useAdvancedProcessing = true
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 16) {
            headerSection
            
            controlSection
            
            logSection
            
            resultSection
        }
        .padding(20)
        .frame(width: 600, height: 700)
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Whisper API Tester")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Text("Test audio transcription with live logging")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var controlSection: some View {
        GroupBox("Controls") {
            VStack(spacing: 12) {
                HStack {
                    Toggle("Use Real Azure API", isOn: $useRealAPI)
                        .help("Toggle between real Azure API and dummy responses")
                    
                    Spacer()
                    
                    Toggle("Advanced Processing", isOn: $useAdvancedProcessing)
                        .help("Enable post-processing with TranscriptCleaner (filler removal, corrections)")
                }
                
                HStack(spacing: 16) {
                    Button(action: toggleRecording) {
                        HStack {
                            Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                            Text(isRecording ? "Stop Recording" : "Start Recording")
                        }
                    }
                    .disabled(isTranscribing)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    
                    if !audioData.isEmpty {
                        Button(action: toggleAudioPlayback) {
                            HStack {
                                Image(systemName: audioPlayerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                Text(audioPlayerManager.isPlaying ? "Pause Audio" : "Play Audio")
                            }
                        }
                        .disabled(isRecording || isTranscribing)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    
                    Button("Test with Sample Audio") {
                        testWithSampleAudio()
                    }
                    .disabled(isRecording || isTranscribing)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var logSection: some View {
        GroupBox {
            VStack(spacing: 8) {
                HStack {
                    Text("Live Logs")
                        .font(.headline)
                    
                    Spacer()
                    
                    if !currentClient.logs.isEmpty {
                        Button("Copy All Logs") {
                            copyAllLogs()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Button("Clear Logs") {
                        clearLogs()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            if currentClient.logs.isEmpty {
                                Text("No logs yet - perform an action to see logs")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                            } else {
                                ForEach(currentClient.logs) { entry in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(entry.level.emoji)
                                                .font(.body)
                                            
                                            Text(entry.timestamp, style: .time)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            
                                            Spacer()
                                            
                                            Text(entry.level == .info ? "INFO" : entry.level == .warning ? "WARN" : "ERROR")
                                                .font(.system(.caption2, design: .monospaced))
                                                .fontWeight(.medium)
                                                .foregroundColor(colorForLevel(entry.level))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(colorForLevel(entry.level).opacity(0.1))
                                                .cornerRadius(4)
                                        }
                                        
                                        Text(entry.message)
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .lineLimit(nil)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .background(backgroundColorFor(level: entry.level))
                                    .cornerRadius(6)
                                    .textSelection(.enabled)
                                    .id(entry.id)
                                }
                            }
                        }
                        .padding(12)
                        .textSelection(.enabled)
                    }
                    .frame(height: 250)
                    .background(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                    .cornerRadius(8)
                    .onChange(of: currentClient.logs.count) { _ in
                        if let lastLog = currentClient.logs.last {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(lastLog.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var resultSection: some View {
        GroupBox("Transcription Result") {
            VStack(alignment: .leading, spacing: 8) {
                if isTranscribing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Transcribing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Raw Transcription:")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Text(transcriptionResult.isEmpty ? "No transcription yet" : transcriptionResult)
                            .font(.body)
                            .foregroundColor(transcriptionResult.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        
                        if useAdvancedProcessing && !transcriptionResult.isEmpty {
                            Text("Advanced Processing:")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.top, 4)
                            
                            Text(TranscriptCleaner().cleanTranscript(transcriptionResult))
                                .font(.body)
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .padding(8)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                }
                
                if !transcriptionResult.isEmpty && !useAdvancedProcessing {
                    Text("💡 Enable 'Advanced Processing' to see cleaned transcription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
            .frame(minHeight: 120, alignment: .topLeading)
        }
    }
    
    private var currentClient: WhisperClient {
        useRealAPI ? whisperClient : dummyClient
    }
    
    private func colorForLevel(_ level: LogEntry.LogLevel) -> Color {
        switch level {
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }
    
    private func backgroundColorFor(level: LogEntry.LogLevel) -> Color {
        switch level {
        case .error: return Color.red.opacity(0.05)
        case .warning: return Color.orange.opacity(0.05)
        case .info: return Color.clear
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        checkMicrophonePermission()
    }
    
    private func actuallyStartRecording() {
        do {
            // Setup audio engine for macOS
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            audioData = Data()
            var audioLevelCounter = 0
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                let data = Data(bytes: buffer.floatChannelData![0], count: Int(buffer.frameLength) * 4)
                
                // Calculate audio level for debugging
                let samples = buffer.floatChannelData![0]
                var sum: Float = 0
                for i in 0..<Int(buffer.frameLength) {
                    sum += abs(samples[i])
                }
                let average = sum / Float(buffer.frameLength)
                
                DispatchQueue.main.async {
                    self.audioData.append(data)
                    
                    // Log audio level every 50 buffers (~1 second)
                    audioLevelCounter += 1
                    if audioLevelCounter % 50 == 0 {
                        let levelPercent = min(100, average * 1000)
                        // Audio level logging removed to avoid compilation issues
                        print("Audio level: \(String(format: "%.1f", levelPercent))%, data size: \(self.audioData.count) bytes")
                    }
                }
            }
            
            try audioEngine.start()
            isRecording = true
            print("Recording started successfully")
            
        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
        
        // Start transcription
        transcribeAudio()
    }
    
    private func testWithSampleAudio() {
        // Generate some sample audio data (sine wave)
        let sampleRate: Float = 44100
        let duration: Float = 2.0
        let frequency: Float = 440 // A4 note
        
        let frameCount = Int(sampleRate * duration)
        var audioData = Data()
        
        for i in 0..<frameCount {
            let sample = sin(2.0 * Float.pi * frequency * Float(i) / sampleRate)
            let bytes = withUnsafeBytes(of: sample) { Data($0) }
            audioData.append(bytes)
        }
        
        self.audioData = audioData
        transcribeAudio()
    }
    
    private func transcribeAudio() {
        guard !audioData.isEmpty else { return }
        
        isTranscribing = true
        transcriptionResult = ""
        
        Task {
            do {
                let result = try await currentClient.transcribe(audioData: audioData)
                
                await MainActor.run {
                    transcriptionResult = result
                    isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Transcription failed: \(error.localizedDescription)"
                    showingError = true
                    isTranscribing = false
                }
            }
        }
    }
    
    private func copyAllLogs() {
        let logText = currentClient.logs.map { entry in
            let levelText: String
            switch entry.level {
            case .info: levelText = "INFO"
            case .warning: levelText = "WARN"  
            case .error: levelText = "ERROR"
            }
            let timeText = DateFormatter.localizedString(from: entry.timestamp, dateStyle: .none, timeStyle: .medium)
            return "[\(timeText)] \(levelText): \(entry.message)"
        }.joined(separator: "\n")
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logText, forType: .string)
    }
    
    private func playRecordedAudio() {
        guard !audioData.isEmpty else { return }
        
        do {
            try audioPlayerManager.playAudio(data: audioData)
        } catch {
            errorMessage = "Failed to play audio: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func toggleAudioPlayback() {
        if audioPlayerManager.isPlaying {
            audioPlayerManager.togglePlayback()
        } else {
            playRecordedAudio()
        }
    }
    
    private func convertPCMToWAVForPlayback(_ pcmData: Data) throws -> Data {
        let sampleRate: UInt32 = 44100
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 32  // 32-bit float for better playback quality
        let bytesPerSample = bitsPerSample / 8
        let frameSize = channels * bytesPerSample
        
        var wavData = Data()
        
        // WAV header
        wavData.append("RIFF".data(using: .ascii)!)
        
        let fileSize = UInt32(36 + pcmData.count)
        withUnsafeBytes(of: fileSize.littleEndian) { wavData.append(Data($0)) }
        
        wavData.append("WAVE".data(using: .ascii)!)
        wavData.append("fmt ".data(using: .ascii)!)
        
        let subchunk1Size: UInt32 = 16
        withUnsafeBytes(of: subchunk1Size.littleEndian) { wavData.append(Data($0)) }
        
        let audioFormat: UInt16 = 3 // IEEE float format for playback
        withUnsafeBytes(of: audioFormat.littleEndian) { wavData.append(Data($0)) }
        
        withUnsafeBytes(of: channels.littleEndian) { wavData.append(Data($0)) }
        withUnsafeBytes(of: sampleRate.littleEndian) { wavData.append(Data($0)) }
        
        let byteRate = sampleRate * UInt32(frameSize)
        withUnsafeBytes(of: byteRate.littleEndian) { wavData.append(Data($0)) }
        
        withUnsafeBytes(of: frameSize.littleEndian) { wavData.append(Data($0)) }
        withUnsafeBytes(of: bitsPerSample.littleEndian) { wavData.append(Data($0)) }
        
        wavData.append("data".data(using: .ascii)!)
        
        let dataSize = UInt32(pcmData.count)
        withUnsafeBytes(of: dataSize.littleEndian) { wavData.append(Data($0)) }
        
        wavData.append(pcmData)
        
        return wavData
    }

    private func clearLogs() {
        whisperClient.clearLogs()
        dummyClient.clearLogs()
        transcriptionResult = ""
    }
    
    private func checkMicrophonePermission() {
        print("🔄 Checking microphone permission for audio recording...")
        
        // For macOS, we need to try to access the microphone directly
        // This will automatically trigger the permission dialog if needed
        do {
            // Create a temporary audio engine to test access
            let testEngine = AVAudioEngine()
            let inputNode = testEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            // Try to install a tap - this will fail if no permission
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { _, _ in
                // Empty tap - we just want to test permission
            }
            
            // Try to start the engine - this triggers permission request
            try testEngine.start()
            
            // If we get here, permission was granted
            print("✅ Microphone permission granted")
            testEngine.stop()
            inputNode.removeTap(onBus: 0)
            
            // Now start actual recording
            actuallyStartRecording()
            
        } catch {
            print("❌ Microphone permission denied or unavailable: \(error)")
            errorMessage = "Microphone access is required for audio recording. Please go to System Preferences > Privacy & Security > Microphone and enable access for JustWhisper."
            showingError = true
        }
    }
}

#Preview {
    TestView()
}
