#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"

: "${INGEST_URL:?}" "${YT_KEY_1:?}" "${YT_KEY_2:?}" "${LOOP_URL:?}"

# رابط راديو الشيخ أحمد العجمي
RADIO_URL="https://qurango.net/radio/ahmad_alajmy"
PORT=8000

EXTRA_PARAM=""
if [ "${IS_BACKUP:-false}" = "true" ]; then
  EXTRA_PARAM="?backup=1"
fi

trap 'kill 0' TERM INT

curl -fL --retry 5 --retry-delay 3 -o /tmp/loop4k.mp4 "$LOOP_URL" || { echo "تحميل الفيديو فشل"; exit 1; }

mkdir -p backup
cat > /tmp/quran.liq <<EOF
radio  = input.http("${RADIO_URL}")
backup = playlist(mode="randomize", "$PWD/backup")
s = fallback(track_sensitive=false, [radio, backup, blank()])
output.harbor(%mp3(bitrate=192), mount="/quran", port=${PORT}, s)
EOF
liquidsoap /tmp/quran.liq > /tmp/liq.log 2>&1 &

for i in $(seq 1 30); do
  code=$(curl -s -m 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/quran")
  [ "$code" = "200" ] && break
  sleep 1
done

stream() {
  local ch_name="$1"
  local stream_key="$2"
  local target_url="${INGEST_URL}/${stream_key}${EXTRA_PARAM}"

  while true; do
    : > "/tmp/prog_${ch_name}.txt"
    ffmpeg -hide_banner -loglevel warning -nostats -progress "/tmp/prog_${ch_name}.txt" \
      -re -stream_loop -1 -i /tmp/loop4k.mp4 \
      -thread_queue_size 1024 -i "http://127.0.0.1:${PORT}/quran" \
      -map 0:v:0 -map 1:a:0 \
      -c:v copy -c:a aac -b:a 192k -ar 48000 -ac 2 -af aresample=async=1000 \
      -f flv "$target_url"
    echo "[$ch_name] ffmpeg وقع، إعادة تشغيل بعد ثانيتين"
    sleep 2
  done
}

stream ch1 "$YT_KEY_1" &
stream ch2 "$YT_KEY_2" &
wait
