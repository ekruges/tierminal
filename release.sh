#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
VERSION="$(cat VERSION)"
./install.sh --no-launch
mkdir -p dist
rm -f "dist/Tierminal-$VERSION.zip"
ditto -c -k --keepParent "$HOME/Applications/Tierminal.app" "dist/Tierminal-$VERSION.zip"
shasum -a 256 "dist/Tierminal-$VERSION.zip"
