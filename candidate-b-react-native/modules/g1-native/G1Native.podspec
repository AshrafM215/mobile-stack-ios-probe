# G1 synthetic native bridge for candidate B - NON-PRODUCTION / SYNTHETIC DATA ONLY.
require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "G1Native"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://example.com/g1bench"
  s.license      = { :type => "UNLICENSED" }
  s.authors      = "G1 synthetic benchmark"
  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://example.invalid/g1-native.git", :tag => s.version.to_s }
  s.source_files = "ios/**/*.{h,m,mm}"
  s.frameworks   = "ARKit"

  install_modules_dependencies(s)
end
