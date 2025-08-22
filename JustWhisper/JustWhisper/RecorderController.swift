//
//  RecorderController.swift
//  JustWhisper
//
//  Created by Scott Soifer on 6/17/25.
//

import AVFoundation
import Foundation
import CoreAudio

/**
 * Represents an audio input device
 */
struct AudioDevice: Identifiable, Equatable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    
    static let `default` = AudioDevice(id: 0, name: "Default", uid: "default")
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }
}

/**
 * Protocol for audio recording functionality - enables testing with DummyRecorder
 */
protocol AudioRecorderProtocol: ObservableObject {
    var isRecording: Bool { get }
    var duration: TimeInterval { get }
    var audioLevel: Float { get }
    var hasRecording: Bool { get }
    var availableDevices: [AudioDevice] { get }
    var selectedDevice: AudioDevice { get set }
    
    func startRecording() throws
    func stopRecording()
    func getRecordingURL() -> URL?
    func refreshDevices()
    func setInputDevice(_ device: AudioDevice) throws
}

/**
 * Real audio recorder using AVAudioEngine for recording and level monitoring
 */
class RecorderController: NSObject, AudioRecorderProtocol {
    @Published var isRecording = false
    @Published var duration: TimeInterval = 0.0
    @Published var audioLevel: Float = 0.0
    @Published var hasRecording = false
    @Published var availableDevices: [AudioDevice] = []
    @Published var selectedDevice: AudioDevice = AudioDevice.default
    
    private var audioEngine: AVAudioEngine!
    private var inputNode: AVAudioInputNode!
    private var recordingFile: AVAudioFile?
    private var recordingURL: URL?
    private var timer: Timer?
    private var startTime: Date?
    private var audioUnit: AudioUnit?
    
    override init() {
        super.init()
        setupRecordingDirectory()
        loadSelectedDevice()
        refreshDevices()
        setupDeviceChangeListener()
        // Delay audio engine setup until permissions are granted
    }
    
    /**
     * Sets up AVAudioEngine for recording - only called after permissions are granted
     */
    private func setupAudioEngine() {
        guard audioEngine == nil else { return }
        
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
        
        // Configure input device if not default
        do {
            try setInputDeviceInternal(selectedDevice)
        } catch {
            print("Failed to set input device: \(error). Using default device.")
        }
        
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
        
        // Setup recording format - use hardware format to avoid sample rate mismatch
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, 
                                          sampleRate: hardwareFormat.sampleRate, 
                                          channels: hardwareFormat.channelCount, 
                                          interleaved: false) ?? hardwareFormat
        
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
        
