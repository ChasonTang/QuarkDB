
Pod::Spec.new do |s|
  s.name             = 'QuarkORM'
  s.version          = '0.1.0'
  s.summary          = 'QuarkORM'

  s.description      = <<-DESC
                        QuarkORM is a lightweight ORM
                        for client. 
                       DESC

  s.homepage         = 'https://github.com/ChasonTang/QuarkDB'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'ChasonTang' => 'chasontang@warmbloom.com' }
  s.source           = { :git => 'https://github.com/ChasonTang/QuarkDB.git', :tag => s.version.to_s }

  s.ios.deployment_target = '8.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES'
  }

  s.source_files = 'QuarkORM/Classes/**/*{h,m}'
end
