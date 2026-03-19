#!/bin/bash
# Post-iOS Export Script for Orbital Pop
# Run this after each Godot iOS export

set -e
cd "$(dirname "$0")/.."

BUILD_DIR="build"
echo "=== Post-iOS Export Setup ==="

# 1. Update dummy.cpp with AdmobPlugin + IAP init
echo "Updating dummy.cpp..."
cat > "$BUILD_DIR/OrbitalPop/dummy.cpp" << 'DUMMY_EOF'
/**************************************************************************/
/*  dummy.cpp                                                             */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/

// Godot Plugins
void godot_apple_embedded_plugins_initialize();
void godot_apple_embedded_plugins_deinitialize();
// Exported Plugins

// Plugin: AdmobPlugin
extern void admob_plugin_init();
extern void admob_plugin_deinit();

// Plugin: IOSInAppPurchase
extern void ios_in_app_purchase_init();
extern void ios_in_app_purchase_deinit();

// Use Plugins
void godot_apple_embedded_plugins_initialize() {
	admob_plugin_init();
	ios_in_app_purchase_init();
}

void godot_apple_embedded_plugins_deinitialize() {
	admob_plugin_deinit();
	ios_in_app_purchase_deinit();
}
DUMMY_EOF

# 2. Update Info.plist with AdMob App ID
echo "Updating Info.plist with AdMob App ID..."
/usr/libexec/PlistBuddy -c "Add :GADApplicationIdentifier string ca-app-pub-4474484017776291~8538825055" "$BUILD_DIR/OrbitalPop/OrbitalPop-Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :GADApplicationIdentifier ca-app-pub-4474484017776291~8538825055" "$BUILD_DIR/OrbitalPop/OrbitalPop-Info.plist"

# 3. Copy plugin xcframeworks
echo "Copying AdmobPlugin.xcframework..."
cp -r ios/plugins/AdmobPlugin.debug.xcframework "$BUILD_DIR/AdmobPlugin.xcframework"

echo "Copying ios-in-app-purchase.xcframework..."
cp -r ios/plugins/ios-in-app-purchase.xcframework "$BUILD_DIR/ios-in-app-purchase.xcframework"

# 4. Configure Xcode project
echo "Configuring Xcode project..."
cd "$BUILD_DIR"
ruby - << 'RUBY_EOF'
require 'xcodeproj'

project_path = 'OrbitalPop.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Set deployment target, Swift settings, and device family
target.build_configurations.each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  config.build_settings['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = '$(inherited)'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'

  library_search_paths = config.build_settings['LIBRARY_SEARCH_PATHS'] || ['$(inherited)']
  library_search_paths = [library_search_paths] if library_search_paths.is_a?(String)
  library_search_paths << '$(TOOLCHAIN_DIR)/usr/lib/swift/$(PLATFORM_NAME)' unless library_search_paths.include?('$(TOOLCHAIN_DIR)/usr/lib/swift/$(PLATFORM_NAME)')
  library_search_paths << '$(SDKROOT)/usr/lib/swift' unless library_search_paths.include?('$(SDKROOT)/usr/lib/swift')
  config.build_settings['LIBRARY_SEARCH_PATHS'] = library_search_paths
end

# Add plugin frameworks if not present
{'AdmobPlugin' => 'AdmobPlugin.xcframework', 'ios-in-app-purchase' => 'ios-in-app-purchase.xcframework'}.each do |name, path|
  already_added = project.frameworks_group.files.any? { |f| f.path&.include?(name) }
  unless already_added
    ref = project.frameworks_group.new_file(path, :project)
    target.frameworks_build_phase.add_file_reference(ref)
  end
end

# Add system frameworks
['AdServices.framework', 'AdSupport.framework', 'AppTrackingTransparency.framework',
 'CoreTelephony.framework', 'SystemConfiguration.framework', 'WebKit.framework'].each do |framework|
  existing = project.frameworks_group.files.any? { |f| f.path == framework }
  unless existing
    ref = project.frameworks_group.new_file(framework, :sdk_root)
    target.frameworks_build_phase.add_file_reference(ref)
  end
end

project.save
puts "Xcode project configured!"
RUBY_EOF

echo ""
echo "=== Setup Complete ==="
echo "Open OrbitalPop.xcodeproj in Xcode to build and run"
