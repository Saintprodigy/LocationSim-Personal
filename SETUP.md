# Build and setup

## Requirements

- A Mac with full Xcode and its iOS SDK, plus XcodeGen (`brew install xcodegen`).
- An iPhone running iOS 18 or later as the build deployment target; that minimum is not a guarantee that every version works. Development testing focused on an iPhone XR running iOS 18.7.10.
- Apple development signing, Developer Mode, and a trusted developer profile where prompted.
- LocalDevVPN installed from its [official App Store link](https://apps.apple.com/us/app/localdevvpn/id6755608044).
- A device-specific RPPairing file from [idevice_pair](https://github.com/jkcoxson/idevice_pair). This is not a SideStore lockdown pairing file.

## Build your own app

```sh
git clone --recurse-submodules https://github.com/Saintprodigy/LocationSim-Personal.git
cd LocationSim-Personal
xcodegen generate
open LocationSimulatorPersonal.xcodeproj
```

Choose your development team for **both** LocationSimulatorPersonal and TripActivityExtension in Signing & Capabilities. Change the bundle identifiers to identifiers your team can sign (including the extension's matching prefix). Select your connected iPhone, then Build and Run. Alternatively pass your team to the command-line build:

```sh
xcodebuild -project LocationSimulatorPersonal.xcodeproj \
  -target LocationSimulatorPersonal -configuration Debug -sdk iphoneos \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID -allowProvisioningUpdates build
```

The included native library targets iPhone devices, not the iOS Simulator. The dependency submodule records the source revision; rebuilding it requires the upstream Rust/iOS toolchain instructions. No personally signed IPA or provisioning credential is distributed here.

## First connection

1. Connect and trust your iPhone on the computer. Enable Developer Mode on the phone and complete any restart/confirmation it requests.
2. Generate an **RPPairing** file with idevice_pair for that phone and import it in LocationSim Settings. Keep it private.
3. Open LocalDevVPN, approve its VPN configuration when iOS asks, and connect it. Use its default configuration; the developer endpoint used by LocationSim is `10.7.0.1`.
4. Return to LocationSim and test a teleport. If offered, allow Local Network access. Location permission is used for the map's real-location feature and is distinct from developer pairing.
5. Check actual location in another app. A map pin or VPN icon alone is not proof that simulation succeeded.

## Outside with no Wi-Fi, try this:

1. Keep mobile data on, open LocalDevVPN, and connect it.
2. Open LocationSim and choose your destination. For a new route or address search, do this while data is on.
3. If the tunnel error appears, briefly turn mobile data off—leave LocalDevVPN connected.
4. Return to LocationSim and retry the teleport or saved trip.
5. Once it successfully starts, turn mobile data back on.

The app also retains pending destinations and retries on network changes. It cannot toggle cellular data for you. The workaround has been reported working by the owner; it is not guaranteed after every restart or on every device. Do not repeatedly regenerate pairing for a network-route error.

## Troubleshooting and maintenance

- **Tunnel failure:** check LocalDevVPN is actually connected, try the data sequence above, and reconnect the helper if needed. Wi-Fi can be a fallback for establishing a session.
- **Search or directions fail:** restore Internet access; use an existing saved trip for offline playback.
- **App won't launch:** check signing/profile expiry before treating it as a tunnel failure. Re-sign without changing the bundle ID if you want to preserve app data.
- **New phone:** export your library, generate fresh pairing for that device, then restore the library. Backups exclude pairing credentials.
- **Unexpected stop:** reopen the app and verify recovery; force-quit/background/reboot behavior is not guaranteed.
- **Reporting bugs:** include app/iOS versions, Wi-Fi/cellular state, whether the VPN is connected, and redacted error text. Never attach pairing files, private keys, or personal saved trips.
