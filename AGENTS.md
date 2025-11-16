# Repository Guidelines

## Response Style
- When responding to user chat prioritize clearness, simplicity, and succinctness

## Project Structure & Module Organization
- `docs/` – reference material, e.g., `minimal_vlcsync_reset.md` for the current two-Pi / three-screen playbook.
- `scripts/` – automation helpers such as `install_worker_units.sh` (generic screen installer), `install_worker_front.sh`, `install_worker_back.sh`, and `install_controller_service.sh`.
- Future Raspberry Pi assets (configs, service files, media notes) should live under `docs/` or `scripts/` unless they are binary media, which belong in `/media/videos` on-device, not in Git.

## Build, Test, and Development Commands
- `sudo ./scripts/reset_vlcsync_services.sh` – wipes prior VLC/looper services before installing the new stack.
- `sudo ./scripts/install_worker_front.sh` / `sudo ./scripts/install_worker_back.sh` – provision the front (screen0/5001) or back (screen1/5002) VLC services with fixed defaults (overridable via env vars).
- `sudo ./scripts/install_worker_units.sh ...` – fall back to the generic installer for bespoke layouts.
- `./scripts/install_controller_service.sh [--skip-deps]` – deploy (or redeploy) the gated `vlcsync` controller as the logged-in user.
- `LIBVA_DRIVER_NAME=v4l2_request vainfo --display drm --device /dev/dri/renderD128` – optional sanity check that VAAPI advertises HEVC (expected to warn on Pi 5 until libva gains the request driver).
- Use SSH URLs when cloning (`git clone git@github.com:...`) to stay aligned with the repo policy.

## Coding Style & Naming Conventions
- Shell scripts: POSIX/Bash, `set -euo pipefail`, 2-space indentation, descriptive function names (`log_section`, `check_file_contains`).
- Documentation: Markdown with sentence-case headings, inline code for commands (`sudo raspi-config ...`) and backtick-wrapped filenames.
- Device/video naming follows the `gradi-*` hostnames plus the `front.mp4` (screen0/5001) and `back.mp4` (screen1/5002) media scheme captured in `docs/minimal_vlcsync_reset.md`.

## Testing Guidelines
- Scripts should include self-check output (e.g., pass/warn/fail summaries) and exit non-zero on critical failures.
- Manual verification (VLC playback, CPU observation) must be recorded in whatever verification log we carry forward in `docs/minimal_vlcsync_reset.md` or its successors.
- When adding new automation, provide a dry-run mode or clear instructions for running on a Raspberry Pi via SSH.

## Commit & Pull Request Guidelines
- Use conventional, action-oriented commit messages (`docs: update phase 2 layout spec`, `scripts: add sync health probe`).
- Pull requests should describe the phase or feature targeted, list manual test evidence (e.g., `install_worker_units.sh` output), and link any tracking issues.
- Include screenshots or command snippets when they clarify hardware tests; omit binary media from Git—reference paths under `/media/videos` instead.
