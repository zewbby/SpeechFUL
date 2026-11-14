Pod::Spec.new do |s|
  s.name = 'hnuhole_native_media'
  s.version = '0.1.0'
  s.summary = 'Original photo selection and Photos import.'
  s.description = 'PHPicker file representations and add-only Photos imports without re-encoding.'
  s.homepage = 'https://www.speechful.dpdns.org/'
  s.license = { :type => 'Proprietary' }
  s.author = { 'SpeechFUL' => 'speechful@example.invalid' }
  s.source = { :path => '.' }
  s.source_files = 'hnuhole_native_media/Sources/hnuhole_native_media/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
end
