Pod::Spec.new do |s|
  s.name = 'hnuhole_auth_vault'
  s.version = '0.1.0'
  s.summary = 'Device bound durable authentication storage.'
  s.description = 'A serialized, non-synchronizing Keychain authentication record.'
  s.homepage = 'https://www.speechful.dpdns.org/'
  s.license = { :type => 'Proprietary' }
  s.author = { 'Hnuhole' => 'hnuhole@example.invalid' }
  s.source = { :path => '.' }
  s.source_files = 'hnuhole_auth_vault/Sources/hnuhole_auth_vault/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
end
