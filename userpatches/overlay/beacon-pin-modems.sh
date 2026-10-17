#!/bin/bash
# Run as root with NO modems plugged in. Pins each modem USB port to a stable name.
set -e
list() { ls /sys/class/net | grep -vE '^(lo|wlan.*|docker.*|tailscale.*|modem[0-9]|wan-eth)$' | sort; }
pathof() { udevadm info "/sys/class/net/$1" | sed -n 's/^E: ID_PATH=//p'; }

for n in 1 2 3 4; do
  before=$(list)
  read -rp "Plug in modem $n ONLY, then press Enter... "
  sleep 8
  new=$(comm -13 <(echo "$before") <(list) | head -n1)
  [ -z "$new" ] && { echo "No new interface found, skipping modem $n"; continue; }
  p=$(pathof "$new")
  printf '[Match]\nPath=%s\nType=ether\n\n[Link]\nName=modem%s\n' "$p" "$n" > /etc/systemd/network/10-modem$n.link
  echo "modem$n -> $new ($p)"
done

ip -br link
read -rp "Name of the Ethernet port to use as LAN (e.g. enP4p65s0), blank to skip: " lan
if [ -n "$lan" ]; then
  p=$(pathof "$lan")
  printf '[Match]\nPath=%s\nType=ether\n\n[Link]\nName=wan-eth\n' "$p" > /etc/systemd/network/10-wan-eth.link
  echo "wan-eth -> $lan ($p)"
fi
echo "Done. Reboot to apply the new names."
