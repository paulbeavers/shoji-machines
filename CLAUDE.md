# CLAUDE.md — Shoji Machines

Companion app of `../shoji` (the tiling window manager): Linux server VMs on Apple's
Virtualization framework, with consoles and SSH in kitty windows. Split out of the shoji repo
on 2026-11-14 (user decision) so VMs run in their own process and survive Shoji restarts. The VM
engine came from MacLucent (`../mactile/Sources/MacLucent/VM`, see its CLAUDE.md for the
history of every VM fix).

## Build, run

```bash
./scripts/build-app.sh            # → build/Shoji Machines.app
open "build/Shoji Machines.app"
```

- Signed ad-hoc with `Resources/Machines.entitlements` (com.apple.security.virtualization — VMs
  can't start without it) and DR `identifier "dev.shoji.Machines"`. Keep both.
- The build runs `lsregister -f` so Shoji's Mod+M (`NSWorkspace.urlForApplication(withBundleIdentifier:)`)
  finds it. Bundle id `dev.shoji.Machines` is what Shoji looks for — don't change it.
- Themes: `scripts/sync-themes.sh` copies ../lucent's `*.theme` (committed copy too). The active
  theme is read from Shoji's `~/.config/shoji/settings.json`; Shoji posts the distributed
  notification `dev.shoji.settingsChanged` on save, and the Machines window recolours.
- Window opacity and hidden title bars follow Shoji's Settings → Windows (`windowOpacity`,
  `hideTitleBars` in settings.json; the older `kittyOpacity`/`kittyHideTitlebar` are read as a
  fallback).
- Commit and push only when asked; Co-Authored-By line at the end of commit messages.

## Files (Sources/ShojiMachines)

| File | Role |
|---|---|
| `main.swift` | `--console` client mode, `--render-icon`, else the app |
| `MachinesAppDelegate.swift` | Window, menus, reopen, quit (asks, then `stopAll` with `.terminateLater`) |
| `MachinesWindow.swift` | The Machines list + New VM form (`MachinesApp`, `NewVMForm`, `VMRowView`) |
| `VMLibrary.swift`, `QCOW2.swift`, `VMManager.swift` | VM engine (images, cloud-init seed, VZ config, lifecycle) |
| `ConsoleServer.swift` | Console socket server, `ConsoleClient`, `Kitty` launcher, `Duration` |
| `Config.swift` | Theme from Shoji's settings, colours/fonts, `FlippedView` |
| `Themes.swift`, `AppIcon.swift` | Lucent theme parser; icon |
| `MachinesTest.swift` | Headless end-to-end test |

## Design notes

- A regular app (Dock icon); Shoji tiles its window like any app's. VMs live in this process, so
  they survive Shoji restarts (the reason for the split — the user restarts Shoji often).
- VM engine copied from MacLucent (`../mactile/Sources/MacLucent/VM`); VMs in
  `~/.config/shoji/vms` (`SHOJI_VMS_DIR` for tests). Guest files renamed `shoji-*`. All the
  MacLucent VM notes (cloud-init, `read -t 1`, `.common` timers, IP via dhcpd_leases…) apply.
- **Consoles are kitty windows:** `ConsoleServer` serves each VM's hvc0 on
  `/tmp/shoji-<uid>/<id>.sock` (short path: sun_path limit), replaying history to new clients;
  kitty runs `Shoji Machines --console <socket> <name>` (`ConsoleClient`: raw tty, poll loop).
  kitty itself answers the guest's `CSI 18 t` size query. Enter in a stopped VM's console starts
  it. SSH = `open -n -b kitty --args ssh …` with the VMs folder's known_hosts.
- Theme changes reach Shoji Machines through the distributed notification
  `Config.changedAcrossApps` posted by `Config.save()`.
- **Test** headless: `SHOJI_MACHINES_TEST=<log> SHOJI_VMS_DIR=<scratch> SHOJI_CONFIG_DIR=<scratch>
  "build/Shoji Machines.app/Contents/MacOS/Shoji Machines"`
  (activation policy .prohibited: never on screen) — creates, boots, round-trips a command through
  a real console client, checks IP + ssh, quits (clean VM stop). It caught a real bug: in the
  client, `write(fd, &buf[off], …)` passes a pointer to a one-byte temporary — use
  `buf.withUnsafeBytes`.


## Testing — the user's real VMs and desktop

- Always `SHOJI_VMS_DIR=<scratch>` and `SHOJI_CONFIG_DIR=<scratch>`; never touch `~/.config/shoji/vms`.
- `SHOJI_MACHINES_TEST` runs headless (activation policy `.prohibited`); macOS has no `timeout`
  command — use the `& P=$!` / `kill -0` loop. Copy/clone cached images into the scratch `images/`.
