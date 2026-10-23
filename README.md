# Pulse

A macOS menu bar app that shows live network throughput and runs speed tests (via speed.cloudflare.com).

## Build

```bash
./build.sh            # builds build/Pulse.app
./build.sh --install  # copies to /Applications
./build.sh --run      # builds and launches
```

Requires macOS 13+ and Swift 5.9+.

## Notifications

Pulse alerts you when your network is **down**, **slow**, or **recovers**:

- **Down**: instantly when your Mac loses its network (after a 5s grace period for Wi-Fi switching), or after two failed connectivity checks in a row.
- **Slow**: when latency stays above your threshold (default 250 ms) for three checks in a row (~45s).
- **Speed test**: when a speed test measures download below your threshold (default 10 Mbps).

Checks run every 15s with a zero-byte request, so they use almost no data. They pause while a speed test runs.
Settings are in the popover under "Notify when network is slow or down". Notifications need the built `.app` (`./build.sh`), not `swift run`.

## Tests

```bash
swift test
```
