#!/usr/bin/env bash
# Hardware encode (Rockchip MPP) if available, otherwise x264 software.
. /etc/beacon/stream.env
[ -e "$VIDEO_DEV" ] || { echo "no capture device at $VIDEO_DEV"; exit 1; }

if gst-inspect-1.0 mpph264enc >/dev/null 2>&1; then
  if gst-inspect-1.0 mpph264enc | grep -q ' bps '; then RATE="bps=$((BITRATE_KBPS*1000))"; else RATE="bitrate=$((BITRATE_KBPS*1000))"; fi
  ENC="mpph264enc $RATE rc-mode=cbr gop=120"
else
  ENC="x264enc bitrate=$BITRATE_KBPS speed-preset=veryfast tune=zerolatency key-int-max=120"
fi

gst-launch-1.0 -e \
  v4l2src device="$VIDEO_DEV" ! \
  video/x-raw,width=1920,height=1080,framerate=60/1 ! videoconvert ! \
  $ENC ! h264parse config-interval=-1 ! queue ! mux. \
  alsasrc device="$AUDIO_DEV" ! audioconvert ! audioresample ! avenc_aac bitrate=160000 ! aacparse ! queue ! mux. \
  mpegtsmux name=mux ! udpsink host=127.0.0.1 port=4000 &
GST=$!

while kill -0 $GST 2>/dev/null; do
  systemd-notify WATCHDOG=1
  sleep 10
done
wait $GST
