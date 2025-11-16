# Minimal VLC + vlcsync reset

This guide resets the in-progress deployment to the minimal “two Pis, three screens” layout. The Pi you are currently logged into (`gradi-mediate`) is both a player and the `vlcsync` controller. The second Pi (`gradi-compress` at `192.168.0.9`) is a worker that now drives **two** HDMI outputs.

## Targets and naming

- **Hostnames & IPs**

  | Hostname        | IP address    | Role / screens            | Expected media files |
  |-----------------|---------------|---------------------------|----------------------|
  | `gradi-mediate` | `192.168.0.4` | Controller + HDMI 0       | `/media/videos/front.mp4` |
  | `gradi-compress` | `192.168.0.9` | Worker + HDMI 0 & 1       | `/media/videos/back.mp4` (screen 0), `/media/videos/side.mp4` (screen 1 – name as needed) |

- **Media naming** – keep using `/media/videos/front.mp4` for the controller. On `gradi-compress`, place the two clips you want as `/media/videos/back.mp4` and `/media/videos/side.mp4` (or adjust when running the installer).
- **RC ports** – controller screen uses TCP `5001`. `gradi-compress` exposes two RC sockets: `5001` for HDMI 0 and `5002` for HDMI 1.

## 1. Clean up legacy services on both Pis

Run the reset helper locally on each Pi. It removes the old looper/systemd units and desktop autostarts, then kills any leftover VLC processes.

```bash
sudo ./scripts/reset_vlcsync_services.sh
```

Set `DRY_RUN=1` if you first want to see which units would be touched (`DRY_RUN=1 sudo ./scripts/reset_vlcsync_services.sh`). The script is idempotent; rerun it if you suspect a Pi still has stray units.

## 2. Install the worker VLC unit

Run the worker installer with the appropriate clip per Pi:

```bash
# On gradi-mediate (controller + single screen)
sudo ./scripts/install_worker_units.sh --video /media/videos/front.mp4

# On gradi-compress (worker with two screens)
sudo ./scripts/install_worker_units.sh \
  --video /media/videos/back.mp4 \
  --screen1-video /media/videos/side.mp4 \
  --screen1-display 1 \
  --screen1-port 5002
```

Optional flags:

- `--display` – change the QT screen index if HDMI ordering differs (default `0`).
- `--rc-port` – move the RC listener off 5001 if another service already binds that port.
- `--extra-args "FLAGS"` – append raw VLC flags (e.g., `--no-audio`) to the screen 0 service.
- `--screen1-video` (and related `--screen1-display`, `--screen1-port`) – enable a second VLC service on the same Pi. Omit these flags on single-screen devices.
- `--screen1-extra-args "FLAGS"` – inject custom VLC flags on the second screen; `--no-audio` is now applied on `gradi-compress` to keep HDMI 1 silent.
- `--user` – override which Linux user runs VLC; defaults to the sudo user invoking the script (or `pi`).
- `--xdisplay` – override the X11 display if it is not `:0`.

After the script runs, `systemctl status gradi-vlc-screen0` should show VLC looping (it will sit black until the media file exists).

## 3. Install the gated `vlcsync` controller on `gradi-mediate`

Run the controller helper as the non-root user that should own the service (default `pi`):

```bash
./scripts/install_controller_service.sh
```

The script installs `vlcsync` via `pip --user`, deploys `systemd/gradi-vlcsync-gated.user.service` into `~/.config/systemd/user`, and enables lingering so the user service stays up after logout. The service waits for all three RC sockets (`192.168.0.4:5001`, `192.168.0.9:5001`, and `192.168.0.9:5002`) to accept TCP connections before launching `vlcsync`, then sends the `stop → seek 0 → play` command burst to start every screen in lockstep.

If you ever change IPs or the RC port, edit `systemd/gradi-vlcsync-gated.user.service` in the repo, redeploy it with the script, and restart the user service (`systemctl --user restart gradi-vlcsync-gated.service`).

## 4. Boot test

1. Power-cycle both Pis (bring the worker up first so its RC socket is ready).
2. Watch `sudo journalctl -u gradi-vlc-screen0 -f` (and `gradi-vlc-screen1` on `gradi-compress`) to ensure VLC binds the RC ports without errors.
3. On `gradi-mediate`, run `journalctl --user -u gradi-vlcsync-gated -f` to confirm the controller waits for both endpoints, launches `vlcsync`, and emits the synchronized start burst.
4. Observe playback for several loops; the controller keeps issuing corrections to hold sync.

## 5. Notes

- Keep NTP enabled (`timedatectl status`) and use wired Ethernet to minimize jitter.
- Validate HEVC decode on new SD images with `scripts/phase1_validate.sh` before running the worker installer.
- Update `/etc/default/gradi-vlc-screen0` if you remap HDMI outputs or swap to new media files, then restart the service.
