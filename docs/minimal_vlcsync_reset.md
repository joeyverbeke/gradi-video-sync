# Minimal VLC + vlcsync reset

This guide resets the in-progress deployment to the minimal “two Pis, three screens” layout. The Pi you are currently logged into (`gradi-mediate`) is both a player and the `vlcsync` controller. The second Pi (`gradi-compress` at `192.168.0.9`) is a worker that now drives **two** HDMI outputs.

## Targets and naming

- **Hostnames & IPs**

  | Hostname        | IP address    | Role / screens            | Expected media files |
  |-----------------|---------------|---------------------------|----------------------|
  | `gradi-mediate` | `192.168.0.4` | Controller + HDMI 0 (front) | `/media/videos/front.mp4` |
  | `gradi-compress` | `192.168.0.9` | Worker + HDMI 0 (front) & HDMI 1 (back) | `/media/videos/front.mp4` (screen 0), `/media/videos/back.mp4` (screen 1) |

- **Media naming** – keep `/media/videos/front.mp4` for every front-facing screen (RC port 5001) and `/media/videos/back.mp4` for every back-facing screen (RC port 5002). Override via env vars if a Pi needs different filenames.
- **RC ports** – front screens always listen on TCP `5001`, back screens on TCP `5002`.

## 1. Clean up legacy services on both Pis

Run the reset helper locally on each Pi. It removes the old looper/systemd units and desktop autostarts, then kills any leftover VLC processes.

```bash
sudo ./scripts/reset_vlcsync_services.sh
```

Set `DRY_RUN=1` if you first want to see which units would be touched (`DRY_RUN=1 sudo ./scripts/reset_vlcsync_services.sh`). The script is idempotent; rerun it if you suspect a Pi still has stray units.

## 2. Install the worker VLC unit

Use the dedicated helpers so you only configure the screen you care about:

```bash
# gradi-mediate (front screen only)
sudo ./scripts/install_worker_front.sh

# gradi-compress (two screens)
sudo ./scripts/install_worker_front.sh   # HDMI 0 / front.mp4 / port 5001
sudo ./scripts/install_worker_back.sh    # HDMI 1 / back.mp4 / port 5002
```

Each helper honors optional env overrides if you need a different filename, screen index, RC port, run user, **or audio target**. Set one of `AUDIO_DEVICE`, `SCREEN0_AUDIO_DEVICE`, or `SCREEN1_AUDIO_DEVICE` to an ALSA/Pulse endpoint (e.g., `dmix:CARD=ATHM50xSTSUSB,DEV=0` for the USB headset currently plugged into `gradi-compress`) so both VLC workers can feed the same speaker:

```bash
AUDIO_DEVICE=dmix:CARD=ATHM50xSTSUSB,DEV=0 sudo MEDIA_FRONT=/media/videos/custom_front.mp4 RUN_USER=pi ./scripts/install_worker_front.sh
SCREEN1_AUDIO_DEVICE=dmix:CARD=ATHM50xSTSUSB,DEV=0 sudo MEDIA_BACK=/media/videos/custom_back.mp4 RUN_USER=pi ./scripts/install_worker_back.sh
```

Under the hood the helpers call `install_worker_units.sh`, so you can still run it directly for bespoke cases (use `--screen0-only`/`--screen1-only` plus the existing flags such as `--extra-args`, `--screen1-extra-args`, and `--xdisplay`).

After the script runs, `systemctl status gradi-vlc-screen0` should show VLC looping (it will sit black until the media file exists).

## 3. Install the gated `vlcsync` controller on `gradi-mediate`

Run the controller helper as the non-root user that should own the service (default `pi`):

```bash
# fresh install
./scripts/install_controller_service.sh

# redeploy after editing the host list
./scripts/install_controller_service.sh --skip-deps
```

The script installs `vlcsync` via `pip --user`, deploys `systemd/gradi-vlcsync-gated.user.service` into `~/.config/systemd/user`, and enables lingering so the user service stays up after logout. The service waits for all three RC sockets (`192.168.0.4:5001`, `192.168.0.9:5001`, and `192.168.0.9:5002`) to accept TCP connections before launching `vlcsync`, then sends the `stop → seek 0 → play` command burst to start every screen in lockstep.

If you ever change IPs or add a screen, update `systemd/gradi-vlcsync-gated.user.service` in the repo, then rerun the helper (use `--skip-deps` for a fast redeploy). It will copy the file, reload the user daemon, and restart the service for you.

## 4. Boot test

1. Power-cycle both Pis (bring the worker up first so its RC socket is ready).
2. Watch `sudo journalctl -u gradi-vlc-screen0 -f` (and `gradi-vlc-screen1` on `gradi-compress`) to ensure VLC binds the RC ports without errors.
3. On `gradi-mediate`, run `journalctl --user -u gradi-vlcsync-gated -f` to confirm the controller waits for both endpoints, launches `vlcsync`, and emits the synchronized start burst.
4. Observe playback for several loops; the controller keeps issuing corrections to hold sync.

## 5. Notes

- Keep NTP enabled (`timedatectl status`) and use wired Ethernet to minimize jitter.
- Validate HEVC decode on new SD images (run a quick VLC manual test) before invoking the worker installers.
- Update `/etc/default/gradi-vlc-screen0` or `/etc/default/gradi-vlc-screen1` if you remap HDMI outputs, swap to new media files, or point VLC at a different speaker. Restart the relevant service after editing.
