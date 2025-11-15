# Raspberry Pi VLC Sync Deployment Playbook

This document expands the ten formal phases in the project brief into concrete actions you can run on Raspberry Pi 5 devices that are already on Raspberry Pi OS Trixie. Follow the phases sequentially; do not skip a phase unless its verification notes have been satisfied on the hardware in question.

---

## Shared Baseline

- **Device naming** – `pi-front-a`, `pi-front-b`, `pi-back-a`, `pi-back-b`. `pi-front-a` doubles as the controller/master.
- **Displays** – two double-sided signs. Each side gets a left/right pair of synchronized screens, hence four Pis/videos.
- **Content spec**  
  - Final delivery per screen: HEVC (H.265) in MP4 container, `2160x3840` portrait orientation, 30 fps, 10‑bit not required (8‑bit is fine), square pixels, identical start/end loop trimming.  
  - Interim test files: same settings but `1440x2560` (portrait).  
  - Audio muted/stripped to avoid codec drift.  
  - File naming: `front_a.mp4`, `front_b.mp4`, `back_a.mp4`, `back_b.mp4` inside `/media/videos`.
- **Network** – all Pis on the same wired VLAN; plan on static IPs:  
  `192.168.50.21` (controller), `.22`, `.23`, `.24`. Hostnames match device names.
