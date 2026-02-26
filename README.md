# FlexBank

A macOS menu bar app for tracking flex time.

## What it does

- Runs only in the menu bar (no dock icon).
- Keeps a simple flex bank (`+` and `-` time).
- Quick-adds your usual early time (default `+30m`) once per day.
- Lets you manually add time or remove time in minutes.
- Sends weekday reminders to update your bank.
- Saves data locally in `~/Library/Application Support/FlexBank/state.json`.

## Run

Development run:

```bash
swift run
```

Build an app bundle (recommended for reminders + normal app launch):

```bash
./scripts/build-app.sh
open dist/FlexBank.app
```

After launch:

1. Click the `⏱` icon in the macOS menu bar.
2. Use `Quick add +30m` when you came in early.
3. Use `Add time...` or `Remove time...` to update your flex bank.
4. Configure quick-add minutes and reminder time from the same menu.

## Tips

### Start at login

1. Build the app bundle with `./scripts/build-app.sh`.
2. Move or copy `dist/FlexBank.app` to `/Applications` (or wherever you keep apps).
3. Open **System Settings → General → Login Items & Extensions**.
4. Click **+** under "Open at Login" and select `FlexBank.app`.

### Notifications

- On first `.app` launch, macOS asks for notification permission. Allow it to get weekday reminders.
- To change notification settings later, go to **System Settings → Notifications → FlexBank**.
- If you run with `swift run`, notifications are disabled by design (development mode).

### Data

- State is stored in `~/Library/Application Support/FlexBank/state.json`.
- To start fresh, quit FlexBank and delete that file.
- The file is plain JSON — safe to back up or inspect manually.
