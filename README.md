# step1-topic-notifier

A local-only macOS menu bar app that periodically sends a notification with a USMLE Step 1 topic selected by a spaced repetition scheduler.

The notification title is the topic, and the body says:

```text
Talk through this from memory.
```

Notifications include three review buttons:

- `Again`: you missed it. The topic comes back soon and opens a Google search.
- `So-So`: you partially knew it. The topic comes back moderately soon and opens a Google search.
- `Good`: you knew it. The topic is pushed later and does not open Google.

Clicking the notification body is treated like `So-So` and opens a Google search for:

```text
<topic> USMLE Step 1
```

## Requirements

- macOS 13 or newer
- Xcode with the macOS SDK installed

## Open, Build, and Run

1. Open `step1-topic-notifier.xcodeproj` in Xcode.
2. Select the `step1-topic-notifier` scheme.
3. Select `My Mac` as the run destination.
4. Press `Cmd-R` to build and run.
5. The app appears in the macOS menu bar as a bell icon. It does not open a normal window.
6. On first launch, allow notification permissions when macOS prompts you.

If Xcode asks for signing settings, select your local Apple Development team in the target's `Signing & Capabilities` tab. The app is intended for local use only and does not require App Store distribution.

## Menu Actions

- `Start Notifications`: schedules the next spaced repetition topic notification.
- `Stop Notifications`: cancels the scheduled topic notification.
- `Interval`: choose 10, 15, 20, 30, 45, or 60 minutes.
- `Launch at Login`: uses `SMAppService.mainApp` on macOS 13+.
- `Trouble Topics`: lists the reviewed topics with the highest weakness scores. Clicking one sends an immediate review notification for that topic.
- `Send Test Notification`: sends an immediate local notification.
- `Quit`: exits the menu bar app.

## Local Data

Topics are bundled in `step1-topic-notifier/topics.json`. Review history is stored locally in `UserDefaults` and includes each topic's last review, next due date, ease factor, interval, review count, and latest rating. The app does not use a backend or network service. The only network action is opening the browser after `Again`, `So-So`, or a notification body click.

## Command-Line Note

This project is meant to be built from Xcode. If `xcodebuild` reports that the active developer directory is `/Library/Developer/CommandLineTools`, switch to full Xcode first:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```
