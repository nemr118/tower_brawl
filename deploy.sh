#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "⚡ [1/2] Exporting Godot project to Web..."
mkdir -p build/web
godot --headless --export-release "Web" "$PROJECT_DIR/build/web/index.html"

LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' || echo "127.0.0.1")

echo ""
echo "═"*60
echo "🚀 [2/2] EXPORT SUCCESSFUL!"
echo "👉 Wife / Kids can open: http://$LOCAL_IP:8000"
echo "═"*60
