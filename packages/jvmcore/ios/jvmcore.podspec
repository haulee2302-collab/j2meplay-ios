Pod::Spec.new do |s|
  s.name             = 'jvmcore'
  s.version          = '0.0.1'
  s.summary          = 'Lõi JVM bằng C cho J2ME Play'
  s.description      = 'Thông dịch bytecode Java + MIDP bằng C, gọi từ Dart qua FFI.'
  s.homepage         = 'https://github.com/haulee2302-collab/j2meplay-ios'
  s.license          = { :type => 'MIT' }
  s.author           = { 'J2ME Play' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{c,h}'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'NO',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) JVM_LIB=1',
    'GCC_C_LANGUAGE_STANDARD' => 'gnu11',
    'GCC_OPTIMIZATION_LEVEL' => '2',
    'OTHER_CFLAGS' => '-w',
  }
end
