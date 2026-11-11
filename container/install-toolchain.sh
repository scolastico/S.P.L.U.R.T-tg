#!/usr/bin/env bash
set -euo pipefail
source /tmp/dependencies.sh
mkdir -p /tmp/byond-download /opt/native
cd /tmp/byond-download
download="https://www.byond.com/download/build/${BYOND_MAJOR}/${BYOND_MAJOR}.${BYOND_MINOR}_byond_linux.zip"
if ! curl -fSL --retry 3 "$download" -o byond.zip || ! unzip -tq byond.zip; then
  curl -fSL --retry 3 "https://byond-builds.dm-lang.org/${BYOND_MAJOR}/${BYOND_MAJOR}.${BYOND_MINOR}_byond_linux.zip" -o byond.zip
fi
unzip -q byond.zip
cd byond
make here
mv /tmp/byond-download/byond /opt/byond
curl -fSL --retry 3 "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-x64.zip" -o /tmp/bun.zip
unzip -q /tmp/bun.zip -d /tmp/bun
install /tmp/bun/bun-linux-x64/bun /usr/local/bin/bun
curl -fSL --retry 3 "https://github.com/tgstation/rust-g/releases/download/${RUST_G_VERSION}/librust_g.so" -o /opt/native/librust_g.so
curl -fSL --retry 3 "https://github.com/${DREAMLUAU_REPO}/releases/download/${DREAMLUAU_VERSION}/libdreamluau.so" -o /opt/native/libdreamluau.so
LD_LIBRARY_PATH=/opt/byond/bin ldd /opt/byond/bin/DreamDaemon /opt/native/*.so | tee /tmp/native-linkages.txt
if grep -q 'not found' /tmp/native-linkages.txt; then
  echo 'A native BYOND/library dependency is missing' >&2
  exit 1
fi
rm -rf /tmp/byond-download /tmp/bun /tmp/bun.zip
