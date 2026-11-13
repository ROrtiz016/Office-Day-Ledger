#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

swift build -c release

APP_DIR="$ROOT_DIR/build/OfficeDayCounter.app"
mkdir -p "$APP_DIR/Contents/MacOS"
cp .build/release/OfficeDayCounter "$APP_DIR/Contents/MacOS/OfficeDayCounter"
cp Info.plist "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR"

printf 'Built %s\n' "$APP_DIR"