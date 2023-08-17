//
//  ConfettiAnimationView.swift
//  Pods
//
//  Created by Леонид Лукашевич on 28.03.2023.
//

import UIKit
import QuartzCore

internal class ConfettiAnimationView: UIView {
    
    enum ConfettiType {
        case confetti
        case triangle
        case star
        case diamond
        case image(UIImage)
    }
    
    var emitter: CAEmitterLayer!
    var colors: [UIColor]!
    var intensity: Float!
    var type: ConfettiType!
    private var active: Bool!
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    func setup() {
        colors = [UIColor(red:0.95, green:0.40, blue:0.27, alpha:1.0),
                  UIColor(red:1.00, green:0.78, blue:0.36, alpha:1.0),
                  UIColor(red:0.48, green:0.78, blue:0.64, alpha:1.0),
                  UIColor(red:0.30, green:0.76, blue:0.85, alpha:1.0),
                  UIColor(red:0.58, green:0.39, blue:0.55, alpha:1.0)]
        intensity = 0.5
        type = .confetti
        active = false
    }
    
    func startConfetti() {
        emitter = CAEmitterLayer()
        
        emitter.emitterPosition = CGPoint(x: 0.0, y: 0.0)
        emitter.emitterShape = CAEmitterLayerEmitterShape.line // CAEmitterLayerEmitterShape.line // kCAEmitterLayerPoint
        emitter.emitterSize = CGSize(width: frame.size.width, height: 1)
        
        var cells = [CAEmitterCell]()
        for color in colors {
            cells.append(confettiWithColor(color: color))
        }
        
        emitter.emitterCells = cells
        layer.addSublayer(emitter)
        active = true
    }
    
    func stopConfetti() {
        emitter?.birthRate = 0
        active = false
    }
    
    func imageForType(type: ConfettiType) -> UIImage? {
        
        var fileName: String!
        
        switch type {
        case .confetti:
            fileName = "confetti"
        case .triangle:
            fileName = "triangle"
        case .star:
            fileName = "star"
        case .diamond:
            fileName = "diamond"
        case let .image(customImage):
            return customImage
        }
        
        let bundle = Bundle(for: WebasystApp.self)
        if let image = UIImage(named: fileName, in: bundle, with: nil) {
            return image
        } else {
            return nil
        }
    }
    
    func confettiWithColor(color: UIColor) -> CAEmitterCell {
        let confetti = CAEmitterCell()
        confetti.birthRate = 64.0 * intensity
        confetti.lifetime = 5.0 * intensity
        confetti.lifetimeRange = 0
        confetti.color = color.cgColor
        confetti.velocity = CGFloat(800.0 * intensity)
        confetti.velocityRange = CGFloat(200.0 * intensity)
        confetti.emissionLongitude = CGFloat.pi
        confetti.emissionRange = CGFloat.pi
        confetti.spin = CGFloat(4.0 * intensity)
        confetti.spinRange = CGFloat(6.0 * intensity)
        confetti.scaleRange = CGFloat(intensity)
        confetti.scaleSpeed = CGFloat(-0.1 * intensity)
        confetti.contents = imageForType(type: type)?.cgImage
        return confetti
    }
    
    func isActive() -> Bool {
        return self.active
    }
}

// MARK: - Request full screen animation
extension ConfettiAnimationView {
    
    class func requestFullScreenAnimation(for viewController: UIViewController) {
        
        let confettiView = ConfettiAnimationView(frame: CGRect(origin: .zero, size: UIScreen.main.bounds.size))
        confettiView.isUserInteractionEnabled = false
        confettiView.alpha = 0.0
        viewController.view.addSubview(confettiView)
        confettiView.startConfetti()
        UIView.animate(withDuration: 0.4) {
            confettiView.alpha = 1.0
        } completion: { _ in
            UIView.animate(withDuration: 0.4, delay: 1.5) {
                confettiView.alpha = 0.0
            } completion: { _ in
                confettiView.removeFromSuperview()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
            confettiView.stopConfetti()
        })
    }
}
