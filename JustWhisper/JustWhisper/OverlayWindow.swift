// NOTE: If you see TUINSRemoteViewController/viewServiceDidTerminateWithError errors in logs, this is a known macOS issue when using NSVisualEffectView in borderless NSWindow overlays. There is no direct way to override viewServiceDidTerminateWithError: without using NSViewController. If instability persists, consider using a custom NSView or fallback visual style.
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
    private var visualEffectView: NSVisualEffectView? // Reference to visual effect view for updates
    
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
        
        // Hide window initially - it should only be visible when recording
        window.orderOut(nil)
        
        // Position window based on user preference (but keep it hidden)
        positionWindow()
        
        // Create visual effect view for glass effect
        let effectView = NSVisualEffectView()
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 20
        
        visualEffectView = effectView
        window.contentView = effectView
        
        // Apply initial color and opacity
        updateOverlayColorAndOpacity()
        
        // Create container view for content
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(containerView)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: effectView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
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
        
        // Update overlay color and opacity from current settings
        updateOverlayColorAndOpacity()
        
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
        
        // Reposition window based on user preference on the current screen
        positionWindow()
        
        // Ensure window is ready to show
        if window.isVisible {
            print("🔄 Window was already visible, hiding first")
            window.orderOut(nil) // Hide first if already visible
        }
        
        // Set window properties to ensure visibility
        window.level = .floating
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        
        print("🎬 Window made key and ordered front, starting fade-in animation")
        
        // Animate window appearance
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        } completionHandler: {
            print("✅ Overlay fade-in animation completed")
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
            await processRecordedAudio(copyOnly: false)
        }
    }
    
    /// Stops recording and processes the audio in copy-only mode (no paste)
    func stopRecordingCopyOnly() {
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
        
        // Process the recorded audio in copy-only mode
        transcriptionTask = Task {
            await processRecordedAudio(copyOnly: true)
        }
    }
    
    /// Processes recorded audio through Whisper API and handles text output
    private func processRecordedAudio(copyOnly: Bool = false) async {
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
                    // Use OpenAI for advanced transcript enhancement
                    print("🤖 Enhancing transcript with OpenAI...")
                    cleanedText = try await cleaner.enhanceWithOpenAI(transcript)
                    print("✅ Successfully enhanced transcript with OpenAI")
                } catch {
                    print("⚠️ OpenAI enhancement failed: \(error.localizedDescription)")
                    print("🔄 Falling back to local processing")
                    cleanedText = cleaner.cleanTranscript(transcript)
                }
            } else {
                // Use local processing
                print("📝 Using local transcript cleaning (OpenAI disabled)")
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
            
            // Either paste or copy based on mode
            if copyOnly {
                await copyTextToClipboard(cleanedText)
                showMessage("Copied to clipboard", color: .systemGreen) // Show success message
                hideOverlayAfterDelay(seconds: 1.5) // Show confirmation longer
            } else {
                await pasteText(cleanedText)
                hideOverlayAfterDelay(seconds: 0.5) // Hide quickly after paste
            }
            
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
    
    /// Shows a message in the overlay with specified color and animation
    private func showMessage(_ message: String, color: NSColor = .red) {
        waveView?.isHidden = true
        thinkingView?.isHidden = true
        thinkingView?.stopAnimating()
        
        // Configure message display
        errorLabel?.stringValue = message
        errorLabel?.textColor = color
        errorLabel?.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        errorLabel?.isHidden = false
        
        // Add attention-grabbing animation
        if let messageView = errorLabel {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                messageView.animator().alphaValue = 0.5
            } completionHandler: {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    messageView.animator().alphaValue = 1.0
                }
            }
        }
    }
    
    /// Shows an error message in the overlay with red text and animation
    private func showError(_ message: String) {
        showMessage(message, color: .red)
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
    
    /// Copies text to clipboard only (no paste)
    private func copyTextToClipboard(_ text: String) async {
        guard !text.isEmpty else { return }
        
        // Store text in pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        print("📋 Copied text to clipboard: \(text)")
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
    
    /// Forces the overlay to hide immediately (useful for debugging stuck overlays)
    func forceHide() {
        guard let window = window else { return }
        
        print("🚨 OverlayWindow: Force hiding overlay (emergency reset)")
        
        // Cancel all tasks
        cancelPendingHideTasks()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        
        // Stop any timers
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil
        
        // Stop recording if active
        if recorder.isRecording {
            recorder.stopRecording()
        }
        
        // Hide window immediately
        window.orderOut(nil)
        
        // Reset state
        resetOverlay()
        
        // Reset hotkey controller
        hotkeyController?.resetRecordingState()
        
        print("✅ OverlayWindow: Force hide complete")
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
    
    /// Updates the overlay background color and opacity from user settings
    private func updateOverlayColorAndOpacity() {
        guard let visualEffectView = visualEffectView else { return }
        
        // Get color values from settings
        let overlayColorRed = UserDefaults.standard.double(forKey: "OverlayColorRed")
        let overlayColorGreen = UserDefaults.standard.double(forKey: "OverlayColorGreen") 
        let overlayColorBlue = UserDefaults.standard.double(forKey: "OverlayColorBlue")
        let overlayColorAlpha = UserDefaults.standard.double(forKey: "OverlayColorAlpha")
        let overlayOpacity = UserDefaults.standard.double(forKey: "OverlayOpacity")
        
        // Check if values are set (UserDefaults returns 0.0 for unset doubles)
        // We need to check if any values have been explicitly set
        let hasColorSettings = UserDefaults.standard.object(forKey: "OverlayColorRed") != nil
        
        // Use default values if not set (darker blue-gray for better visibility)
        let red = hasColorSettings ? overlayColorRed : 0.2
        let green = hasColorSettings ? overlayColorGreen : 0.3
        let blue = hasColorSettings ? overlayColorBlue : 0.5
        let alpha = hasColorSettings ? overlayColorAlpha : 0.85
        let opacity = overlayOpacity > 0 ? overlayOpacity : 0.85
        
        // Update the background color and opacity
        visualEffectView.layer?.backgroundColor = NSColor(red: red, green: green, blue: blue, alpha: alpha).cgColor
        visualEffectView.alphaValue = opacity
        
        print("🎨 Updated overlay color: R:\(red) G:\(green) B:\(blue) A:\(alpha) Opacity:\(opacity)")
    }
    
    /// Legacy method for backward compatibility - now calls the new method
    func updateOverlayColor() {
        updateOverlayColorAndOpacity()
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
    
    /// Called when UserDefaults values change - updates overlay appearance if needed
    @objc private func userDefaultsDidChange() {
        // Update overlay color when settings change
        updateOverlayColor()
        
        // Update position when position setting changes
        positionWindow()
    }
    
    /// Positions the overlay window based on user preference
    private func positionWindow() {
        guard let window = window, let screen = NSScreen.main else { 
            print("❌ OverlayWindow: Cannot position - window or screen is nil")
            return 
        }
        
        let overlayPosition = UserDefaults.standard.string(forKey: "OverlayPosition") ?? "center"
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        let margin: CGFloat = 50 // Distance from screen edges
        
        print("🖥️ Screen frame: \(screenFrame)")
        print("🪟 Window frame: \(windowFrame)")
        print("📍 Requested position: \(overlayPosition)")
        
        let x: CGFloat
        let y: CGFloat
        
        switch overlayPosition {
        case "top-left":
            x = screenFrame.minX + margin
            y = screenFrame.maxY - windowFrame.height - margin
        case "top-right":
            x = screenFrame.maxX - windowFrame.width - margin
            y = screenFrame.maxY - windowFrame.height - margin
        case "bottom-left":
            x = screenFrame.minX + margin
            y = screenFrame.minY + margin
        case "bottom-right":
            x = screenFrame.maxX - windowFrame.width - margin
            y = screenFrame.minY + margin
        case "center":
            x = screenFrame.midX - windowFrame.width / 2
            y = screenFrame.midY - windowFrame.height / 2
        default: // fallback to center
            print("⚠️ Unknown position '\(overlayPosition)', using center")
            x = screenFrame.midX - windowFrame.width / 2
            y = screenFrame.midY - windowFrame.height / 2
        }
        
        // Ensure the window stays within screen bounds
        let clampedX = max(screenFrame.minX, min(x, screenFrame.maxX - windowFrame.width))
        let clampedY = max(screenFrame.minY, min(y, screenFrame.maxY - windowFrame.height))
        
        print("🎯 Calculated position: (\(x), \(y)) -> Clamped: (\(clampedX), \(clampedY))")
        
        window.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
        
        // Set window level but don't make it visible - only showRecording() should do that
        window.level = .floating
        
        print("✅ Positioned overlay at \(overlayPosition): (\(clampedX), \(clampedY)) on screen \(screenFrame)")
    }
    
    deinit {
        // Remove observer to prevent memory leaks
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Shows the overlay for preview purposes (without recording functionality)
    func showPreview() {
        guard let window = window else { 
            print("❌ OverlayWindow: Cannot show preview - window is nil")
            return 
        }
        
        print("🎨 OverlayWindow: Showing overlay for color preview")
        
        // Cancel any pending hide operations
        cancelPendingHideTasks()
        
        // Reset the overlay to clean state
        resetOverlay()
        
        // Update overlay color and opacity from current settings
        updateOverlayColorAndOpacity()
        
        // Show a preview message instead of recording UI
        waveView?.isHidden = true
        thinkingView?.isHidden = true
        errorLabel?.stringValue = "Color Preview"
        errorLabel?.textColor = .white
        errorLabel?.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        errorLabel?.isHidden = false
        
        print("🎨 OverlayWindow: Set up preview UI elements")
        
        // Position window based on user preference
        positionWindow()
        
        // Ensure window is ready to show
        if window.isVisible {
            print("🔄 Preview window was already visible, hiding first")
            window.orderOut(nil) // Hide first if already visible
        }
        
        // Set window properties to ensure visibility
        window.level = .floating
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        
        print("🎨 Window made key and ordered front for preview, starting fade-in animation")
        
        // Animate window appearance
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        } completionHandler: {
            print("✅ Overlay preview shown successfully")
        }
    }
    
    /// Hides the overlay preview
    func hidePreview() {
        guard let window = window, window.isVisible else { return }
        
        print("🎨 OverlayWindow: Hiding overlay preview")
        
        // Fade out with smooth animation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0
        } completionHandler: {
            // Remove window from screen after animation completes
            window.orderOut(nil)
            
            // Reset overlay state
            self.resetOverlay()
            print("✅ Overlay preview hidden")
        }
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
            
            // Hide immediately if no active operation (including preview mode)
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
