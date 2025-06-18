//
//  AppDelegate.swift
//  JustWhisper
//
//  Created by Scott Soifer on 6/16/25.
//

import Cocoa
import SwiftUI
import AVFoundation

/// Main application delegate that coordinates the menu bar app, hotkey handling, and overlay management
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyController: HotkeyController?
    private var overlayWindow: OverlayWindow?
    private var settingsWindow: NSWindow?
    private var permissionManager = PermissionManager()
    
    /// Called when the application finishes launching
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 JustWhisper starting up...")
        
        // Hide dock icon to make it a true menu bar app
        NSApp.setActivationPolicy(.accessory)
        
        // Disable automatic state restoration to avoid saved state errors
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        
        setupMenuBar()
        setupHotkeyController()
        setupOverlay()
        
        // Request microphone permission immediately on startup
        requestMicrophonePermissionOnStartup()
        
        print("✅ JustWhisper startup complete")
    }
    
    /// Sets up the menu bar status item with icon and menu
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "JustWhisper")
            button.image?.isTemplate = true
        }
        
        let menu = NSMenu()
        
        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = UserDefaults.standard.bool(forKey: "JustWhisperEnabled") ? .on : .off
        menu.addItem(enabledItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let permissionsItem = NSMenuItem(title: "Check Permissions", action: #selector(checkPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit JustWhisper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    /// Initializes the global hotkey controller for Fn key capture
    private func setupHotkeyController() {
        hotkeyController = HotkeyController()
        hotkeyController?.onHotkeyPress = { [weak self] in
            self?.startRecording()
        }
        hotkeyController?.onHotkeyRelease = { [weak self] in
            self?.stopRecording()
        }
    }
    
    /// Creates the transparent overlay window
    private func setupOverlay() {
        overlayWindow = OverlayWindow(hotkeyController: hotkeyController)
    }
    
    /// Requests microphone permission on app startup
    private func requestMicrophonePermissionOnStartup() {
        print("🎤 Checking microphone permission...")
        
        // Wait a moment for the app to fully initialize, then check permission
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Check the current permission status
            self.permissionManager.checkPermissionStatus()
            
            // If permission is not granted, request it
            if !self.permissionManager.hasRecordPermission {
                print("📋 Microphone permission not granted - requesting permission")
                self.permissionManager.requestPermission()
            } else {
                print("✅ Microphone permission already granted")
            }
        }
    }
    
    /// Starts the recording process and shows the overlay
    private func startRecording() {
        guard UserDefaults.standard.bool(forKey: "JustWhisperEnabled") else { return }
        overlayWindow?.showRecording()
    }
    
    /// Stops recording and processes the audio
    private func stopRecording() {
        overlayWindow?.stopRecording()
    }
    
    /// Toggles the enabled state of JustWhisper
    @objc private func toggleEnabled() {
        let isEnabled = UserDefaults.standard.bool(forKey: "JustWhisperEnabled")
        UserDefaults.standard.set(!isEnabled, forKey: "JustWhisperEnabled")
        
        // Update menu item state
        if let menu = statusItem?.menu,
           let enabledItem = menu.item(at: 0) {
            enabledItem.state = !isEnabled ? .on : .off
        }
        
        // Update hotkey controller
        hotkeyController?.isEnabled = !isEnabled
    }
    
    /// Shows an alert to guide users to grant accessibility permissions
    private func showAccessibilityPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        JustWhisper needs accessibility permission to capture global hotkeys (Fn key).
        
        To grant permission:
        1. Go to System Preferences/Settings
        2. Click Security & Privacy → Privacy → Accessibility
        3. Click the lock and enter your password
        4. Check the box next to "JustWhisper"
        
        After granting permission, the global hotkey will work automatically.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "OK")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open System Preferences to Accessibility settings
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Checks and shows the status of required permissions
    @objc private func checkPermissions() {
        let hasAccessibility = AXIsProcessTrusted()
        let hasMicrophone = permissionManager.hasRecordPermission
        
        let alert = NSAlert()
        alert.messageText = "Permission Status"
        
        var status = "Current permissions:\n\n"
        status += hasAccessibility ? "✅ Accessibility: Granted\n" : "❌ Accessibility: Not Granted\n"
        status += hasMicrophone ? "✅ Microphone: Granted\n" : "❌ Microphone: Not Granted\n"
        
        if !hasAccessibility {
            status += "\nTo grant Accessibility permission:\n"
            status += "System Preferences → Security & Privacy → Privacy → Accessibility"
        }
        
        if !hasMicrophone {
            status += "\nTo grant Microphone permission:\n"
            status += "System Preferences → Security & Privacy → Privacy → Microphone"
        }
        
        alert.informativeText = status
        alert.alertStyle = hasAccessibility && hasMicrophone ? .informational : .warning
        
        if !hasAccessibility {
            alert.addButton(withTitle: "Open Accessibility Settings")
        }
        if !hasMicrophone {
            alert.addButton(withTitle: "Open Microphone Settings")
        }
        alert.addButton(withTitle: "OK")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            if !hasAccessibility {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            } else if !hasMicrophone {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                NSWorkspace.shared.open(url)
            }
        } else if response == .alertSecondButtonReturn && !hasAccessibility && !hasMicrophone {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Shows the preferences window
    @objc private func showPreferences() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            
            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "JustWhisper Preferences"
            settingsWindow?.styleMask = [.titled, .closable, .resizable]
            settingsWindow?.isReleasedWhenClosed = false
            settingsWindow?.setContentSize(NSSize(width: 480, height: 600))
            settingsWindow?.minSize = NSSize(width: 480, height: 600)
            settingsWindow?.maxSize = NSSize(width: 800, height: 1000)
            settingsWindow?.center()
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
