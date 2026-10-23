Pulse is a macOS menu bar app that shows your live network speed, runs speed tests, and notifies you when your network is slow or down.

Works on macOS 13 (Ventura) or newer, on both Apple Silicon and Intel Macs.

## Install

1. Download **Pulse.zip** below and double-click it to unzip.
2. Drag **Pulse.app** into your **Applications** folder.
3. Open Pulse. macOS will say it can't verify the developer. Click **Done** (or **Cancel**).
4. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the Pulse message. Confirm with your password.
5. Pulse appears in your menu bar (top right), showing ↓ and ↑ speeds. Click it to open.
6. When asked, click **Allow** so Pulse can send notifications.

You only need steps 3–4 the first time. macOS asks because Pulse isn't signed with a paid Apple developer account.

Prefer Terminal? After step 2, run:

```
xattr -dr com.apple.quarantine /Applications/Pulse.app
```

## What's in it

- Live download and upload speed in the menu bar, with a 60-second graph
- Speed test (download, upload, latency, jitter) via Cloudflare
- Notifications when your network goes down, gets slow, or recovers
- Alert when a speed test comes in below a speed you choose
- Option to show speeds in bits (Mbps, like fast.com) or bytes (MB/s)
- Launch at login
