# Beacon OS

Bonded cellular streaming OS for the Orange Pi 5 Plus (Armbian-based, librist bonding).

## Build
GitHub: Actions tab > "Build BeaconOS Image" > Run workflow. Download the image from the run's Artifacts.

## First setup on the device
1. Flash the image, boot, finish the Armbian first-login prompts.
2. `sudo beacon-pin-modems` (start with no modems plugged in), then reboot.
3. `sudo nano /etc/beacon/stream.env` and set `RIST_SERVER`.
4. `sudo tailscale up`, then `sudo tailscale serve --bg 8080`.
5. Token: `sudo grep BEACON_TOKEN /etc/beacon/env`. Enter it in the Beacon app.
