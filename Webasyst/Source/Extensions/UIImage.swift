//
//  UIImage.swift
//  Webasyst
//
//  Created by Виктор Кобыхно on 26.05.2021.
//

import UIKit

extension UIImage {
    /// Drawing an image with a gradient
    /// - Parameters:
    ///   - gradientColors: Gradient colours
    ///   - size: Gradient size
    convenience init?(gradientColors: [UIColor], size: CGSize) {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        defer { UIGraphicsEndImageContext() }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = gradientColors.map { $0.cgColor } as CFArray
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: nil) else { return nil }
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0.0, y: 0.0),
                                   end: CGPoint(x: size.width, y: size.height),
                                   options: [])
        guard let image = UIGraphicsGetImageFromCurrentImageContext()?.cgImage else { return nil }
        self.init(cgImage: image)
    }
}
