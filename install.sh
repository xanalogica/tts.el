#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="/opt/tts-el"
DATA_DIR="/var/lib/tts-piper"
UNIT_FILE="/etc/systemd/system/tts-piper.service"

echo "🗂  Copying compose stack to $DEST_DIR"
sudo mkdir -p "$DEST_DIR"
sudo cp "$SRC_DIR/contrib/docker-compose.yml" "$DEST_DIR"

echo "🔧 Installing systemd unit"
sudo cp "$SRC_DIR/contrib/tts-piper.service" "$UNIT_FILE"
sudo chmod 644 "$UNIT_FILE"

echo "📂 Creating data directory $DATA_DIR"
sudo mkdir -p "$DATA_DIR"
sudo chown root:docker "$DATA_DIR"
sudo chmod 775 "$DATA_DIR"

echo "🐋 Pulling rhasspy/wyoming-piper image"
docker pull rhasspy/wyoming-piper:latest

echo "🎤 Pre-downloading voice models"

download_voice () {     # $1=variant  $2=voice  $3=tier
  local variant="$1" voice="$2" tier="$3"
  local base="https://huggingface.co/rhasspy/piper-voices/resolve/main"
  local dir="$DATA_DIR/${variant}_${voice}-${tier}"
  local file="${variant}-${voice}-${tier}.onnx"
  local json="${file}.json"

  echo "  -> ${variant}/${voice}/${tier}"
  echo "     ${base}/en/${variant}/${voice}/${tier}/${file}"

  sudo mkdir -p "$dir"
  curl -fL "${base}/en/${variant}/${voice}/${tier}/${file}"  -o "/tmp/$file"
  curl -fL "${base}/en/${variant}/${voice}/${tier}/${json}"  -o "/tmp/$json"
  sudo mv "/tmp/$file" "/tmp/$json" "$dir/"
}

download_voice en_US   lessac    medium
download_voice en_US   kathleen  low
download_voice en_GB   harriet   high

echo "🔄 Reloading systemd & enabling service"
sudo systemctl daemon-reload
sudo systemctl enable --now tts-piper.service

echo "✅ Install complete – Piper listens on port 10200 and models live in $DATA_DIR."
