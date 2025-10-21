#
# Be sure to run `pod lib lint Webasyst.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
    s.name             = 'Webasyst'
    s.version          = '1.10.20'
    s.summary          = 'Webasyst ID auth & token refresh & API calls'
    s.description      = <<-DESC
    This library has been created to make working with Webasyst easier. The library allows you to authorise a user via a WAID server, get user settings and get tokens to work with them. The library has its own database to work with and requires no additional Core Data connection to the project.
    DESC
    s.homepage         = 'https://github.com/1312inc/Webasyst-X-iOS-Pod'
    s.license          = { :type => 'LGPL', :file => 'LICENSE' }
    s.authors          = { '1312 Inc.' => 'hello@1312.io' }
    s.source           = { :git => 'https://github.com/1312inc/Webasyst-X-iOS-Pod.git', :tag => "v1.10.20" }
    
    s.swift_version = '5.0'
    
    s.platform = :ios
    s.platform = :watchos
    
    s.ios.deployment_target = '13.0'
    s.watchos.deployment_target = '7.0'
    
    s.source_files = 'Webasyst/Source/**/*.swift'
    s.ios.source_files = 'Webasyst/iOS/**/*.swift'
    s.watchos.source_files = 'Webasyst/WatchOS/**/*.swift'
    
    s.resources = 'Webasyst/**/**/*.{strings,xcdatamodeld,xcassets}'
    
    s.frameworks = 'Foundation', 'CoreData'
    s.ios.frameworks = 'UIKit', 'WebKit'
    s.watchos.frameworks = 'WatchKit'
end
