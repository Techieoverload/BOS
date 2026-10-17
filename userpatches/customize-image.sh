#!/bin/bash
# Runs inside the image chroot during the Armbian build.
RELEASE=$1; LINUXFAMILY=$2; BOARD=$3; BUILD_DESKTOP=$4

Main() {
  export DEBIAN_FRONTEND=noninteractive
  O=/tmp/overlay

  apt-get update
  apt-get install -y --no-install-recommends \
    network-manager modemmanager usb-modeswitch python3 curl ca-certificates \
    build-essential meson ninja-build git cmake pkg-config libmbedtls-dev \
    libdrm-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-alsa

  # --- librist (bonding) ---
  git clone --depth 1 https://code.videolan.org/rist/librist.git /tmp/librist
  meson setup /tmp/librist/build /tmp/librist
  ninja -C /tmp/librist/build install
  ldconfig
  ldd /usr/local/bin/ristsender | grep "not found" && { echo "ristsender missing libs"; exit 1; }

  # --- Rockchip MPP + GStreamer plugin (hardware encoder). Non-fatal: encoder.sh falls back to x264 ---
  (
    set -e
    git clone --depth 1 https://github.com/rockchip-linux/mpp /tmp/mpp
    cmake -S /tmp/mpp -B /tmp/mpp/build -DRKPLATFORM=ON -DHAVE_DRM=ON
    cmake --build /tmp/mpp/build -j"$(nproc)"
    cmake --install /tmp/mpp/build
    ldconfig
    git clone --depth 1 -b gstreamer-rockchip https://github.com/JeffyCN/mirrors /tmp/gst-rk
    meson setup /tmp/gst-rk/build /tmp/gst-rk
    ninja -C /tmp/gst-rk/build install
    ldconfig
  ) || echo "WARNING: Rockchip MPP/GStreamer plugin build failed; image will use x264 software encoding"

  # --- Tailscale ---
  curl -fsSL https://tailscale.com/install.sh | sh || echo "WARNING: tailscale install failed"

  # --- Beacon files ---
  install -d /opt/beacon /etc/beacon
  install -m755 $O/beacon-server.py /opt/beacon/
  install -m755 $O/encoder.sh /usr/local/bin/encoder.sh
  install -m755 $O/beacon-firstboot.sh /usr/local/bin/beacon-firstboot.sh
  install -m755 $O/beacon-pin-modems.sh /usr/local/bin/beacon-pin-modems
  install -m755 -o root -g root $O/90-wan-routing /etc/NetworkManager/dispatcher.d/90-wan-routing
  install -m644 $O/90-multiwan.conf /etc/sysctl.d/90-multiwan.conf
  install -m644 $O/stream.env /etc/beacon/stream.env
  install -m644 -t /etc/systemd/system $O/beacon-ui.service $O/beacon-firstboot.service $O/rist-sender.service $O/gst-encoder.service
  echo "beacon" > /etc/hostname

  # Only the UI backend starts automatically. The panel's Go Live button starts the stream.
  systemctl enable beacon-firstboot beacon-ui NetworkManager ModemManager tailscaled || true

  # --- Cleanup ---
  rm -rf /tmp/librist /tmp/mpp /tmp/gst-rk
  apt-get clean
  rm -rf /var/lib/apt/lists/*
}
Main "$@"
