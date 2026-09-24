# Fader

Fader is a menu-bar audio splitter for macOS. Each app that is playing gets its own volume, mute, and output device. Spotify can stay on your headphones while the browser plays through the speakers.

It runs on macOS 14.2 and later. Fader captures each app with a Core Audio process tap, applies that app’s volume, and plays the result on the device you pick. Quitting Fader hands audio back to the system output.

## What v1 does

- Lists only apps that are currently playing, and keeps a row up for a couple of seconds between tracks
- Per-app volume, mute, and output device
- Master volume
- Remembers each app’s volume, mute, and device
- New apps follow the system output until you pick a device
- If headphones unplug, that app falls back to the system output and returns to the headphones when they reconnect

Input routing and keyboard shortcuts are not in this version.

## Run it

1. Open `Fader.xcodeproj` in Xcode 15 or later on macOS 14.2+.
2. Run the Fader scheme.
3. When macOS asks, allow System Audio Recording.
4. Play audio in another app. It shows up in the menu-bar panel.

Click **Open mixer** if you want the panel to stay on screen.

The menu-bar icon is `slider.vertical.3`. There is no Dock icon.

Saved routes live in `~/Library/Application Support/Fader/routes.json`.

## Logic tests

The routing rules, app grouping, and saved settings are in `Sources/FaderCore` so they can be tested without Core Audio:

```sh
swift test
```

## Permission

The first capture prompts for System Audio Recording. If you deny it, the panel links to System Settings → Privacy & Security → System Audio Recording. The Mac App Store is a poor fit for this, so Fader is meant to be built and run directly. The license is MIT.
