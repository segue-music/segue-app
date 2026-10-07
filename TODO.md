# TODO

## The iPhone's own name

Other devices see an iPhone as "iPhone" (an iPad as "iPad"), not by its name in Settings: since
iOS 16, `UIDevice.current.name` gives that name only to an app with Apple's
`com.apple.developer.device-information.user-assigned-device-name` entitlement. The app already asks
for it (`ios/Runner/AppDelegate.swift`); only the entitlement is missing.

1. Request it at https://developer.apple.com/contact/request/user-assigned-device-name/. Connect
   fits Apple's criteria: the name shows in the device picker, it identifies the user's own devices
   in a feature across several of them, and it goes only to the user's own media server and hub.
   The request needs screenshots of the picker listing devices by name (from a computer or an
   Android phone).
2. Once Apple grants it: in the Apple Developer site, turn on "User Assigned Device Name" under the
   App ID's Additional Capabilities, make the App Store provisioning profile again and fetch it
   again in Codemagic.
3. Add `ios/Runner/Runner.entitlements` with the key (`<true/>`) and point the Runner target's
   `CODE_SIGN_ENTITLEMENTS` at it, in its three configurations (Debug, Release, Profile). Not
   before step 2: a profile without the entitlement fails the build's signing.
4. In `README.md`, drop "What iOS does differently"'s item on the name, and add the entitlement to
   "Running on iOS" (step 1 there says "with no extra capabilities").
