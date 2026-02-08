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
    private let fnKeyCode: CGKeyCode = 0xB3
    private let ctrlKeyCode: CGKeyCode = 0x3B
    private let escapeKeyCode: CGKeyCode = 0x35

    /// Whether we're currently recording
    private var isRecording = false
    /// Whether we're currently processing (thinking)
    private var isProcessing = false
    private var accessibilityPermissionGranted = false
    private var permissionCheckTimer: Timer?

    /// Callbacks
    var onHotkeyPress: (() -> Void)?
    var onHotkeyRelease: (() -> Void)?
    var onCopyOnlyPress: (() -> Void)?
    var onNoGPTPastePress: (() -> Void)?
    var onEscapePress: (() -> Void)?

    @Published var isEnabled: Bool = true {
        didSet {
            if isEnabled {
                startListening()
            } else {
                stopListening()
            }
        }
    }
    
    func resetRecordingState() {
        isRecording = false
        isProcessing = false
    }

    func setProcessing() {
        isRecording = false
        isProcessing = true
    }

    func restart() {
        stopListening()
        resetRecordingState()
        checkAccessibilityPermissions()
        if isEnabled && AXIsProcessTrusted() {
            startListening()
        }
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
    
    private func checkAccessibilityPermissions() {
        accessibilityPermissionGranted = AXIsProcessTrusted()
        if !accessibilityPermissionGranted {
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            startPermissionCheckTimer()
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
                    self.permissionCheckTimer?.invalidate()
                    self.permissionCheckTimer = nil
                    if self.isEnabled { self.startListening() }
                }
            }
        }
    }
    
    private func startListening() {
        guard eventTap == nil else { return }
        if !AXIsProcessTrusted() {
            checkAccessibilityPermissions()
            return
        }
        
        // Create event tap for key down, key up, and modifier flag changes
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
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
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            } else {
                stopListening()
                startListening()
            }
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Ctrl during recording → no-GPT paste
        if type == .flagsChanged {
            if event.flags.contains(.maskControl) && isRecording {
                Task { @MainActor in
                    self.onNoGPTPastePress?()
                    self.isRecording = false
                    self.isProcessing = true
                }
                return nil
            }
        }

        // Fn key — toggle recording on/off
        if keyCode == fnKeyCode && type == .keyDown {
            Task { @MainActor in
                if self.isRecording {
                    self.onHotkeyRelease?()
                    self.isRecording = false
                    self.isProcessing = true
                } else {
                    self.onHotkeyPress?()
                    self.isRecording = true
                }
            }
        }
        // Ctrl during recording → no-GPT paste
        else if keyCode == ctrlKeyCode && isRecording {
            if type == .keyDown {
                Task { @MainActor in
                    self.onNoGPTPastePress?()
                    self.isRecording = false
                    self.isProcessing = true
                }
                return nil
            }
        }
        // Escape → cancel
        else if keyCode == escapeKeyCode && (isRecording || isProcessing) {
            if type == .keyDown {
                Task { @MainActor in
                    self.onEscapePress?()
                    self.isRecording = false
                    self.isProcessing = false
                }
                return nil
            }
        }

        return Unmanaged.passRetained(event)
    }
}
