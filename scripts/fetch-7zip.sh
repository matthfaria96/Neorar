#!/bin/sh
# Downloads the official 7-Zip console build for macOS (universal) into Vendor/.
set -eu
cd "$(dirname "$0")/.."

VERSION="26.04"
FILE="7z2604-mac.tar.xz"
SHA256="bee04358cbcbc7106273cee0e8d72916db2696c48067a3538c34d8cd6fd16578"
URL="https://github.com/ip7z/7zip/releases/download/${VERSION}/${FILE}"

if [ -x Vendor/7zz ] && Vendor/7zz | grep -q "7-Zip (z) ${VERSION}"; then
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "Baixando 7-Zip ${VERSION}…"
curl -fsSL -o "$WORK/$FILE" "$URL"
echo "${SHA256}  $WORK/$FILE" | shasum -a 256 -c - >/dev/null
tar -xJf "$WORK/$FILE" -C "$WORK"
mkdir -p Vendor
cp "$WORK/7zz" Vendor/7zz
cp "$WORK/License.txt" Vendor/7-Zip-License.txt
chmod 755 Vendor/7zz
echo "7-Zip ${VERSION} pronto em Vendor/7zz"
