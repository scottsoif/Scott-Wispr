//
//  WaveView.swift
//  JustWhisper
//
//  Created by Scott Soifer on 6/16/25.
//

import Cocoa

/// Custom NSView that displays animated waveform bars with real audio level response
class WaveView: NSView {
    private var barLayers: [CALayer] = []
    private let numberOfBars = 12
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 5
    private let maxBarHeight: CGFloat = 60
    private let minBarHeight: CGFloat = 2
    private var animatedLevel: Float = 0.0
    private var isRecording: Bool = false
    
    // Sine wave properties
    private var wavePhase: Float = 0.0
    private var waveAmplitude: Float = 1.0
    private var waveFrequency: Float = 1.0
    private var lastUpdateTime: CFTimeInterval = 0
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
        startWaveAnimation()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
        startWaveAnimation()
    }
    
    /// Sets up individual bar layers
    private func setupLayers() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        
        // Create individual bar layers
        for _ in 0..<numberOfBars {
            let barLayer = CALayer()
            barLayer.backgroundColor = NSColor.systemGray.cgColor
            barLayer.cornerRadius = barWidth / 2
            barLayers.append(barLayer)
            layer?.addSublayer(barLayer)
        }
        
        updateLayerFrames()
    }
    
    override func layout() {
        super.layout()
        updateLayerFrames()
    }
    
    /// Updates layer frames when view bounds change
    private func updateLayerFrames() {
        let totalWidth = CGFloat(numberOfBars) * barWidth + CGFloat(numberOfBars - 1) * barSpacing
        let startX = (bounds.width - totalWidth) / 2
        
        // Position each bar individually
        for (index, barLayer) in barLayers.enumerated() {
            let x = startX + CGFloat(index) * (barWidth + barSpacing)
            barLayer.frame = CGRect(
                x: x,
                y: (bounds.height - minBarHeight) / 2,
                width: barWidth,
                height: minBarHeight
            )
        }
    }
    
    /// Updates the waveform with real-time audio level
    /// - Parameter audioLevel: RMS amplitude value (0.0 to 1.0)
    /// - Parameter recording: Whether currently recording
    func updateAudioLevel(_ audioLevel: Float, isRecording recording: Bool) {
        self.isRecording = recording
        
        // Update wave phase for continuous animation
        let currentTime = CACurrentMediaTime()
        if lastUpdateTime > 0 {
            let deltaTime = Float(currentTime - lastUpdateTime)
            wavePhase += deltaTime * 3.0 // Adjust speed as needed
            
            // Keep phase in reasonable range
            if wavePhase > 2.0 * Float.pi {
                wavePhase -= 2.0 * Float.pi
            }
        }
        lastUpdateTime = currentTime
        
        // Smooth animation toward new audio level
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.05) // Shorter duration for more responsive feel
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        
        animatedLevel = audioLevel
        
        // Adjust wave properties based on audio level
        waveAmplitude = 0.6 + audioLevel * 0.4 // More amplitude with higher audio levels
        waveFrequency = 1.0 + audioLevel * 2.0 // Faster waves with higher audio levels
        
        updateBarHeights()
        updateBarColors()
        
        CATransaction.commit()
    }
    
    /// Calculates bar height based on audio level and sine wave pattern
    /// Creates a dynamic sine wave effect across all bars
    private func barHeight(for index: Int) -> CGFloat {
        // Calculate sine wave value for this bar position
        let normalizedIndex = Float(index) / Float(numberOfBars - 1) // 0.0 to 1.0
        let wavePosition = normalizedIndex * waveFrequency * 2.0 * Float.pi + wavePhase
        let sineValue = sin(wavePosition) // -1.0 to 1.0
        
        // Convert sine value to positive range (0.0 to 1.0) and apply amplitude
        let normalizedSine = (sineValue + 1.0) / 2.0 * waveAmplitude
        
        // Combine audio level with sine wave pattern
        let baseLevel = isRecording ? animatedLevel : 0.1 // Minimum activity when not recording
        let combinedLevel = baseLevel * (0.3 + normalizedSine * 0.7) // Mix base level with sine wave
        
        // Apply some randomness for more organic feel
        let randomFactor = Float.random(in: 0.9...1.1)
        let finalLevel = combinedLevel * randomFactor
        
        return minBarHeight + (CGFloat(finalLevel) * (maxBarHeight - minBarHeight))
    }
    
    /// Updates all bar heights based on current audio level
    private func updateBarHeights() {
        for (index, barLayer) in barLayers.enumerated() {
            let targetHeight = barHeight(for: index)
            
            barLayer.frame.size.height = targetHeight
            barLayer.frame.origin.y = (bounds.height - targetHeight) / 2
        }
    }
    
    /// Updates bar colors based on recording state
    private func updateBarColors() {
        let activeColor = NSColor.systemBlue.cgColor
        let inactiveColor = NSColor.systemGray.withAlphaComponent(0.5).cgColor
        
        for barLayer in barLayers {
            barLayer.backgroundColor = isRecording ? activeColor : inactiveColor
        }
    }
    
    /// Resets the waveform to idle state
    func reset() {
        isRecording = false
        
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.5)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        
        // Reset to idle animation state
        animatedLevel = 0.05
        waveAmplitude = 0.3
        waveFrequency = 1.0
        
        updateBarHeights()
        updateBarColors()
        
        // Remove any existing animations
        for barLayer in barLayers {
            barLayer.removeAllAnimations()
        }
        
        CATransaction.commit()
        
        // Reset timing
        lastUpdateTime = CACurrentMediaTime()
    }
    
    /// Sets recording state and updates visual appearance
    func setRecording(_ recording: Bool) {
        isRecording = recording
        updateBarColors()
        
        if !recording {
            // Animate to idle state when recording stops
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.5)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            
            // Transition to idle animation
            animatedLevel = 0.05
            waveAmplitude = 0.3
            waveFrequency = 1.0
            updateBarHeights()
            
            CATransaction.commit()
            
            // Reset timing for smooth transition to idle animation
            lastUpdateTime = CACurrentMediaTime()
        }
    }
    
    /// Starts the continuous wave animation
    private func startWaveAnimation() {
        lastUpdateTime = CACurrentMediaTime()
        wavePhase = Float.random(in: 0...(2.0 * Float.pi)) // Random starting phase
        
        // Create a timer for continuous animation when idle
        Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Only animate when not actively receiving audio updates
            if !self.isRecording {
                self.updateIdleAnimation()
            }
        }
    }
    
    /// Updates the animation during idle state
    private func updateIdleAnimation() {
        let currentTime = CACurrentMediaTime()
        let deltaTime = Float(currentTime - lastUpdateTime)
        wavePhase += deltaTime * 1.5 // Slower animation when idle
        
        // Keep phase in reasonable range
        if wavePhase > 2.0 * Float.pi {
            wavePhase -= 2.0 * Float.pi
        }
        
        lastUpdateTime = currentTime
        
        // Set idle properties
        waveAmplitude = 0.3
        waveFrequency = 1.0
        animatedLevel = 0.05 // Very low level for subtle movement
        
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        
        updateBarHeights()
        
        CATransaction.commit()
    }
    
    /// Customizes the sine wave parameters for different visual effects
    /// - Parameters:
    ///   - amplitude: Wave amplitude (0.0 to 1.0) - how dramatic the wave effect is
    ///   - frequency: Wave frequency (0.5 to 3.0) - how many wave cycles across the bars
    ///   - speed: Animation speed multiplier (0.5 to 3.0) - how fast the wave moves
    func configureWave(amplitude: Float = 1.0, frequency: Float = 1.0, speed: Float = 1.0) {
        waveAmplitude = max(0.0, min(1.0, amplitude))
        waveFrequency = max(0.5, min(3.0, frequency))
        // Speed will be applied in the animation methods
    }
    
    /// Provides some preset wave configurations
    enum WavePreset {
        case gentle     // Subtle, slow waves
        case energetic  // Fast, dramatic waves
        case pulse      // Rhythmic pulsing effect
        case ocean      // Ocean-like flowing waves
    }
    
    /// Applies a preset wave configuration
    func applyWavePreset(_ preset: WavePreset) {
        switch preset {
        case .gentle:
            configureWave(amplitude: 0.4, frequency: 0.8, speed: 0.7)
        case .energetic:
            configureWave(amplitude: 1.0, frequency: 2.0, speed: 2.0)
        case .pulse:
            configureWave(amplitude: 0.8, frequency: 0.5, speed: 1.5)
        case .ocean:
            configureWave(amplitude: 0.6, frequency: 1.2, speed: 0.8)
        }
    }
}
