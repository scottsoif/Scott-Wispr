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
    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 4
    private let maxBarHeight: CGFloat = 60
    private let minBarHeight: CGFloat = 4
    private var animatedLevel: Float = 0.0
    private var isRecording: Bool = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {

        super.init(coder: coder)
        setupLayers()
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
        
        // Smooth animation toward new audio level
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        
        animatedLevel = audioLevel
        updateBarHeights()
        updateBarColors()
        
        CATransaction.commit()
    }
    
    /// Calculates bar height based on audio level and bar position
    /// Creates a wave-like effect with center bars being tallest
    private func barHeight(for index: Int) -> CGFloat {
        let centerIndex = Float(numberOfBars - 1) / 2.0
        let distance = abs(Float(index) - centerIndex)
        let falloff = max(0, 1.0 - (distance / centerIndex) * 0.3)
        
        let level = animatedLevel * falloff
        return minBarHeight + (CGFloat(level) * (maxBarHeight - minBarHeight))
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
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        
        animatedLevel = 0.0
        updateBarHeights()
        updateBarColors()
        
        // Remove any existing animations
        for barLayer in barLayers {
            barLayer.removeAllAnimations()
        }
        
        CATransaction.commit()
    }
    
    /// Sets recording state and updates visual appearance
    func setRecording(_ recording: Bool) {
        isRecording = recording
        updateBarColors()
        
        if !recording {
            // Animate to idle state when recording stops
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            
            animatedLevel = 0.0
            updateBarHeights()
            
            CATransaction.commit()
        }
    }
}
