//
//  OverlayWindow.swift
//  JustWhisper
//
//  Created by Scott Soifer on 6/16/25.
//

import Cocoa
import SwiftUI
import AVFoundation

/// Custom NSWindow subclass that handles escape key to cancel operations
class OverlayNSWindow: NSWindow {
    weak var overlayWindow: OverlayWindow?
    
    override func keyDown(with event: NSEvent) {
        // Handle escape key
        if event.keyCode == 53 { // Escape key code
            overlayWindow?.handleEscapeKey()
            return // Don't pass the event up the chain
        } else {
            super.keyDown(with: event)
        }
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeKey() {
        super.becomeKey()
        // Make sure we can receive key events
        makeFirstResponder(self)
    }
}

/// Transparent overlay window that displays recording UI and waveform visualization
@MainActor
class OverlayWindow: NSObject {
    private var window: OverlayNSWindow?
    private var recorder = RecorderController()
    private var waveView: WaveView?
    private var thinkingView: ThinkingView?
    private var errorLabel: NSTextField?
    private var whisperClient = WhisperClient()
    private var levelUpdateTimer: Timer?
    private weak var hotkeyController: HotkeyController?
    private var overlayLayer: CALayer? // Reference to overlay layer for color updates
    
    // Tracking variable for hide task - used to cancel pending hide operations
    private var hideTask: Task<Void, Never>? = nil
    
    // Tracking variable for transcription task - used to cancel ongoing transcription
    private var transcriptionTask: Task<Void, Never>? = nil
    
    init(hotkeyController: HotkeyController? = nil) {
        super.init()
        self.hotkeyController = hotkeyController
        setupWindow()
        setupUserDefaultsObserver()
    }
    
    /// Creates and configures the transparent overlay window
    private func setupWindow() {
        // Create window with transparent background using custom window class
        window = OverlayNSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 180),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        guard let window = window else { return }
        
        // Set the overlay window reference for escape key handling
        window.overlayWindow = self
        
        // Configure window properties
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false // Enable mouse events so we can receive key events
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        
        // Position window in center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        // Apply user's overlay color and alpha from settings
        let overlayColorRed = UserDefaults.standard.double(forKey: "OverlayColorRed")
        let overlayColorGreen = UserDefaults.standard.double(forKey: "OverlayColorGreen") 
        let overlayColorBlue = UserDefaults.standard.double(forKey: "OverlayColorBlue")
        let overlayColorAlpha = UserDefaults.standard.double(forKey: "OverlayColorAlpha")
        
        // Use default values if not set (darker blue-gray for better visibility)
        let red = overlayColorRed > 0 ? overlayColorRed : 0.2
        let green = overlayColorGreen > 0 ? overlayColorGreen : 0.3
        let blue = overlayColorBlue > 0 ? overlayColorBlue : 0.5
        let alpha = overlayColorAlpha > 0 ? overlayColorAlpha : 0.85
        
        // Create visual effect view for glass effect
        let visualEffectView = NSVisualEffectView()
        // Temporarily disable material to force our custom color
        // visualEffectView.material = .hudWindow"Oh, baby, is this working? I think it is."
        // visualEffectView.blendingMode = .behindWindow
        visualEffectView.blendingMode = .withinWindow  // Change blending mode
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 20
        
        // Force background color directly on the visual effect view using settings
        visualEffectView.layer?.backgroundColor = NSColor(red: red, green: green, blue: blue, alpha: alpha).cgColor
        
        // Create overlay with user's color
        // overlayLayer = CALayer()
        // overlayLayer?.backgroundColor = NSColor(red: red, green: green, blue: blue, alpha: alpha).cgColor
        // overlayLayer?.cornerRadius = 20
        // visualEffectView.layer?.insertSublayer(overlayLayer!, at: 0)
        
        // Set the visual effect view's alpha
        visualEffectView.alphaValue = 1.0
        
        window.contentView = visualEffectView
        
