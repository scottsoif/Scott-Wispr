//
//  RecorderController.swift
//  JustWhisper
//
//  Created by Scott Soifer on 6/17/25.
//

import AVFoundation
import Foundation

/**
 * Protocol for audio recording functionality - enables testing with DummyRecorder
 */
protocol AudioRecorderProtocol: ObservableObject {
    var isRecording: Bool { get }
    var duration: TimeInterval { get }
    var audioLevel: Float { get }
    var hasRecording: Bool { get }
    
    func startRecording() throws
    func stopRecording()
    func getRecordingURL() -> URL?
}

/**
 * Real audio recorder using AVAudioEngine for recording and level monitoring
 */
class RecorderController: NSObject, AudioRecorderProtocol {
    @Published var isRecording = false
    @Published var duration: TimeInterval = 0.0
    @Published var audioLevel: Float = 0.0
    @Published var hasRecording = false
    
    private var audioEngine: AVAudioEngine!
    private var inputNode: AVAudioInputNode!
    private var recordingFile: AVAudioFile?
    private var recordingURL: URL?
    private var timer: Timer?
    private var startTime: Date?
    
    override init() {
        super.init()
        setupRecordingDirectory()
        // Delay audio engine setup until permissions are granted
    }
    
    /**
     * Sets up AVAudioEngine for recording - only called after permissions are granted
     */
    private func setupAudioEngine() {
        guard audioEngine == nil else { return }
        
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
        
        // No AVAudioSession configuration needed on macOS
        // Audio permissions are handled at the system level via entitlements
    }
    
    /**
     * Creates recording directory if it doesn't exist
     */
    private func setupRecordingDirectory() {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let justWhisperURL = appSupportURL.appendingPathComponent("JustWhisper")
        
        try? FileManager.default.createDirectory(at: justWhisperURL, withIntermediateDirectories: true)
    }
    
    /**
     * Starts audio recording and level monitoring
     */
    func startRecording() throws {
        guard !isRecording else { return }
        
        // Check microphone permission first
        let permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard permissionStatus == .authorized else {
            throw NSError(domain: "RecorderController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Microphone permission not granted"])
        }
        
        // Setup audio engine if not already done
        setupAudioEngine()
        
        // Create recording file URL
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let justWhisperURL = appSupportURL.appendingPathComponent("JustWhisper")
        recordingURL = justWhisperURL.appendingPathComponent("recording.caf")
        
        // Remove existing file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        // Setup recording format
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Create audio file
        recordingFile = try AVAudioFile(forWriting: recordingURL!, settings: recordingFormat.settings)
        
        // Install tap for recording and level monitoring
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, let file = self.recordingFile else { return }
            
            // Write to file
            do {
                try file.write(from: buffer)
            } catch {
                print("Failed to write audio buffer: \(error)")
            }
            
            // Calculate audio level
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0.0
            
            if let channelData = channelData {
                for i in 0..<frameLength {
                    let sample = channelData[i]
                    sum += sample * sample
                }
            }
            
            let rms = sqrt(sum / Float(frameLength))
            let avgPower = 20 * log10(rms)
            let normalizedLevel = max(0.0, min(1.0, (avgPower + 80.0) / 80.0))
            
            DispatchQueue.main.async {
                self.audioLevel = normalizedLevel
            }
        }
        
        // Start engine
        try audioEngine.start()
        
        // Start timer for duration
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.startTime else { return }
            self.duration = Date().timeIntervalSince(startTime)
        }
        
        isRecording = true
    }
    
    /**
     * Stops audio recording and saves the file
     */
    func stopRecording() {
        guard isRecording else { return }
        
        // Stop timer
        timer?.invalidate()
        timer = nil
        
        // Remove tap and stop engine
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        
        // Close recording file
        recordingFile = nil
        
        isRecording = false
        hasRecording = true
        audioLevel = 0.0
    }
    
    /**
     * Returns the URL of the last recording
     */
    func getRecordingURL() -> URL? {
        return hasRecording ? recordingURL : nil
    }
    
    deinit {
        if isRecording {
            stopRecording()
        }
    }
}

/**
 * Dummy recorder for testing - plays back a pre-recorded sample
 */
class DummyRecorder: AudioRecorderProtocol {
    @Published var isRecording = false
    @Published var duration: TimeInterval = 0.0
    @Published var audioLevel: Float = 0.0
    @Published var hasRecording = true // Always has a "recording"
    
    private var timer: Timer?
    private var startTime: Date?
    private var levelTimer: Timer?
    
    func startRecording() throws {
        guard !isRecording else { return }
        
        startTime = Date()
        
        // Simulate recording with timer
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.startTime else { return }
            self.duration = Date().timeIntervalSince(startTime)
        }
        
        // Simulate audio levels
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.audioLevel = Float.random(in: 0.1...0.8)
        }
        
        isRecording = true
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        timer?.invalidate()
        timer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        
        isRecording = false
        hasRecording = true
        audioLevel = 0.0
    }
    
    func getRecordingURL() -> URL? {
        // Return a dummy URL for testing
        return Bundle.main.url(forResource: "sample", withExtension: "caf")
    }
}