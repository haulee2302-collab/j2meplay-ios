Pod::Spec.new do |s|
  s.name             = 'jp_pip'
  s.version          = '0.0.1'
  s.summary          = 'Picture in Picture cho J2ME Play'
  s.description      = 'Đẩy khung hình RGBA vào AVSampleBufferDisplayLayer và bật hình trong hình.'
  s.homepage         = 'https://github.com/haulee2302-collab/j2meplay-ios'
  s.license          = { :type => 'MIT' }
  s.author           = { 'J2ME Play' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'
end
