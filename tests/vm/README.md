# Prime Linux — Headless VM Test Harness (`tests/vm/`)

This directory contains the reproducible QEMU/KVM harness for provisioning a clean Arch Linux guest with Prime Linux and running all three layers of the E2E suite (`structural.sh`, `contracts.sh`, `journeys.sh`) without ever opening a window on the host desktop.

## Prerequisites & State Directory

Large disk images and SSH keys live in `${PRIME_VM_DIR:-~/VMs/prime}` (outside the git tree):
- `arch-cloud.qcow2` — base Arch Linux cloud image
- `disk.qcow2` — 40G throwaway copy-on-write overlay (`rm ~/VMs/prime/disk.qcow2` resets the machine in seconds)
- `seed.iso` — cloud-init seed (`build-seed.sh`)
- `id_ed25519` — SSH key for `sean@127.0.0.1` (port `2222`)

## Commands

```bash
# 1. Start the VM headless (VirGL egl-headless + VNC connector on 127.0.0.1:5901)
bash tests/vm/start-vm.sh

# 2. Copy the repo (including .git) into the VM and run `install.sh --yes`
bash tests/vm/provision-vm.sh

# 3. Start Hyprland headlessly inside the guest and run the E2E suite
bash tests/vm/run-suite.sh          # full suite: structural + contracts + journeys
bash tests/vm/run-suite.sh --fast   # read-only layers: structural + contracts
```

## How the Headless Hyprland 0.57 Display Path Works

Getting Hyprland 0.57 (Aquamarine DRM backend + Lua config loader) to run headlessly inside a QEMU guest requires solving three specific constraints:

1. **Both a GBM 3D render node and a connected display output**:
   - `-vga std` (`bochs-drm`) has no `/dev/dri/renderD128` node and cannot allocate GBM scanout buffers (`GBM: Failed to allocate a GBM buffer: bo null`).
   - `-display egl-headless` alone attaches no display connector to `virtio-vga-gl`, so Aquamarine sees 0 outputs.
   - **Solution (`start-vm.sh`)**: `-vga none -device virtio-vga-gl -display egl-headless,rendernode=/dev/dri/renderD128 -vnc 127.0.0.1:5901`. This exposes VirGL `/dev/dri/renderD128` for hardware-accelerated GBM buffers AND attaches a connected `Virtual-1` (`1280x800@75Hz`) output while opening zero windows on the host.
2. **DRM master on `seat0` (`tty1`)**:
   - Launching Hyprland directly from an SSH session has no VT seat and collides with `sddm.service` / `getty@tty1.service` (`atomic drm request: failed to commit: Permission denied`).
   - **Solution (`run-suite.sh`)**: Stop `sddm.service` and `getty@tty1.service`, then launch `/usr/bin/Hyprland` via `systemd-run --unit=prime-vm-hypr --uid=sean --gid=sean -p PAMName=login -p TTYPath=/dev/tty1 -p StandardInput=tty -E AQ_NO_MODIFIERS=1 /usr/bin/Hyprland`.
3. **Hyprland 0.57 Lua config entry point**:
   - Passing `--config ~/.config/hypr/hyprland.conf` forces Hyprland 0.57's CLI to parse `hyprland.conf` as Lua (`unexpected symbol near '#'`).
   - **Solution (`run-suite.sh`)**: Invoke `/usr/bin/Hyprland` without `--config` so it loads `~/.config/hypr/hyprland.lua`, which bridges `hyprland.conf` via `hl.legacy_config(...)` with zero config errors.
4. **Preventing `hypridle` / `hyprlock` from blocking `grim`**:
   - When `hypridle` locks the session with `hyprlock` (`ext-session-lock-v1`) or turns DPMS off after idle timeout, `wlr-screencopy` (`grim`) blocks waiting for an unlocked frame.
   - **Solution (`run-suite.sh`)**: Terminate `hypridle`/`hyprlock` and ensure `dpms on` before running the suite.
