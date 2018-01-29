Pod::Spec.new do |s|
    s.name        = "Allow2iOS"
    s.version     = "0.8.0"
    s.summary     = "Allow2 Parental Freedom Platform makes it easy to add parental controls to your apps"
    s.homepage    = "https://github.com/Allow2/allow2iOS"
    s.license     = { :type => 'Custom', :file => 'LICENSE' }
    s.authors     = { "CEO" => "ceo@allow2.com" }

    s.requires_arc = true
    s.ios.deployment_target = "10.0"
    s.source   = { :git => "https://github.com/Allow2/Allow2iOS.git", :tag => s.version }
    s.source_files = "Allow2Framework/*.swift"
    s.pod_target_xcconfig =  {
        'SWIFT_VERSION' => '4.0',
    }
end
