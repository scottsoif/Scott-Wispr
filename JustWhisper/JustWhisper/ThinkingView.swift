//
//  ThinkingView.swift
//  JustWhisper
//
//  Created by Scott Soifer on 6/16/25.
//

import Cocoa

/// Custom NSView that displays animated thinking dots while processing audio
class ThinkingView: NSView {
    private var dotLayers: [CALayer] = []
    private let numberOfDots = 3
    private let dotSize: CGFloat = 8
    private let dotSpacing: CGFloat = 12
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupDots()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDots()
    }
    
    /// Sets up the three thinking dots
    private func setupDots() {
        wantsLayer = true
        
        for _ in 0..<numberOfDots {
            let dotLayer = CALayer()
            dotLayer.backgroundColor = NSColor.white.cgColor
            dotLayer.cornerRadius = dotSize / 2
            dotLayer.frame = CGRect(
                x: 0, y: 0,
                width: dotSize, height: dotSize
            )
            
            layer?.addSublayer(dotLayer)
            dotLayers.append(dotLayer)
        }
    }
    
    override func layout() {
        super.layout()
        positionDots()
    }
    
    /// Positions the dots horizontally centered
    private func positionDots() {
        let totalWidth = CGFloat(numberOfDots) * dotSize + CGFloat(numberOfDots - 1) * dotSpacing
        let startX = (bounds.width - totalWidth) / 2
        let centerY = (bounds.height - dotSize) / 2
        
        for (index, dotLayer) in dotLayers.enumerated() {
            let x = startX + CGFloat(index) * (dotSize + dotSpacing)
            dotLayer.frame = CGRect(
                x: x, y: centerY,
                width: dotSize, height: dotSize
            )
        }
    }
    
    /// Starts the thinking animation with sequential dot scaling
    func startAnimating() {
        for (index, dotLayer) in dotLayers.enumerated() {
            let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
            scaleAnimation.fromValue = 1.0
            scaleAnimation.toValue = 1.4
            scaleAnimation.duration = 0.6
            scaleAnimation.autoreverses = true
            scaleAnimation.repeatCount = .infinity
            scaleAnimation.beginTime = CACurrentMediaTime() + Double(index) * 0.2
            scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            dotLayer.add(scaleAnimation, forKey: "thinking")
        }
    }
    
    /// Stops the thinking animation
    func stopAnimating() {
        for dotLayer in dotLayers {
            dotLayer.removeAllAnimations()
            dotLayer.transform = CATransform3DIdentity
        }
    }
}
