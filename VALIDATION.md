# Validation and known boundaries

Source snapshot: 1.5.2 build 14.

- Local signed device build and deep signature verification passed for the Settings addition.
- The owner reported successful no-Wi-Fi operation using the mobile-data toggle workaround on September 5, 2026. This does not establish universal cold startup with data left on.
- Earlier device diagnostics distinguished Internet route generation from developer-tunnel connection failure. Wi-Fi route playback and stop were observed; not all changes in this snapshot received a new physical-device run.
- Build 14 adds the five-step guide at the bottom of Settings. Installation on the owner's paired iPhone succeeded on September 5, 2026. A subsequent launch succeeded after the initial locked-device rejection. The Settings layout was not independently visually inspected in this final installation check.
- Newer recovery code retains a successfully cleared connection, retries pending destinations on foreground/path changes, and does not treat a retained native handle as proof of simulated GPS.
- The developer test harness restores its current library snapshot rather than an old backup. It is not an exhaustive test suite or independent Find My verification.

Before relying on a new release, test real-device Wi-Fi start; data-off/start/data-on; saved offline trip; stop/restart; travel-mode/speed changes; library backup/restore; background/lock; and reboot recovery. Observe both beginning and ending network states. Never call a simulated network event an actual cellular transition.
