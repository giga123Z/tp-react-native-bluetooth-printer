require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "RNBluetoothEscposPrinter"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.author       = 'tulparyazilim'
  s.homepage     = 'https://github.com/tulparyazilim/tp-react-native-bluetooth-printer'
  s.license      = package["license"]
  s.platform     = :ios, "13.0"
  s.source       = { :git => "https://github.com/giga123Z/tp-react-native-bluetooth-printer", :tag => "#{s.version}" }
  s.source_files = "ios/**/*.{h,c,m,swift}"
  s.requires_arc = true
  s.dependency "React"
  s.dependency 'ZXingObjC/PDF417'
  s.dependency 'ZXingObjC/OneD'

  s.pod_target_xcconfig = {
    # For use_frameworks! to have correct defines, please sync up with ZxingObjC dependencies above
    'GCC_PREPROCESSOR_DEFINITIONS' => 'ZXINGOBJC_USE_SUBSPECS ZXINGOBJC_PDF417 ZXINGOBJC_ONED',
  }
end
