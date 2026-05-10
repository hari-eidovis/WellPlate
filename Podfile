platform :ios, '18.6'

target 'WellPlate' do
  use_frameworks!
  pod 'lottie-ios'
end

post_install do |installer|
  # Xcode 16 enables User Script Sandboxing by default, which blocks the
  # CocoaPods "Embed Pods Frameworks" rsync. Disable it on Pods targets and
  # on the host WellPlate target so the script phase can run.
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    end
  end

  installer.aggregate_targets.each do |aggregate_target|
    aggregate_target.user_project.native_targets.each do |target|
      next unless target.name == 'WellPlate'
      target.build_configurations.each do |config|
        config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      end
    end
    aggregate_target.user_project.save
  end
end
