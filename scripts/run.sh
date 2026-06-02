xcodebuild -project Furioke/Furioke.xcodeproj -scheme Furioke -configuration Debug \
  -destination "platform=iOS,name=Jay's iPhone" -allowProvisioningUpdates build && \
xcrun devicectl device install app --device 00008150-0011023A11C0401C \
  /Users/Jay/Library/Developer/Xcode/DerivedData/Furioke-fikckrpqfumufvbdnrbwjhngnqpm/Build/Products/Debug-iphoneos/Furioke.app && \
xcrun devicectl device process launch --device 00008150-0011023A11C0401C com.magicparklabs.Furioke
