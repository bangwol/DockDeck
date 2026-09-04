#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$REPO_DIR/build/ui-gallery}"

mkdir -p "$OUTPUT_DIR"
DOCKDECK_UI_GALLERY_DIR="$OUTPUT_DIR" \
    swift test --package-path "$REPO_DIR" -c release \
    -Xswiftc -warnings-as-errors \
    --filter ModuleGalleryTests/testRenderModuleGallery

echo "UI gallery: $OUTPUT_DIR"
