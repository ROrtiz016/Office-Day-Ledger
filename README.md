# Office Day Counter

A macOS menu-bar app for tracking a fixed goal of 12 days per month. Office days and PTO count; weekends and excluded dates do not. Records and settings are stored locally in macOS user defaults.

## Requirements and local build

macOS 14 or later and Xcode with the Swift 6 toolchain are required. From this folder:

```sh
swift test
sh Scripts/build-app.sh
open build/OfficeDayCounter.app
```

The script creates an ad-hoc signed app for local use. Quit any running copy before rebuilding or replacing it, then open the newly built bundle. To install it locally, copy the built app to Applications and open that copy. Keep a backup before replacing or removing an installation. macOS may ask for permissions again after a rebuild or move.

## Setup and daily use

Select a past or current eligible date to cycle between office, PTO, and unmarked. Excluding a date hides an existing mark from counts and reports; removing the exclusion restores it.

Under **Network automation**, save the exact office Wi-Fi name and enable detection. Grant Location access so macOS can provide the Wi-Fi name, and enable notification alerts. Confirm a detected day in the app or notification. The app must be running for Wi-Fi detection and progress checks; **Launch at login** can start it automatically, subject to macOS approval in Login Items. Checks may be delayed or missed while the Mac sleeps or the app is closed.

## Backup and recovery

Use **Export backup** to save a JSON copy of the records and settings somewhere safe. **Import backup** validates the file and shows a summary before replacing all current records and settings. Export a current backup before restoring an older one. CSV and PDF exports are reports, not restorable backups.

If notifications or Wi-Fi detection do not work, check the app's status and the Location and Notifications settings in System Settings. Confirm the saved Wi-Fi name matches exactly and the app is running. Manual calendar editing works without Wi-Fi detection.

## Validation and distribution

Run `swift test` for the automated logic tests. Before using a new build, also check calendar editing, backup export and restore, Wi-Fi and notification permissions, notification actions, sleep/wake, launch at login, and CSV/PDF exports on macOS. The automated tests do not verify these system integrations. Use test records or export a backup before exercising restore.

The local build script does not create a Developer ID signed or notarized distribution, an installer, or an update mechanism. Distribution outside the local machine requires a release signing and notarization process, an installation and update strategy, and testing on a clean Mac. No automatic updates are currently provided.
