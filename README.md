# LocationSim Personal

A personal iPhone location simulator with saved trips, folders, adjustable movement speeds, and cellular-session recovery. Based on [Locus](https://github.com/ChrisMack32/Locus), with the original MIT license retained. This is an independent derivative, not the official upstream release.

**Current design: two apps — LocationSim Personal and LocalDevVPN.** No hosted VPN server or recurring server bill is required. After initial device pairing, everyday use does not require a Mac or USB connection. App signing still needs maintenance.

## Features

- Map-based teleporting and address/place search.
- Road-route planning, drawn paths, and GPX import/export.
- Walking, running, cycling, and driving; change travel mode during playback, with a tortoise-to-rabbit speed slider and separate saved speeds for each mode.
- Joystick movement, route pause/resume, reversing, looping, arrival pauses, and movement variation.
- Named saved trips, folders, tags, saved locations, and recent locations.
- Library export/restore, including movement settings; device pairing credentials are deliberately excluded.
- Map styles, route progress, remaining distance, ETA, background keep-alive, Live Activity, and interruption notices.
- Shortcuts actions for saved trips, pause/resume, stopping simulation, and opening the library.
- Saved-session restoration, pending-destination retry, and connection reuse after stopping.
- Built-in mobile-data connection instructions at the bottom of Settings.

## How location changes work

The map and route player produce coordinates. The [idevice](https://github.com/jkcoxson/idevice) library sends them through a paired local developer connection to Apple's location simulation service. Apps that accept the resulting system location can display that position. The owner has reported seeing it in Find My, but behavior across apps and future iOS releases is not guaranteed. This is not an IP-address VPN or an anti-cheat bypass. Find My sharing updates still depend on connectivity and Apple's services.

## Why two apps?

LocationSim supplies the interface and location commands. [LocalDevVPN](https://github.com/jkcoxson/LocalDevVPN) supplies the local tunnel. Its VPN is not a remote server connection. Keeping that component in its separately signed app allows the LocationSim build to use personal development signing without a Network Extension entitlement.

An embedded Packet Tunnel extension is a possible future option, but is **not implemented** here. It requires suitable signing, normally paid Apple Developer membership. Embedding a VPN would not by itself prove that cellular startup limitations are fixed.

## Setup and outside-without-Wi-Fi instructions

See [SETUP.md](SETUP.md) for building, installation, pairing, and the exact cellular workaround.

The owner confirmed that the data-off/start/data-on workaround worked without Wi-Fi on their phone. This is a reported device result, not a guarantee for every iOS version, carrier, reboot, or VPN state.

## Limitations — please read

- LocalDevVPN must remain available and connected; other VPNs may conflict.
- Cold startup on cellular can fail. Briefly disabling mobile data can allow the local session to start; restore data afterward. Some states may still require reconnecting the VPN or starting on Wi-Fi.
- Saved/drawn coordinate playback does not require Internet access once the local tunnel works. New address searches, road directions, and uncached map tiles need Internet access.
- Background execution is best effort. Force-quitting, iOS termination, rebooting, or signing expiry can interrupt operation. Do not depend on an unattended route continuing forever.
- Developer Mode, a valid device-specific RPPairing credential, and valid app signing are required. Free signing normally needs frequent renewal.
- New devices require their own pairing. Future iOS compatibility is not promised; experimental newer-OS pairing branches are not a compatibility certification.
- Apps may reject simulated locations. This project does not bypass those checks.
- No claim of bug-free operation. See [VALIDATION.md](VALIDATION.md) for what was and was not checked.

## Privacy and source publication

The library is stored locally; no analytics service is added. Map/search requests use Apple's services, and location-consuming apps may transmit location themselves. This repository excludes the owner's pairing files, signing profiles, personal library, screenshots, device reports, and private development history. Never upload an RPPairing file in a bug report.

## Source layout

| Component | Role |
| --- | --- |
| `Locus/Features` | Settings, maps, joystick, route and library interfaces |
| `Locus/Engine/SpoofSession.swift` | Movement, route state, persistence and recovery |
| `Locus/Engine/LocationEngine.swift` | Serialized native developer-service connection |
| `Locus/Engine/PairingStore.swift` | Protected device credential storage |
| `Locus/Support` | Saved trips, folders, backups and LocalDevVPN integration |
| `Locus/App/LocationSimIntents.swift` | Shortcuts actions |
| `Shared`, `TripActivityExtension` | Live Activity models and presentation |
| `Vendor/idevice` | Device-target FFI library and headers |
| `Dependencies`, `Tools` | Pinned upstream source submodules |

## Credits and license

- [Locus / ChrisMack32 and contributors](https://github.com/ChrisMack32/Locus): base app, MIT; see [LICENSE](LICENSE).
- [idevice / jkcoxson and contributors](https://github.com/jkcoxson/idevice): developer communication, MIT; see [vendor license](Vendor/idevice/LICENSE.txt).
- [idevice_pair](https://github.com/jkcoxson/idevice_pair): external pairing utility; its own license applies.
- [LocalDevVPN](https://github.com/jkcoxson/LocalDevVPN): separately installed dependency, not bundled or relicensed by this project.
- Cellular recovery research: [Mirage setup](https://github.com/xXWapixelXx/Mirage-updates/blob/main/SETUP.md), [StikJIT integration](https://github.com/StikDebug/StikJIT/blob/main/INTEGRATION.md), and [community reports](https://www.reddit.com/r/sideloaded/comments/1v9z69n/locus_forever_free_opensource_no_accounts_gps/). Reports inform workarounds, not universal compatibility claims.

Use only on devices you own or are authorized to test. Be mindful of location-sharing recipients and application terms. Not affiliated with Apple or the external projects listed above.
