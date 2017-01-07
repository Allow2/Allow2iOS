Pod::Spec.new do |s|
    s.name        = "Allow2FrameworkiOS"
    s.version     = "0.1.0"
    s.summary     = "Allow2 makes it easy to add parental controls to your apps"
    s.homepage    = "https://github.com/Allow2/allow2iOS"
    s.license     = { :type => "To Be Announced" }
    s.authors     = { "CEO" => "ceo@allow2.com" }

    s.requires_arc = true
    s.osx.deployment_target = "10.9"
    s.ios.deployment_target = "9.0"
    s.watchos.deployment_target = "2.0"
    s.tvos.deployment_target = "9.0"
    s.source   = { :git => "https://github.com/Allow2/allow2iOS.git", :tag => s.version }
    s.source_files = "Allow2Framework/*.swift"
    s.pod_target_xcconfig =  {
        'SWIFT_VERSION' => '2.3',
    }
end