        // Create container view for content
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(containerView)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])
        
        setupContentViews(in: containerView)
    }
    
    /// Sets up the content views (microphone icon, waveform, thinking dots, error label)
    private func setupContentViews(in container: NSView) {
        // Microphone icon
        let micIcon = NSImageView()
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 48, weight: .medium)
        micIcon.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")?.withSymbolConfiguration(symbolConfig)
        micIcon.contentTintColor = .white
        micIcon.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(micIcon)
        
        // Wave view for audio visualization
        waveView = WaveView()
        waveView?.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(waveView!)
        
        // Thinking view (initially hidden)
        thinkingView = ThinkingView()
        thinkingView?.translatesAutoresizingMaskIntoConstraints = false
        thinkingView?.isHidden = true
        container.addSubview(thinkingView!)
        
        // Error label (initially hidden)
        errorLabel = NSTextField()
        errorLabel?.translatesAutoresizingMaskIntoConstraints = false
        errorLabel?.isEditable = false
        errorLabel?.isBordered = false
        errorLabel?.backgroundColor = .clear
        errorLabel?.textColor = .red
        errorLabel?.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        errorLabel?.alignment = .center
        errorLabel?.lineBreakMode = .byWordWrapping
        errorLabel?.maximumNumberOfLines = 2
        errorLabel?.isHidden = true
        container.addSubview(errorLabel!)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Mic icon - top center
            micIcon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            micIcon.topAnchor.constraint(equalTo: container.topAnchor, constant: 32),
            micIcon.widthAnchor.constraint(equalToConstant: 64),
            micIcon.heightAnchor.constraint(equalToConstant: 64),
            
            // Wave view - center, below mic
            waveView!.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            waveView!.topAnchor.constraint(equalTo: micIcon.bottomAnchor, constant: 20),
            waveView!.widthAnchor.constraint(equalToConstant: 180),
            waveView!.heightAnchor.constraint(equalToConstant: 40),
            
            // Thinking view - same position as wave view
            thinkingView!.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            thinkingView!.centerYAnchor.constraint(equalTo: waveView!.centerYAnchor),
            thinkingView!.widthAnchor.constraint(equalToConstant: 120),
            thinkingView!.heightAnchor.constraint(equalToConstant: 40),
            
            // Error label - center, same position as wave/thinking views
            errorLabel!.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            errorLabel!.centerYAnchor.constraint(equalTo: waveView!.centerYAnchor),
            errorLabel!.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 12),
            errorLabel!.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12)
        ])
    }
    
    /// Shows the overlay and starts recording
    func showRecording() {
        guard let window = window else { return }
        
        // Cancel any pending hide operations
        cancelPendingHideTasks()
        
        // Fully reset the overlay before showing
        resetOverlay()
        
        // Update overlay color from current settings
        updateOverlayColor()
        
        print("🎬 OverlayWindow: Showing recording overlay")
        
        // Start recording
        do {
            try recorder.startRecording()
            waveView?.setRecording(true)
        } catch {
            print("❌ Failed to start recording: \(error)")
            showError("Failed to start recording")
            return
        }
        
        // Start level update timer to animate waveform
        levelUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let audioLevel = self.recorder.audioLevel
                self.waveView?.updateAudioLevel(audioLevel, isRecording: true)
            }
        }
        
        // Reposition window to ensure it's centered on the current screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        // Ensure window is ready to show
        if window.isVisible {
            window.orderOut(nil) // Hide first if already visible
        }
        
        // Animate window appearance
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
    }
    
    /// Stops recording and processes the audio
    func stopRecording() {
        guard window != nil else { return }
        
        // Stop level update timer
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil
        
        // Stop recording
        recorder.stopRecording()
        waveView?.setRecording(false)
        
        // Switch to thinking mode
        waveView?.isHidden = true
        thinkingView?.isHidden = false
        thinkingView?.startAnimating()
        errorLabel?.isHidden = true
        
        // Process the recorded audio - overlay will be hidden after processing completes
        transcriptionTask = Task {
            await processRecordedAudio()
        }
    }
    
    /// Processes recorded audio through Whisper API and handles text output
    private func processRecordedAudio() async {
        guard let recordingURL = recorder.getRecordingURL() else { 
            showError("No recording found")
            hideOverlayAfterDelay(seconds: 10) // Keep error visible for 10 seconds
            return 
        }
        
        do {
            // Check if task was cancelled before starting
            guard !Task.isCancelled else {
                print("🛑 OverlayWindow: Transcription task cancelled before starting")
                return
            }
            
            // Read audio file data
            let recordedAudioData = try Data(contentsOf: recordingURL)
            
            // Check if task was cancelled after reading file
            guard !Task.isCancelled else {
                print("🛑 OverlayWindow: Transcription task cancelled after reading audio file")
                return
            }
            
            // Send to Whisper API - overlay stays open during this time
            let transcript = try await whisperClient.transcribe(audioData: recordedAudioData)
            
            // Check if task was cancelled after transcription
            guard !Task.isCancelled else {
                print("🛑 OverlayWindow: Transcription task cancelled after API call")
                return
            }
            
            // Create transcript cleaner with user settings
            let cleaner = TranscriptCleaner(options: getCurrentTranscriptOptions())
            
            // Check if Azure OpenAI is enabled in settings
            let useAzureOpenAI = UserDefaults.standard.bool(forKey: "UseAzureOpenAI")
            
            var cleanedText: String
            if useAzureOpenAI {
                do {
                    // Use Azure OpenAI for advanced transcript enhancement
                    print("🤖 Enhancing transcript with Azure OpenAI...")
                    cleanedText = try await cleaner.enhanceWithAzureOpenAI(transcript)
                    print("✅ Successfully enhanced transcript with Azure OpenAI")
                } catch {
                    print("⚠️ Azure OpenAI enhancement failed: \(error.localizedDescription)")
                    print("🔄 Falling back to local processing")
                    cleanedText = cleaner.cleanTranscript(transcript)
                }
            } else {
                // Use local processing
                print("📝 Using local transcript cleaning (Azure OpenAI disabled)")
                cleanedText = cleaner.cleanTranscript(transcript)
            }
            
            // If transcript is empty, show an error
            if cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showError("No speech detected")
                hideOverlayAfterDelay(seconds: 10)
                return
            }
            
            // Final cancellation check before pasting
            guard !Task.isCancelled else {
                print("🛑 OverlayWindow: Transcription task cancelled before pasting")
                return
            }
            
            // Paste the result immediately if successful
            await pasteText(cleanedText)
            
            // Hide overlay after successful paste with short delay for feedback
            hideOverlayAfterDelay(seconds: 0.5)
            
            // Clear the transcription task reference
            self.transcriptionTask = nil
            
        } catch {
            print("Failed to process audio: \(error)")
            
            // Show more user-friendly error messages
            var errorMessage = "Transcription failed"
            
            if let nsError = error as NSError? {
                if nsError.domain == NSURLErrorDomain {
                    errorMessage = "Network error. Check your connection."
                } else if error.localizedDescription.contains("timeout") {
                    errorMessage = "Request timed out. Try again."
                } else {
                    // Truncate long error messages for display
                    let shortError = String(error.localizedDescription.prefix(50))
                    errorMessage = "Error: \(shortError)"
                }
            }
            
            // Display error in red for 10 seconds
            showError(errorMessage)
            hideOverlayAfterDelay(seconds: 10)
            
            // Clear the transcription task reference
            self.transcriptionTask = nil
        }
    }
    
    /// Retrieves the current transcript cleaner options from UserDefaults
    private func getCurrentTranscriptOptions() -> TranscriptCleaner.CleanerOptions {
        let defaults = UserDefaults.standard
        
        var options = TranscriptCleaner.CleanerOptions()
        options.removeFillerWords = defaults.bool(forKey: "RemoveFillerWords")
        options.processLineBreakCommands = defaults.bool(forKey: "ProcessLineBreakCommands")
        options.processPunctuationCommands = defaults.bool(forKey: "ProcessPunctuationCommands")
        options.processFormattingCommands = defaults.bool(forKey: "ProcessFormattingCommands")
        options.applySelfCorrection = defaults.bool(forKey: "ApplySelfCorrection")
        options.automaticCapitalization = defaults.bool(forKey: "AutomaticCapitalization")
        
        return options
    }
    
    /// Shows an error message in the overlay with red text and animation
    private func showError(_ message: String) {
        waveView?.isHidden = true
        thinkingView?.isHidden = true
        thinkingView?.stopAnimating()
        
        // Configure error display
        errorLabel?.stringValue = message
        errorLabel?.textColor = NSColor.red
        errorLabel?.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        errorLabel?.isHidden = false
        
        // Add attention-grabbing animation
        if let errorView = errorLabel {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                errorView.animator().alphaValue = 0.5
            } completionHandler: {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    errorView.animator().alphaValue = 1.0
                }
            }
        }
    }
    
    /// Hides the overlay with a smooth fade-out animation
    private func hideOverlay() {
        guard let window = window else { return }
        
        print("🔽 OverlayWindow: Hiding overlay window")
        
        // Stop timers
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil
        
        // Reset recording state in hotkey controller
        hotkeyController?.resetRecordingState()
        
        // Fade out with smooth animation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            
            // Also scale down slightly for a nicer effect
            if let visualEffect = window.contentView as? NSVisualEffectView {
                visualEffect.animator().alphaValue = 0
                
                // Add subtle transform for elegant exit
                let scaleTransform = CATransform3DMakeScale(0.95, 0.95, 1.0)
                
                // Use CATransaction for layer animation since layers don't have animator()
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.15)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
                visualEffect.layer?.transform = scaleTransform
                CATransaction.commit()
            } else {
                window.animator().alphaValue = 0
            }
        } completionHandler: {
            // Remove window from screen after animation completes
            window.orderOut(nil)
            
            // Reset overlay state after a short delay to ensure we're ready for next use
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.resetOverlay()
            }
        }
    }
    
    /// Cancels any pending hide tasks
    private func cancelPendingHideTasks() {
        hideTask?.cancel()
        hideTask = nil
    }
    
    /// Hides the overlay after a specified delay
    private func hideOverlayAfterDelay(seconds: Double) {
        // Cancel any existing hide tasks
        cancelPendingHideTasks()
        
        print("⏱️ OverlayWindow: Scheduled to hide after \(seconds)s delay")
        
        // Create a new hide task
        hideTask = Task {
            do {
                // Wait for the specified delay
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                
                // Check if task was cancelled
                if Task.isCancelled {
                    print("🛑 OverlayWindow: Hide task cancelled")
                    return
                }
                
                // Ensure we run UI updates on the main thread
                await MainActor.run {
                    if !Task.isCancelled {
                        print("⏱️ OverlayWindow: Hiding after \(seconds)s delay")
                        hideOverlay()
                    }
                }
            } catch {
                print("🛑 OverlayWindow: Hide task cancelled or failed: \(error)")
            }
        }
    }
    
    /// Pastes text into the currently focused application
    private func pasteText(_ text: String) async {
        guard !text.isEmpty else { return }
        
        // Store text in pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Small delay to ensure pasteboard is updated
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        
        let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
        cmdVDown?.flags = .maskCommand
        
        let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        cmdVUp?.flags = .maskCommand
        
        cmdVDown?.post(tap: .cghidEventTap)
        cmdVUp?.post(tap: .cghidEventTap)
    }
    
    /// Resets the overlay window to its initial state
    func resetOverlay() {
        // Reset UI elements
        waveView?.reset()
        waveView?.isHidden = false
        
        thinkingView?.stopAnimating()
        thinkingView?.isHidden = true
        
        errorLabel?.stringValue = ""
        errorLabel?.isHidden = true
        
        // Reset any timers
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil
        
        // Reset window state
        if let window = window {
            window.alphaValue = 1.0
            if let visualEffect = window.contentView as? NSVisualEffectView {
                visualEffect.alphaValue = 0.85
                
                // Reset transform
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                visualEffect.layer?.transform = CATransform3DIdentity
                CATransaction.commit()
            }
        }
        
        // Ensure Hotkey controller state is reset
        hotkeyController?.resetRecordingState()
        
        print("🔄 OverlayWindow: Reset complete - window ready for reuse")
    }
    
    /// Updates the overlay background color from user settings
    func updateOverlayColor() {
        guard let overlayLayer = overlayLayer else { return }
        
        // Get color values from settings
        let overlayColorRed = UserDefaults.standard.double(forKey: "OverlayColorRed")
        let overlayColorGreen = UserDefaults.standard.double(forKey: "OverlayColorGreen") 
        let overlayColorBlue = UserDefaults.standard.double(forKey: "OverlayColorBlue")
        let overlayColorAlpha = UserDefaults.standard.double(forKey: "OverlayColorAlpha")
        
        // Use default values if not set (darker blue-gray for better visibility)
        let red = overlayColorRed > 0 ? overlayColorRed : 0.2
        let green = overlayColorGreen > 0 ? overlayColorGreen : 0.3
        let blue = overlayColorBlue > 0 ? overlayColorBlue : 0.5
        let alpha = overlayColorAlpha > 0 ? overlayColorAlpha : 0.85
        
        // Update the layer's background color
        overlayLayer.backgroundColor = NSColor(red: red, green: green, blue: blue, alpha: alpha).cgColor
    }

    /// Sets up observer for UserDefaults changes to update overlay color live
    private func setupUserDefaultsObserver() {
        // Observe changes to overlay color settings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }
    
    /// Called when UserDefaults values change - updates overlay color if needed
    @objc private func userDefaultsDidChange() {
        // Update overlay color when settings change
        updateOverlayColor()
    }
    
    deinit {
        // Remove observer to prevent memory leaks
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Handles escape key press to cancel current operation and hide overlay
    func handleEscapeKey() {
        guard let window = window, window.isVisible else { return }
        
        print("🛑 OverlayWindow: Escape key pressed - canceling operation")
        
        // Cancel any pending hide tasks
        cancelPendingHideTasks()
        
        // Cancel any ongoing transcription
        if let transcriptionTask = transcriptionTask {
            print("🛑 OverlayWindow: Canceling transcription task")
            transcriptionTask.cancel()
            self.transcriptionTask = nil
        }
        
        // Check current state and provide appropriate feedback
        if recorder.isRecording {
            print("🛑 OverlayWindow: Canceling active recording")
            
            // Show brief cancellation feedback before hiding
            showError("Recording canceled")
            
            // Stop recording
            recorder.stopRecording()
            waveView?.setRecording(false)
            
            // Hide after brief feedback
            hideOverlayAfterDelay(seconds: 0.5)
        } else if thinkingView?.isHidden == false {
            print("🛑 OverlayWindow: Canceling transcription process")
            
            // Show cancellation feedback
            showError("Transcription canceled")
            
            // Hide after brief feedback  
            hideOverlayAfterDelay(seconds: 0.5)
        } else {
            print("🛑 OverlayWindow: Closing overlay")
            
            // Hide immediately if no active operation
            hideOverlay()
        }
        
        // Stop level update timer
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil
        
        // Stop thinking animation
        thinkingView?.stopAnimating()
        
        // Reset hotkey controller state
        hotkeyController?.resetRecordingState()
        
        print("🛑 OverlayWindow: Operation canceled via escape key")
    }
}