- **Reference repo** – [`vlc_sync_video_looper`](https://github.com/jensee-gmbh/vlc_sync_video_looper) cloned under `/opt/vlc_sync_video_looper`.

---

## Phase 1 – Hardware HEVC validation

1. **Graphics stack sanity check**
   ```bash
   sudo raspi-config nonint get_config_var dtoverlay /boot/firmware/config.txt
   ```
   Expect `vc4-kms-v3d`. If missing, append `dtoverlay=vc4-kms-v3d` and ensure `ARM_64BIT=1`. Reboot.
2. **Packages**
   ```bash
   sudo apt update
   sudo apt install -y vlc vlc-plugin-base vainfo
   ```
3. **Test asset** – Copy one HEVC MP4 to `~/Videos/test.mp4`.
4. **Manual VLC run**  
   `vlc --fullscreen --loop ~/Videos/test.mp4`  
   Enable *Video → Output = Automatic* and confirm Tools → Codec Info shows `hevc (Hardware decoding)` (vout `mmal vout`/`GLX`).
5. **Resource validation** – run `htop` and `vainfo --display drm --device /dev/dri/renderD128`. CPU load should stay <40 % aggregate; GPU decoder reported as `hevc_mpi12`.
6. **Scripted sanity check** – `./scripts/phase1_validate.sh /path/to/test.mp4` gathers overlay/package status, confirms the `rpi_hevc_dec` (or `rpivid`) kernel module is loaded, and reminds you of the manual VLC observation. On Raspberry Pi 5, the VAAPI driver currently reports a warning; rely on the module check plus the VLC codec panel for confirmation until the libva v4l2-request plugin lands in the distro.

> ✅ Verify that fullscreen playback is visually clean and the codec panel shows hardware decode. If not, fix GPU stack before continuing.

---

## Phase 2 – Layout & encoding spec

Document the following (this file already serves as the canonical reference):

- Four Raspberry Pi 5s will be cloned from one golden image. After flashing, you only need to edit the hostname and `/media/videos/video_looper.conf` (to set `VIDEO_FILE` and the worker/controller role). No other per-device tweaks should be required.
- Hostnames are fixed as `gradi-compress`, `gradi-mediate`, `gradi-predict`, and `gradi-calibrate`.
- Video filenames follow the `<concept>-<face>.mp4` convention (example: `compress-front.mp4`, `compress-back.mp4`). Each Pi pulls the file that matches its concept + whether it faces the public (“front”) or interior (“back”).

| Pi hostname       | Screen location        | Video filename (test/final)     | Notes |
|-------------------|------------------------|---------------------------------|-------|
| `gradi-compress`  | Structure A, public-facing side | `/media/videos/compress-front.mp4` | Controller Pi; workers listed here |
| `gradi-mediate`   | Structure A, rear-facing side   | `/media/videos/compress-back.mp4`  | Worker |
| `gradi-predict`   | Structure B, public-facing side | `/media/videos/predict-front.mp4`  | Worker |
| `gradi-calibrate` | Structure B, rear-facing side   | `/media/videos/predict-back.mp4`   | Worker |

- Encoding rules for all four clips: MP4 container, HEVC Main profile (libx265 or equivalent), constant 30 fps, fixed GOP length aligned to the frame rate (e.g., keyframe every 30 frames), identical duration and loop trim so the looper can restart frame-accurately, no audio track. Maintain the portrait dimensions: 1440 × 2560 for tests, 2160 × 3840 for final.
- Keep total duration divisible by an integer number of frames at 30 fps (e.g., 90 s → 2700 frames) to avoid fractional frame loops.
- Production handoff: deliver both the portrait 1440p test set and the 2160p final set together so swapping files is a copy/restart operation.

Ask the human reviewer to sign off on the above spec before encoding new media.

---

## Phase 3 – Single-Pi autoplay prototype

1. **Run the helper script**:
   ```bash
   sudo VIDEO_FILE=/home/pi/Desktop/compress-1.mp4 ./scripts/phase3_setup.sh
   ```
   - Defaults: enables desktop auto-login for `$TARGET_USER` (defaults to the user invoking sudo), writes `~/.config/autostart/vlc-loop.desktop`, and disables blanking via `raspi-config`.
   - Override `VIDEO_FILE` when pointing at `/media/videos/<concept>-<face>.mp4` once Phase 4 is done.
2. **What the script does** (for auditing or manual replication):
   - Calls `raspi-config nonint do_boot_behaviour B4` to auto-login.
   - Calls `raspi-config nonint do_blanking 1` to keep the display awake.
   - Creates an autostart entry that disables DPMS via `xset` and launches VLC fullscreen looping the requested file.
3. **Manual validation** – after the script runs, reboot (`sudo reboot`). The desktop session should auto-login and launch VLC into a fullscreen loop with no blanking. If it doesn’t, inspect `~/.config/autostart/vlc-loop.desktop` and rerun the script with corrected environment variables.

---

## Phase 4 – `/media/videos` content mount

1. **Run the helper** (pass the partition you want to dedicate to content):
   ```bash
   sudo DEVICE=/dev/mmcblk0p3 FSTYPE=ext4 VIDEO_FILE=/media/videos/compress-front.mp4 ./scripts/phase4_prepare_media.sh
   ```
   - Formats the partition, adds it to `/etc/fstab`, mounts `/media/videos`, copies any existing demo clip, and rewrites `~/.config/autostart/vlc-loop.desktop` so VLC pulls from the mounted path.
   - Defaults assume ext4; set `FSTYPE=exfat` if you need removable-media compatibility.
2. **Manual adjustments**:
   - If you already have a formatted partition, skip the `mkfs` command by pre-mounting `/media/videos` and then running `rsync` manually; update `/etc/fstab` to keep it persistent.
   - Confirm the autostart file now references `/media/videos/<concept>-<face>.mp4`.
3. **Validation** – reboot. VLC should start automatically and play the file stored under `/media/videos`. Swap the media file and reboot to ensure the new content loads without additional changes.

---

## Phase 5 – Introduce VLC Sync Video Looper

1. **Install**:
   ```bash
   sudo apt install -y git python3-venv
   sudo mkdir -p /opt/vlc_sync_video_looper
   sudo git clone git@github.com:dreerr/vlc_sync_video_looper.git /opt/vlc_sync_video_looper
   cd /opt/vlc_sync_video_looper && sudo ./install.sh
   ```
   This drops `vlc_sync_video_looper.service`.
2. **Config** – `/media/videos/video_looper.conf` (controller local-only mode):
   ```ini
   [GENERAL]
   MODE=controller
   MEDIA_DIR=/media/videos
   VIDEO_FILE=front_a.mp4
   SCREEN=0
   STARTUP_DELAY=2

   [NETWORK]
   WORKERS=
   BROADCAST_PORT=5000

   [VLC]
   EXTRA_OPTS=--no-video-title-show --fullscreen
   ```
3. **Enable service** – `sudo systemctl enable --now vlc_sync_video_looper.service`
4. **Disable autostart** – remove `vlc-loop.desktop`.
5. Human reboot confirms service brings up VLC automatically.

---

## Phase 6 – Swap in 1440p spec media

- Copy approved `1440x2560` HEVC files into `/media/videos`, matching filenames per Pi.
- `sudo systemctl restart vlc_sync_video_looper` after each copy. Watch `journalctl -u vlc_sync_video_looper -f` for decoder logs. Confirm clean loops.
- Later, swap to `2160x3840` masters the same way.

---

## Phase 7 – Network/time prep for four Pis

1. **Static addressing** – either via router DHCP reservations or `/etc/dhcpcd.conf` overrides:
   ```
   interface eth0
   static ip_address=192.168.50.21/24
   static routers=192.168.50.1
   static domain_name_servers=192.168.50.1
   ```
2. **Hostname** – `sudo hostnamectl set-hostname pi-front-a` (etc.).
3. **Connectivity test** – from each Pi: `for host in pi-front-a pi-front-b pi-back-a pi-back-b; do ping -c2 $host; done`
4. **Clock sync** – ensure `systemd-timesyncd` is active:
   ```bash
   timedatectl set-ntp true
   timedatectl status
   ```
5. Record the final IP ↔ hostname mapping back in this doc for quick reference.

---

## Phase 8 – Two-Pi synchronization test

1. Clone the Phase 6 setup onto `pi-front-b`.
2. **Controller config** (`pi-front-a`):
   ```ini
   MODE=controller
   WORKERS=192.168.50.22:6001
   VIDEO_FILE=front_a.mp4
   ```
3. **Worker config** (`pi-front-b`):
   ```ini
   MODE=worker
   CONTROLLER=192.168.50.21:6001
   VIDEO_FILE=front_b.mp4
   ```
   Workers still need a local file; the looper keeps them frame-aligned via timestamp beacons.
4. Enable service on both Pis and `sudo journalctl -u vlc_sync_video_looper -f` while restarting to confirm handshake.
5. Reboot both devices close together. Observe sync with the naked eye and by recording slo‑mo video if needed.

Troubleshooting tips:
- Ports blocked? Use `ss -ltnp | grep 6001`.
- Clock skew? `chronyc tracking` or `timedatectl show -p NTPSynchronized`.

---

## Phase 9 – Expand to four Pis

1. Ensure each Pi has its own `/media/videos/<file>.mp4`.
2. Controller config adds all workers:
   ```ini
   WORKERS=192.168.50.22:6001,192.168.50.23:6001,192.168.50.24:6001
   ```
3. Each worker uses `MODE=worker`, `CONTROLLER=192.168.50.21:6001`, and its own `VIDEO_FILE`.
4. Double-check firewall (if any) allows UDP/TCP as per the looper docs.
5. Power-cycle all Pis via a power strip. Confirm all four screens reach playback within ~30 s and remain within sync tolerance over at least ten loops.

---

## Phase 10 – Kiosk hardening & imaging

1. **Disable distractions** – turn off update popups: `sudo apt remove -y update-notifier`, disable GNOME notifications via `gsettings set org.gnome.desktop.notifications show-banners false`.
2. **Screen blanking** – already disabled, but confirm via `xset -q` (DPMS off) and `/etc/xdg/lxsession/LXDE-pi/autostart` if LXDE is in use.
3. **Power-fail testing** – human pulls power mid-loop several times to ensure clean recovery.
4. **Clone master SD**  
   - Shutdown master cleanly.  
   - Use `sudo dd if=/dev/sdX of=~/pi-front-a-golden.img bs=16M status=progress` on a workstation.  
   - Compress with `xz -T0`.  
   - Flash to other cards via `raspi-imager` or `dd` (`sudo xzcat *.img.xz | sudo dd of=/dev/sdY bs=16M status=progress && sync`).
5. **Per-device tweaks after cloning** – change hostname/IP (`hostnamectl`, `dhcpcd.conf`), update `/media/videos/video_looper.conf` `MODE`/`VIDEO_FILE`, and regenerate SSH host keys: `sudo rm /etc/ssh/ssh_host_* && sudo dpkg-reconfigure openssh-server`.
6. **Soak test** – run all four for ≥6 hours, include at least one cold boot and one abrupt power cut. Watch `journalctl -u vlc_sync_video_looper` for errors.

---

## Verification log

Use the following template (copy per device) once phases are ticked off:

| Phase | Device(s) | Date | Evidence/Notes |
|-------|-----------|------|----------------|
| 1 | pi-front-a | | |
| 2 | all | | |
| … | | | |
| 10 | all | | |

Maintaining this log keeps the rollout auditable when cloning to new Pis later.
