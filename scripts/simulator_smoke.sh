#!/bin/bash
set -euo pipefail
mkdir -p build/screenshots
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for devices in d["devices"].values() for x in devices if x["name"].startswith("iPhone")))')
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl install "$DEVICE" build/Build/Products/Debug-iphonesimulator/vidioi.app
xcrun simctl launch "$DEVICE" com.mostafa.vidioi
sleep 3
xcrun simctl io "$DEVICE" screenshot build/screenshots/studio.png
xcrun simctl terminate "$DEVICE" com.mostafa.vidioi
xcrun simctl launch "$DEVICE" com.mostafa.vidioi --screenshot-editor --render-smoke
sleep 5
xcrun simctl io "$DEVICE" screenshot build/screenshots/editor.png
APP_DATA=$(xcrun simctl get_app_container "$DEVICE" com.mostafa.vidioi data)
for attempt in $(seq 1 30); do
  if [ -f "$APP_DATA/Documents/smoke-result.json" ]; then break; fi
  sleep 3
done
sleep 3
xcrun simctl io "$DEVICE" screenshot build/screenshots/editor.png
cp "$APP_DATA/Documents/smoke-result.json" build/screenshots/render-result.json
python3 - "$APP_DATA/Documents/smoke-result.json" <<'PY'
import json,sys,os
result=json.load(open(sys.argv[1]))
print(result)
assert result['success'],result.get('error')
assert os.path.getsize(result['path'])>1000
PY
xcrun simctl terminate "$DEVICE" com.mostafa.vidioi
xcrun simctl launch "$DEVICE" com.mostafa.vidioi --screenshot-editor --screenshot-motion
sleep 3
xcrun simctl io "$DEVICE" screenshot build/screenshots/motion.png
xcrun simctl terminate "$DEVICE" com.mostafa.vidioi
xcrun simctl launch "$DEVICE" com.mostafa.vidioi --screenshot-ai
sleep 3
xcrun simctl io "$DEVICE" screenshot build/screenshots/connection.png
