#!/usr/bin/env sh
set -e

# OmniLux container entrypoint
# 0. Fix data directory ownership when the mounted dataset permits it
# 1. Ensure optional ingestion workspace directories exist
# 2. Start the Node.js application

# Ensure the runtime paths are writable before dropping privileges.
if [ -d /app/data ] && [ ! -w /app/data ] 2>/dev/null; then
  echo "[init] Fixing data directory permissions..."
  chown -R "$(id -u):$(id -g)" /app/data 2>/dev/null || true
fi

# Ensure media ingestion workspace directories are writable.
INGESTION_DIR="/app/media-ingestion"
mkdir -p "$INGESTION_DIR/raw" "$INGESTION_DIR/temp" "$INGESTION_DIR/transcode" "$INGESTION_DIR/downloads" 2>/dev/null || true
chown -R omnilux:omnilux "$INGESTION_DIR" /app/data /app/plugins 2>/dev/null || true

# Start the application
echo "[server] Starting OmniLux..."
exec su -s /bin/sh omnilux -c 'node apps/server/dist/index.js'
