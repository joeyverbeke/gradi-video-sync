# Minimal VLC + vlcsync reset

This guide resets the in-progress deployment to the minimal “two Pis, one screen each” layout. The Pi you are currently logged into (`gradi-mediate`) is both a player and the `vlcsync` controller. The second Pi (currently `gradi-compress`, or whichever host you use at `192.168.0.9`) is a worker player. Expand back to four Pis later by following the same pattern.

## Targets and naming

- **Hostnames & IPs**

  | Hostname        | IP address    | Role              |
  |-----------------|---------------|-------------------|
  | `gradi-mediate` | `192.168.0.4` | Controller + screen |
  | `gradi-compress` (worker) | `192.168.0.9` | Worker + screen   |

- **Media naming** – copy the portrait HEVC masters into `/media/videos/front.mp4` (controller) and `/media/videos/back.mp4` (worker). Use these filenames consistently so scripts do not need per-device edits.
- **RC port** – every VLC worker exposes RC commands on TCP `5001`.

## 1. Clean up legacy services on both Pis

Run the reset helper locally on each Pi. It removes the old looper/systemd units and desktop autostarts, then kills any leftover VLC processes.

```bash
sudo ./scripts/reset_vlcsync_services.sh
```

Set `DRY_RUN=1` if you first want to see which units would be touched (`DRY_RUN=1 sudo ./scripts/reset_vlcsync_services.sh`). The script is idempotent; rerun it if you suspect a Pi still has stray units.

## 2. Install the worker VLC unit

Run the worker installer with the appropriate clip per Pi:

```bash
# On gradi-mediate (controller + screen)
sudo ./scripts/install_worker_units.sh --video /media/videos/front.mp4

# On the worker Pi (e.g., gradi-compress)
sudo ./scripts/install_worker_units.sh --video /media/videos/back.mp4
```

Optional flags:

- `--display` – change the QT screen index if HDMI ordering differs (default `0`).
- `--rc-port` – move the RC listener off 5001 if another service already binds that port.
- `--user` – override which Linux user runs VLC; defaults to the sudo user invoking the script (or `pi`).
- `--xdisplay` – override the X11 display if it is not `:0`.

After the script runs, `systemctl status gradi-vlc-screen0` should show VLC looping (it will sit black until the media file exists).

## 3. Install the gated `vlcsync` controller on `gradi-mediate`

Run the controller helper as the non-root user that should own the service (default `pi`):

```bash
./scripts/install_controller_service.sh
```

The script installs `vlcsync` via `pip --user`, deploys `systemd/gradi-vlcsync-gated.user.service` into `~/.config/systemd/user`, and enables lingering so the user service stays up after logout. The service waits for both RC sockets (`192.168.0.4:5001` and `192.168.0.9:5001`) to accept TCP connections before launching `vlcsync`, then sends the `stop → seek 0 → play` command burst to start both Pis in lockstep.

If you ever change IPs or the RC port, edit `systemd/gradi-vlcsync-gated.user.service` in the repo, redeploy it with the script, and restart the user service (`systemctl --user restart gradi-vlcsync-gated.service`).

## 4. Boot test

1. Power-cycle both Pis (bring the worker up first so its RC socket is ready).
2. Watch `sudo journalctl -u gradi-vlc-screen0 -f` on each Pi to ensure VLC binds the RC port without errors.
3. On `gradi-mediate`, run `journalctl --user -u gradi-vlcsync-gated -f` to confirm the controller waits for both endpoints, launches `vlcsync`, and emits the synchronized start burst.
4. Observe playback for several loops; the controller keeps issuing corrections to hold sync.

## 5. Notes

- Keep NTP enabled (`timedatectl status`) and use wired Ethernet to minimize jitter.
- Validate HEVC decode on new SD images with `scripts/phase1_validate.sh` before running the worker installer.
- Update `/etc/default/gradi-vlc-screen0` if you remap HDMI outputs or swap to new media files, then restart the service.
