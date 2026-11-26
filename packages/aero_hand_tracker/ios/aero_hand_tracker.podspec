Pod::Spec.new do |s|
  s.name             = 'aero_hand_tracker'
  s.version          = '1.0.0'
  s.summary          = 'MediaPipe Hand Landmarker bridge for Aerograph.'
  s.description      = 'On-device fingertip tracking for Aerograph using MediaPipe Tasks Vision.'
  s.homepage         = 'https://github.com/AsRanjan007/aerograph'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ashutosh Ranjan' => 'https://github.com/AsRanjan007' }
  s.source           = { :path => '.' }
  s.source_files     = 'aero_hand_tracker/Sources/aero_hand_tracker/**/*.swift'
  s.resource_bundles = { 'aero_hand_tracker_privacy' => ['aero_hand_tracker/Sources/aero_hand_tracker/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.dependency 'MediaPipeTasksVision', '>= 0.10.14'
  s.platform = :ios, '15.0'
  s.static_framework = true
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
