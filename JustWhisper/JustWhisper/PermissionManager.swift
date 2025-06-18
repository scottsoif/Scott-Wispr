//
//  PermissionManager.swift
//  JustWhisper
//
//  Created by AI Assistant on Date
//

import AVFoundation
import Cocoa

/**
 * Manages microphone permissions and handles permission-related UI
 */
class PermissionManager: ObservableObject {
    @Published var hasRecordPermission = false
    @Published var isCheckingPermission = false
    
    init() {
        checkPermissionStatus()
    }
    
    /**
     * Checks current microphone permission status
     * On macOS, we use AVCaptureDevice authorization status
     */
    func checkPermissionStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        DispatchQueue.main.async {
            self.hasRecordPermission = (status == .authorized)
        }
        
        // Log the current status for debugging
        // print("Microphone permission status: \(status.rawValue)")
    }
    
    /**
     * Requests microphone permission from the user
     * On denial, opens System Preferences to Security & Privacy → Microphone
     */
    func requestPermission() {
        isCheckingPermission = true
        
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.isCheckingPermission = false
                self?.hasRecordPermission = granted
                
                if !granted {
                    self?.openSystemPreferences()
                }
            }
        }
    }
    
    /**
     * Opens System Preferences to Security & Privacy → Microphone settings
     */
    private func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
}

