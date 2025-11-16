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

Run both commands on dual-screen Pis (e.g., `gradi-compress`). Each script honors env overrides (the back helper adds `--no-audio` by default):

```bash
sudo MEDIA_FRONT=/media/videos/custom_front.mp4 RUN_USER=pi ./scripts/install_worker_front.sh
sudo MEDIA_BACK=/media/videos/custom_back.mp4 SCREEN1_EXTRA_ARGS="" RUN_USER=pi ./scripts/install_worker_back.sh
```

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
