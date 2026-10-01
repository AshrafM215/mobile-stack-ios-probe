# Candidate B adapter (TurboModule NativeG1) to the G1 common native module - NON-PRODUCTION / SYNTHETIC DATA ONLY.
require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "G1Native"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://example.invalid/g1bench"
  s.license      = { :type => "UNLICENSED" }
  s.authors      = "G1 synthetic benchmark"
  s.platforms    = { :ios => "16.0" }
  s.source       = { :git => "https://example.invalid/g1-native.git", :tag => s.version.to_s }
  s.source_files = "ios/**/*.{h,m,mm}"
  s.dependency "G1NativeCommon"

  install_modules_dependencies(s)
end
