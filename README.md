# Shoji Machines

Linux server VMs for macOS, the companion app of [Shoji](../shoji) (a Hyprland-style tiling window
manager). Create VMs from cloud images — Debian 13/12, Ubuntu 26.04/24.04/26.10, Fedora, Rocky 10,
AlmaLinux 10, Alpine — on Apple's Virtualization framework, start and stop them, and open a VM's
serial console or an SSH session in a **kitty** window. Shoji opens it with **Mod+M**.

```bash
./scripts/build-app.sh            # → build/Shoji Machines.app (registered with macOS for Shoji)
open "build/Shoji Machines.app"
```

- VMs keep running when Shoji restarts (they live in this app); quitting Shoji Machines shuts
  them down cleanly. Closing its window keeps them running.
- Each VM logs you in as your Mac user with passwordless `sudo` and your `~/.ssh/*.pub` keys; the
  console works without networking and follows the kitty window's size.
- VMs, images and settings live in `~/.config/shoji` (shared with Shoji; the theme follows Shoji's).
- Requires an Apple Silicon Mac, macOS 13+, kitty, and a Swift toolchain to build.
