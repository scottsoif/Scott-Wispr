//
//  HotkeyController.swift
//  JustWhisper
// 
//  Created by Scott Soifer on 6/16/25.
//

import Cocoa
import Carbon

/// Controller for capturing global Fn key events using CGEventTap
class HotkeyController: ObservableObject {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    // 0xB3 (179) is the correct Fn key code for modern macOS versions
    private let fnKeyCode: CGKeyCode = 0xB3 // Fn key code for macOS
    
    /// Whether we're currently recording (for toggle behavior)
    private var isRecording = false
    
    /// Whether accessibility permissions have been checked and granted
    private var accessibilityPermissionGranted = false
    
    /// Timer to periodically check for accessibility permissions
    private var permissionCheckTimer: Timer?
    
    /// Callback triggered when Fn key is pressed (toggle mode)
    var onHotkeyPress: (() -> Void)?
    
    /// Callback triggered when Fn key is released (hold mode - not used in toggle)
    var onHotkeyRelease: (() -> Void)?
    
    /// Whether the hotkey controller is enabled
    @Published var isEnabled: Bool = true {
        didSet {
            if isEnabled {
                startListening()
            } else {
                stopListening()
            }
        }
    }
    
    /// Resets the recording state (called when overlay is closed)
    func resetRecordingState() {
        isRecording = false
    }
    
    init() {
        // Initialize as enabled by default
        UserDefaults.standard.register(defaults: ["JustWhisperEnabled": true])
        isEnabled = UserDefaults.standard.bool(forKey: "JustWhisperEnabled")
        
        // Start checking for accessibility permissions
        checkAccessibilityPermissions()
        
        if isEnabled {
            startListening()
        }
    }
    
    deinit {
        stopListening()
        permissionCheckTimer?.invalidate()
    }
    
    /// Checks and requests accessibility permissions with better user guidance
    private func checkAccessibilityPermissions() {
        accessibilityPermissionGranted = AXIsProcessTrusted()
        
        if !accessibilityPermissionGranted {
            print("🚫 HotkeyController: Accessibility permissions not granted. Requesting permissions...")
            
            // Show the system permission dialog
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            // Start a timer to check when permissions are granted
            startPermissionCheckTimer()
        } else {
            print("✅ HotkeyController: Accessibility permissions already granted")
        }
    }
    
    /// Starts a timer to periodically check if accessibility permissions have been granted
    private func startPermissionCheckTimer() {
        permissionCheckTimer?.invalidate()
        
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let newStatus = AXIsProcessTrusted()
            if newStatus != self.accessibilityPermissionGranted {
                self.accessibilityPermissionGranted = newStatus
                
                if newStatus {
                    print("✅ HotkeyController: Accessibility permissions granted! Starting hotkey listener...")
                    self.permissionCheckTimer?.invalidate()
                    self.permissionCheckTimer = nil
                    
                    // Start listening now that we have permissions
                    if self.isEnabled {
                        self.startListening()
                    }
                }
            }
        }
    }
    
    /// Starts listening for global key events
    private func startListening() {
        guard eventTap == nil else { return }
        
        // Check accessibility permissions before proceeding
        if !AXIsProcessTrusted() {
            print("⏳ HotkeyController: Waiting for accessibility permissions...")
            checkAccessibilityPermissions()
            return
        }
        
        print("✅ HotkeyController: Starting global hotkey listener with accessibility permissions")
        
        // Create event tap for key down and key up events
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                
                let controller = Unmanaged<HotkeyController>.fromOpaque(refcon).takeUnretainedValue()
                return controller.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard let eventTap = eventTap else {
            print("❌ HotkeyController: Failed to create event tap")
            return
        }
        
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        print("🚀 HotkeyController: Global hotkey listener is now active")
    }
    
    /// Stops listening for global key events
    private func stopListening() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }
    
    /// Handles individual key events from the event tap
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle event tap being disabled by system (timeout or user input)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            print("🚨 HotkeyController: Event tap disabled (type: \(type)). Attempting to re-enable...")
            if let eventTap = eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                print("✅ HotkeyController: Event tap re-enabled")
            } else {
                // Try to restart listening if event tap is nil
                print("🔄 HotkeyController: Event tap is nil, restarting listener...")
                stopListening()
                startListening()
            }
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Handle Fn key specifically
        if keyCode == fnKeyCode {
            // Only handle key down events for toggle behavior
            switch type {
            case .keyDown:
                Task { @MainActor in
                    // Toggle between start and stop recording
                    if isRecording {
                        // Currently recording, so stop it
                        print("🛑 HotkeyController: Stopping recording...")
                        onHotkeyRelease?()
                        isRecording = false
                    } else {
                        // Not recording, so start it
                        print("🎬 HotkeyController: Starting recording...")
                        onHotkeyPress?()
                        isRecording = true
                    }
                }
            case .keyUp:
                print("🔼 HotkeyController: Fn key up (ignored in toggle mode)")
                // Ignore key up events in toggle mode
                break
            default:
                break
            }
        }

        // Pass the event through to allow normal system behavior
        return Unmanaged.passRetained(event)
    }
}
