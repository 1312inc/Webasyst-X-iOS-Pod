#
# Be sure to run `pod lib lint Webasyst.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'Webasyst'
  s.version          = '1.4.14'
  s.summary          = 'Webasyst ID auth & token refresh'
  s.description      = <<-DESC
                        This library has been created to make working with Webasyst easier. The library allows you to authorise a user via a WAID server, get user settings and get tokens to work with them. The library has its own database to work with and requires no additional Core Data connection to the project.
                        DESC
  s.homepage         = 'https://github.com/1312inc/Webasyst-X-iOS-Pod'
  s.license          = { :type => 'LGPL', :file => 'LICENSE' }
  s.authors          = { '1312 Inc.' => 'hello@1312.io' }
  s.source           = { :git => 'https://github.com/1312inc/Webasyst-X-iOS-Pod.git', :tag => "v1.4.14" }

  s.ios.deployment_target = '13.0'
  s.swift_version = '4.0'

  s.source_files = 'Source/**/*.swift'
  s.resources = "Source/**/*.xcdatamodeld"
  s.framework  = "Foundation"
  s.framework  = "CoreData"
  s.ios.framework  = "UIKit"
end
