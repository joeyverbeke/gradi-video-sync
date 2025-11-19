# Gradi video sync quick start

This repo drives a VLC + `vlcsync` setup. Follow these steps for any fresh Pi or when adding screens.

## 1. Reset the Pi (run on every Pi)

```bash
cd ~/k0j0/video-sync
git pull
sudo ./scripts/reset_vlcsync_services.sh
```

## 2. Install the worker screen(s)

Front screens (HDMI 0, RC port 5001):

```bash
sudo ./scripts/install_worker_front.sh
```

Back screens (HDMI 1, RC port 5002):

```bash
sudo ./scripts/install_worker_back.sh
```

Run both commands on dual-screen Pis (e.g., `gradi-compress`). Each script honors env overrides, including audio routing via `AUDIO_DEVICE`, `SCREEN0_AUDIO_DEVICE`, or `SCREEN1_AUDIO_DEVICE`. **Pass those vars inside the sudo command** so the installer can see them.

How to pick the right audio device:
1. Plug in the speaker/headphones, then run `aplay -L`.
2. In that output, find the block whose description matches your hardware and copy the `plughw:...` or `dmix:...` line.
3. Use that value in the installer command, e.g.:

```bash
sudo AUDIO_DEVICE=dmix:CARD=GVAUDIO,DEV=0 MEDIA_FRONT=/media/videos/front.mp4 ./scripts/install_worker_front.sh
sudo SCREEN1_AUDIO_DEVICE=dmix:CARD=GVAUDIO,DEV=0 MEDIA_BACK=/media/videos/back.mp4 ./scripts/install_worker_back.sh
```

To change audio later, rerun the relevant installer with the new ALSA device value (or edit `/etc/default/gradi-vlc-screen*` and restart the matching service).

Reboot and confirm the RC ports are listening:

```bash
sudo reboot
# after reboot
systemctl status gradi-vlc-screen0
systemctl status gradi-vlc-screen1  # only if installed
ss -ltnp | grep -E ':(5001|5002)'
```

## 3. Update the controller host list

Edit `systemd/gradi-vlcsync-gated.user.service` so the `HOSTS=` line (and `--rc-host` flags) include every RC endpoint (IP:port) you want in sync.

## 4. Redeploy the controller service (run on `gradi-mediate`)

```bash
cd ~/k0j0/video-sync
./scripts/install_controller_service.sh --skip-deps
systemctl --user status gradi-vlcsync-gated
```

The controller waits for all listed RC sockets before launching `vlcsync` and issuing the synchronized start burst. Use `journalctl --user -u gradi-vlcsync-gated -f` to watch it connect.
