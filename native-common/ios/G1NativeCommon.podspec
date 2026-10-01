# G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
# CocoaPods distribution of the same sources as Package.swift (used by candidate B).
Pod::Spec.new do |s|
  s.name         = "G1NativeCommon"
  s.version      = "1.0.0"
  s.summary      = "Synthetic benchmark common native module (non-production)."
  s.homepage     = "https://example.invalid/g1-native-common"
  s.license      = { :type => "Proprietary-Synthetic", :text => "NON-PRODUCTION / SYNTHETIC DATA ONLY" }
  s.author       = { "G1 lab" => "lab@example.invalid" }
  s.source       = { :path => "." }
  s.platforms    = { :ios => "16.0" }
  s.swift_version = "5.9"
  s.source_files = "Sources/G1NativeCommon/**/*.swift"
  s.resource_bundles = { "G1NativeCommonResources" => ["Sources/G1NativeCommon/Resources/g1/*"] }
  s.frameworks   = "ARKit", "AVFoundation", "CryptoKit", "Vision", "SceneKit", "Security", "UIKit"
end
