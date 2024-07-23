#!/bin/bash

xcodebuild archive -project ZPTCPIPStack.xcodeproj -scheme ZPTCPIPStack -destination "generic/platform=macOS,variant=Mac Catalyst" -archivePath "archives/macCat/ZPTCPIPStack" &&
# xcodebuild archive -project ZPTCPIPStack.xcodeproj -scheme ZPTCPIPStack -destination "generic/platform=macOS" -archivePath "archives/mac/ZPTCPIPStack" &&
xcodebuild archive -project ZPTCPIPStack.xcodeproj -scheme ZPTCPIPStack -destination "generic/platform=iOS" -archivePath "archives/ios/ZPTCPIPStack" &&
xcodebuild archive -project ZPTCPIPStack.xcodeproj -scheme ZPTCPIPStack -destination "generic/platform=iOS Simulator" -archivePath "archives/sim/ZPTCPIPStack" &&
# xcodebuild -create-xcframework \
# -archive archives/ios/ZPTCPIPStack.xcarchive -framework ZPTCPIPStack.framework \
# -archive archives/sim/ZPTCPIPStack.xcarchive -framework ZPTCPIPStack.framework \
# -archive archives/mac/ZPTCPIPStack.xcarchive -framework ZPTCPIPStack.framework \
# -archive archives/macCat/ZPTCPIPStack.xcarchive -framework ZPTCPIPStack.framework \
# -output xcframeworks/ZPTCPIPStack.xcframework
xcodebuild -create-xcframework \
-archive archives/ios/ZPTCPIPStack.xcarchive -framework ZPTCPIPStack.framework \
-archive archives/sim/ZPTCPIPStack.xcarchive -framework ZPTCPIPStack.framework \
-archive archives/macCat/ZPTCPIPStack.xcarchive -framework ZPTCPIPStack.framework \
-output xcframeworks/ZPTCPIPStack.xcframework

