//
//  UIImage.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 26.05.2021.
//

import Foundation

extension UIImage {
    /// Drawing an image with a gradient
    /// - Parameters:
    ///   - bounds: Gradient boundaries
    ///   - colors: Gradient colours
    /// - Returns: Gradient image 
    static func gradientImageWithBounds(bounds: CGRect, colors: [CGColor]) -> UIImage {
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = bounds
        gradientLayer.colors = colors
        UIGraphicsBeginImageContext(gradientLayer.bounds.size)
        gradientLayer.render(in: UIGraphicsGetCurrentContext()!)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image!
    }
}