        // Start engine with retry logic for device switching
        do {
            try audioEngine.start()
        } catch {
            print("⚠️ Failed to start audio engine, attempting device recovery...")
            
            // If starting fails (common with AirPods), try fallback to default device
            if selectedDevice != AudioDevice.default {
                print("🔄 Switching to default device and retrying...")
                
                // Clean up current engine
                audioEngine.stop()
                audioEngine = nil
                inputNode = nil
                
                // Switch to default device
                let previousDevice = selectedDevice
                selectedDevice = AudioDevice.default
                
                // Setup new engine with default device
                setupAudioEngine()
                
                // Recreate recording file with new format
                let newRecordingFormat = inputNode.inputFormat(forBus: 0)
                let newFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, 
                                            sampleRate: newRecordingFormat.sampleRate, 
                                            channels: newRecordingFormat.channelCount, 
                                            interleaved: false) ?? newRecordingFormat
                
                recordingFile = try AVAudioFile(forWriting: recordingURL!, settings: newFormat.settings)
                
                // Install tap with new format
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: newFormat) { [weak self] buffer, _ in
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
                
                // Try starting again with default device
                try audioEngine.start()
                print("✅ Successfully recovered using default device (was trying: \(previousDevice.name))")
            } else {
                // Already using default device, re-throw the error
                throw error
            }
        }
        
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
    
    // MARK: - Device Management
    
    /**
     * Refreshes the list of available audio input devices
     */
    func refreshDevices() {
        var devices: [AudioDevice] = [AudioDevice.default]
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        
        guard status == noErr else {
            print("Failed to get audio devices count: \(status)")
            self.availableDevices = devices
            return
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array<AudioDeviceID>(repeating: 0, count: deviceCount)
        
        let getDevicesStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        
        guard getDevicesStatus == noErr else {
            print("Failed to get audio devices: \(getDevicesStatus)")
            self.availableDevices = devices
            return
        }
        
        for deviceID in deviceIDs {
            // Check if device has input channels
            var inputChannelsAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var inputChannelsSize: UInt32 = 0
            let inputChannelsStatus = AudioObjectGetPropertyDataSize(deviceID, &inputChannelsAddress, 0, nil, &inputChannelsSize)
            
            guard inputChannelsStatus == noErr && inputChannelsSize > 0 else { continue }
            
            let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPointer.deallocate() }
            
            let getInputChannelsStatus = AudioObjectGetPropertyData(deviceID, &inputChannelsAddress, 0, nil, &inputChannelsSize, bufferListPointer)
            
            guard getInputChannelsStatus == noErr else { continue }
            
            let bufferList = bufferListPointer.pointee
            var hasInputChannels = false
            
            let bufferCount = Int(bufferList.mNumberBuffers)
            let buffers = UnsafeMutableAudioBufferListPointer(bufferListPointer)
            
            for i in 0..<bufferCount {
                if buffers[i].mNumberChannels > 0 {
                    hasInputChannels = true
                    break
                }
            }
            
            guard hasInputChannels else { continue }
            
            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var nameSize: UInt32 = 0
            let nameStatus = AudioObjectGetPropertyDataSize(deviceID, &nameAddress, 0, nil, &nameSize)
            
            guard nameStatus == noErr else { continue }
            
            var name: CFString?
            let getNameStatus = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name)
            
            guard getNameStatus == noErr, let deviceName = name as String? else { continue }
            
            // Get device UID
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var uidSize: UInt32 = 0
            let uidStatus = AudioObjectGetPropertyDataSize(deviceID, &uidAddress, 0, nil, &uidSize)
            
            guard uidStatus == noErr else { continue }
            
            var uid: CFString?
            let getUidStatus = AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uid)
            
            guard getUidStatus == noErr, let deviceUID = uid as String? else { continue }
            
            let device = AudioDevice(id: deviceID, name: deviceName, uid: deviceUID)
            devices.append(device)
        }
        
        DispatchQueue.main.async {
            self.availableDevices = devices
            
            // Update selected device if it was loaded from UserDefaults
            if self.selectedDevice.uid != "default" {
                if let savedDevice = devices.first(where: { $0.uid == self.selectedDevice.uid }) {
                    self.selectedDevice = savedDevice
                    print("✅ Restored saved device: \(savedDevice.name)")
                } else {
                    // Saved device not found (disconnected), reset to default
                    print("⚠️ Saved device '\(self.selectedDevice.uid)' not found, switching to default")
                    self.selectedDevice = AudioDevice.default
                    self.saveSelectedDevice()
                }
            }
        }
        
        print("Found \(devices.count) audio input devices")
        for device in devices {
            print("  - \(device.name) (\(device.uid))")
        }
    }
    
    /**
     * Sets the input device for recording
     */
    func setInputDevice(_ device: AudioDevice) throws {
        selectedDevice = device
        saveSelectedDevice()
        
        // Always restart audio engine when changing devices to avoid conflicts
        let wasRecording = isRecording
        if wasRecording {
            stopRecording()
        }
        
        // Clean up existing audio engine
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            audioEngine = nil
            inputNode = nil
            audioUnit = nil
        }
        
        // For non-default devices, set system preference if possible
        if device != AudioDevice.default {
            try setSystemInputDevice(device)
            
            // Give AirPods and other wireless devices time to become ready
            if device.name.contains("AirPods") || device.name.contains("Bluetooth") {
                print("⏳ Waiting for wireless device to become ready...")
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        
        // Setup with new device - setupAudioEngine will be called when needed
        print("✅ Successfully switched to device: \(device.name)")
    }
    
    /**
     * Attempts to set the system default input device (works better with AirPods)
     */
    private func setSystemInputDevice(_ device: AudioDevice) throws {
        guard device.id != 0 else { return }
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID = device.id
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
        
        if status != noErr {
            print("⚠️ Could not set system default input device: \(status) (this is often normal)")
            // Don't throw - many apps can't change system defaults, but the device switch may still work
        } else {
            print("✅ Set system default input device to: \(device.name)")
        }
    }
    
    /**
     * Internal method to set input device without triggering restart (simplified)
     */
    private func setInputDeviceInternal(_ device: AudioDevice) throws {
        // With the new approach, we rely on system default device setting
        // The audio engine will pick up the correct device when it starts
        print("✅ Audio engine will use device: \(device.name)")
    }
    
    /**
     * Validates that a device is currently available for use
     */
    private func isDeviceAvailable(_ device: AudioDevice) -> Bool {
        guard device.id != 0 else { return true } // Default device is always available
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var isAlive: UInt32 = 0
        var dataSize: UInt32 = UInt32(MemoryLayout<UInt32>.size)
        
        let status = AudioObjectGetPropertyData(device.id, &propertyAddress, 0, nil, &dataSize, &isAlive)
        
        return status == noErr && isAlive == 1
    }
    
    /**
     * Saves the selected device to UserDefaults
     */
    private func saveSelectedDevice() {
        UserDefaults.standard.set(selectedDevice.uid, forKey: "SelectedAudioDeviceUID")
    }
    
    /**
     * Loads the previously selected device from UserDefaults
     */
    private func loadSelectedDevice() {
        let savedUID = UserDefaults.standard.string(forKey: "SelectedAudioDeviceUID") ?? "default"
        selectedDevice = AudioDevice(id: 0, name: "Default", uid: savedUID)
        
        // We'll update this with the actual device info when refreshDevices() is called
    }
    
    // MARK: - Device Change Monitoring
    
    /**
     * Sets up listener for audio device changes (connect/disconnect)
     */
    private func setupDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let callback: AudioObjectPropertyListenerProc = { (objectID, numberAddresses, addresses, clientData) in
            guard let clientData = clientData else { return noErr }
            
            let recorderController = Unmanaged<RecorderController>.fromOpaque(clientData).takeUnretainedValue()
            DispatchQueue.main.async {
                recorderController.handleDeviceListChange()
            }
            
            return noErr
        }
        
        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            callback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        
        if status != noErr {
            print("⚠️ Failed to setup device change listener: \(status)")
        } else {
            print("✅ Setup device change listener")
        }
    }
    
    /**
     * Handles changes to the device list (devices added/removed)
     */
    private func handleDeviceListChange() {
        print("🔄 Audio device list changed, refreshing...")
        
        let previousDeviceCount = availableDevices.count
        let previousSelectedDevice = selectedDevice
        
        // Refresh the device list
        refreshDevices()
        
        // Check if our selected device is still available
        if !availableDevices.contains(where: { $0.uid == previousSelectedDevice.uid }) && previousSelectedDevice != AudioDevice.default {
            print("⚠️ Selected device '\(previousSelectedDevice.name)' disconnected, switching to default")
            
            // Device disconnected, switch to default
            selectedDevice = AudioDevice.default
            saveSelectedDevice()
            
            // If we were recording, restart with default device
            if isRecording {
                print("🔄 Restarting recording with default device...")
                do {
                    let wasRecording = isRecording
                    stopRecording()
                    
                    // Clean up and restart audio engine
                    if let engine = audioEngine {
                        if engine.isRunning {
                            engine.stop()
                        }
                        audioEngine = nil
                        inputNode = nil
                    }
                    
                    if wasRecording {
                        try startRecording()
                    }
                } catch {
                    print("❌ Failed to restart recording: \(error)")
                }
            }
        }
        
        // Log device changes
        if availableDevices.count != previousDeviceCount {
            print("📱 Device count changed: \(previousDeviceCount) → \(availableDevices.count)")
        }
    }
    
    deinit {
        // Clean up - just stop recording if needed, skip listener removal since it requires exact callback match
        print("🧹 RecorderController: Cleaning up")
        
        if isRecording {
            stopRecording()
        }
        
        // Note: AudioObjectRemovePropertyListener requires the exact same callback reference
        // which is complex to store. The system will clean up when the object is deallocated.
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
    @Published var availableDevices: [AudioDevice] = [AudioDevice.default, AudioDevice(id: 1, name: "Built-in Microphone", uid: "built-in"), AudioDevice(id: 2, name: "AirPods Pro", uid: "airpods")]
    @Published var selectedDevice: AudioDevice = AudioDevice.default
    
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
    
    func refreshDevices() {
        // Dummy implementation - devices are already set
    }
    
    func setInputDevice(_ device: AudioDevice) throws {
        selectedDevice = device
    }
}