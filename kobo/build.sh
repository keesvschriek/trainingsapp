#!/bin/sh
# Bouwt kees-study-kobo.zip met dezelfde mappen als op de Kobo.
# Gebruik vanuit de hoofdmap van de repo: sh kobo/build.sh
set -e
OUT=${1:-kees-study-kobo.zip}
TMP=$(mktemp -d)
npx tsx scripts/export-kobo.ts kobo/app/data
npx tsx scripts/export-kobo-map.ts kobo/app/data
mkdir -p "$TMP/.adds/keesstudy" "$TMP/.adds/koreader/patches" "$TMP/.adds/nm" "$TMP/extra/kfmon/.adds/kfmon/config" "$TMP/extra/kfmon/.adds/keesstudy"
cp -r kobo/app "$TMP/.adds/keesstudy/app"
echo "$(date -u +%Y-%m-%d)-$(git rev-parse --short HEAD 2>/dev/null || echo lokaal)" > "$TMP/.adds/keesstudy/app/version.txt"
cp kobo/install/patches/2-kees-study.lua "$TMP/.adds/koreader/patches/"
cp kobo/install/nm/kees_study "$TMP/.adds/nm/"
cp kobo/install/start.sh "$TMP/extra/kfmon/.adds/keesstudy/"
cp kobo/install/kfmon/keesstudy.ini "$TMP/extra/kfmon/.adds/kfmon/config/"
cp kobo/install/kees-study.png "$TMP/extra/kfmon/" 2>/dev/null || true
cp kobo/LEESMIJ.txt "$TMP/LEESMIJ-kees-study.txt"
rm -f "$OUT"
(cd "$TMP" && zip -qr - .) > "$OUT"
rm -rf "$TMP"
echo "klaar: $OUT"
