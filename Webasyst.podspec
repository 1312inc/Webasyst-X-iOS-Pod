Pod::Spec.new do |spec|

    spec.name         = "Webasyst"
    spec.version      = "0.0.1"
    spec.summary      = "Cocoapods library to work with Webasyst"
    spec.author       = { "viktkobst" => "viktkobst@gmail.com" }
    spec.description  = <<-DESC
        This library is designed to work with Webasyst
        DESC

    spec.homepage     = "https://github.com/1312inc/Webasyst-X-iOS-Pod"
    spec.license      = { :type => "LGPL", :file => "LICENSE" }

    spec.ios.deployment_target = "13.0"
    spec.swift_version = "4.2"

    spec.source        = { :git => "https://github.com/1312inc/Webasyst-X-iOS-Pod.git", :tag => "#{spec.version}" }
    spec.source_files  = "Sources/**/*.{h,m,swift}"
    spec.framework        = "Foundation"
    spec.requires_arc     = true
    spec.default_subspec  = 'Core'
    
    spec.subspec 'Core' do |core|
        core.source_files           = 'Sources/Webasyst.swift'
        core.public_header_files    = 'Sources/*.h'
        core.dependency 'Webasyst/Networking'
    end
    
    spec.subspec 'Networking' do |networking|
        networking.source_files     = 'Sources/Networking.swift'
    end
    
end
