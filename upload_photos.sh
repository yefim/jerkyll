#!/usr/bin/env bash

# Usage:
#   ./upload_photos.sh <folder> [--date yyyy-mm-dd]
# Requires: Bash 4+, exiftool, fd, jq, yq (Mike Farah v4), shasum,
# ImageMagick (magick), awk.
# Commit _photo_uploads.json alongside your shoots to retain upload history.

set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: $0 <folder> [--date yyyy-mm-dd]"
  exit 0
fi

if [ $# -lt 1 ]; then
  echo "Usage: $0 <folder> [--date yyyy-mm-dd]"
  exit 1
fi

DIR="$1"
shift

if [[ ! -d "$DIR" ]]; then
  echo "Error: not a directory: $DIR" >&2
  exit 1
fi
DIR=$(cd -- "$DIR" && pwd -P)

TARGET_DATE=""

# Parse optional args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --date)
      TARGET_DATE="${2:-}"
      if [[ ! "$TARGET_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] ||
         [[ $(date -j -f "%Y-%m-%d" "$TARGET_DATE" "+%Y-%m-%d" 2>/dev/null) != "$TARGET_DATE" ]]; then
        echo "Error: --date must be a valid yyyy-mm-dd date" >&2
        exit 1
      fi
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

for dependency in exiftool fd jq yq shasum magick awk; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "Error: required command not found: $dependency" >&2
    exit 1
  fi
done

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
HISTORY_FILE="$SCRIPT_DIR/_photo_uploads.json"
LOCK_DIR="$SCRIPT_DIR/.photo-upload.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Error: another photo upload is running. If a run was killed, remove $LOCK_DIR before retrying." >&2
  exit 1
fi
WORK_DIR=""
cleanup() {
  [[ -z "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"
  rmdir "$LOCK_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Use the repo's filesystem so mv replaces history and shoot files atomically.
WORK_DIR=$(mktemp -d "$SCRIPT_DIR/.photo-upload.XXXXXX")
[[ -f "$HISTORY_FILE" ]] || printf '{}\n' > "$HISTORY_FILE"
jq -e 'type == "object"' "$HISTORY_FILE" >/dev/null

calculate_metadata() {
  local photo="$1" dimensions width height hash
  dimensions=$(magick "${photo}[0]" -auto-orient -format '%w %h' info:) || return
  read -r width height <<< "$dimensions"
  # Encode a small, oriented RGB thumbnail with 4 x 3 BlurHash components.
  # Algorithm: https://github.com/woltapp/blurhash/blob/master/Algorithm.md
  hash=$(magick "${photo}[0]" -auto-orient -thumbnail '32x32>' -colorspace sRGB \
    -background white -alpha remove -alpha off -depth 8 txt:- | awk '
    function abs(v) { return v < 0 ? -v : v }
    function clamp(v, low, high) { return v < low ? low : (v > high ? high : v) }
    function linear(v) { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055)^2.4 }
    function srgb(v) {
      v = clamp(v, 0, 1)
      return int(255 * (v <= 0.0031308 ? v * 12.92 : 1.055 * v^(1 / 2.4) - 0.055) + 0.5)
    }
    function base83(v, digits, result, i, divisor) {
      result = ""
      for (i = digits - 1; i >= 0; i--) {
        divisor = 83^i
        result = result substr(alphabet, int(v / divisor) % 83 + 1, 1)
      }
      return result
    }
    BEGIN {
      alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~"
      pi = atan2(0, -1)
    }
    NR == 1 {
      sub(/^.*: /, "")
      split($0, size, ",")
      width = size[1]; height = size[2]
      next
    }
    {
      gsub(/[:,()]/, " ")
      for (c = 0; c < 3; c++) pixels[$1, $2, c] = linear($(c + 3))
      count++
    }
    END {
      if (width <= 0 || height <= 0 || count != width * height) exit 1
      for (cy = 0; cy < 3; cy++) for (cx = 0; cx < 4; cx++) {
        component = cy * 4 + cx
        normalisation = component == 0 ? 1 : 2
        for (y = 0; y < height; y++) for (x = 0; x < width; x++) {
          basis = cos(pi * cx * x / width) * cos(pi * cy * y / height)
          for (c = 0; c < 3; c++) factors[component, c] += basis * pixels[x, y, c]
        }
        for (c = 0; c < 3; c++) {
          factors[component, c] *= normalisation / (width * height)
          if (component > 0 && abs(factors[component, c]) > maximum) maximum = abs(factors[component, c])
        }
      }
      quantised = clamp(int(maximum * 166 - 0.5), 0, 82)
      scale = (quantised + 1) / 166
      dc = srgb(factors[0, 0]) * 65536 + srgb(factors[0, 1]) * 256 + srgb(factors[0, 2])
      hash = base83(21, 1) base83(quantised, 1) base83(dc, 4)
      for (component = 1; component < 12; component++) {
        ac = 0
        for (c = 0; c < 3; c++) {
          value = factors[component, c]
          signed_root = sqrt(abs(value) / scale) * (value < 0 ? -1 : 1)
          ac = ac * 19 + clamp(int(signed_root * 9 + 9.5), 0, 18)
        }
        hash = hash base83(ac, 2)
      }
      print hash
    }') || return
  jq -n --argjson width "$width" --argjson height "$height" --arg blurhash "$hash" \
    '{width: $width, height: $height, blurhash: $blurhash}'
}

save_upload() {
  jq --arg fingerprint "$fingerprint" --argjson entry "$entry" \
    '.[$fingerprint] = $entry' "$HISTORY_FILE" > "$WORK_DIR/history.json"
  mv "$WORK_DIR/history.json" "$HISTORY_FILE"
}

update_shoot() {
  # Upgrade matching scalar IDs, merge metadata in place, or prepend a new image.
  # Front-matter mode preserves the Markdown body; merge keeps custom captions.
  PHOTO_ENTRY="$entry" yq --exit-status --front-matter=process '
    select(tag == "!!map" and (.images == null or (.images | tag) == "!!seq")) |
    (env(PHOTO_ENTRY) | ... style = "") as $photo |
    .images = (.images // []) |
    (.images[] | select(. == $photo.id)) = $photo |
    (.images[] | select(.id == $photo.id)) *= $photo |
    with(select([.images[] | select(.id == $photo.id)] | length == 0);
      .images = [$photo] + .images
    )
  ' "$doc" > "$WORK_DIR/shoot.md"
  if ! cmp -s "$doc" "$WORK_DIR/shoot.md"; then
    mv "$WORK_DIR/shoot.md" "$doc"
  fi
}

# -----------------------------
# 1. Build map: filepath → YYYY-MM-DD
#    using *one* exiftool call
# -----------------------------

declare -A FILE_DATES

exiftool -fast -json -DateTimeOriginal -d '%Y-%m-%d' -r \
  -ext jpg -ext jpeg -ext png -ext heic "$DIR" > "$WORK_DIR/exif.json"
if [[ -s "$WORK_DIR/exif.json" ]]; then
  jq -j '.[] | .SourceFile, "\u0000", (.DateTimeOriginal // ""), "\u0000"' \
    "$WORK_DIR/exif.json" > "$WORK_DIR/dates"
  while IFS= read -r -d '' path && IFS= read -r -d '' ymd; do
    [[ "$ymd" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && FILE_DATES["$path"]="$ymd"
  done < "$WORK_DIR/dates"
fi

# -----------------------------
# 2. Iterate files (skip if no EXIF date)
# -----------------------------

fd -0 --type f --absolute-path -e jpg -e jpeg -e png -e heic . "$DIR" > "$WORK_DIR/files"
uploaded=0
while IFS= read -r -d '' f; do
  ymd="${FILE_DATES["$f"]:-}"

  # Skip files with no EXIF date
  if [[ -z "$ymd" ]]; then
    echo "Skipping $f (no EXIF date)"
    continue
  fi

  # Apply --date filter
  if [[ -n "$TARGET_DATE" && "$ymd" != "$TARGET_DATE" ]]; then
    continue
  fi

  fingerprint=$(shasum -a 256 < "$f")
  fingerprint="${fingerprint%% *}"
  entry=$(jq -c --arg fingerprint "$fingerprint" '.[$fingerprint]' "$HISTORY_FILE")
  if jq -e --arg fingerprint "$fingerprint" 'has($fingerprint)' "$HISTORY_FILE" >/dev/null; then
    jq -e 'type == "object" and (.id | type == "string" and length > 0)' <<< "$entry" >/dev/null
    echo "Reusing $f (date: $ymd)…"
    if ! jq -e '(.width | type == "number" and . > 0) and
                (.height | type == "number" and . > 0) and
                (.blurhash | type == "string" and length == 28)' <<< "$entry" >/dev/null; then
      metadata=$(calculate_metadata "$f")
      entry=$(jq --argjson metadata "$metadata" '. + $metadata' <<< "$entry")
      save_upload
    fi
  else
    : "${CF_API_TOKEN:?Set CF_API_TOKEN before uploading new photos}"
    : "${CF_ACCOUNT_ID:?Set CF_ACCOUNT_ID before uploading new photos}"
    metadata=$(calculate_metadata "$f")
    echo "Uploading $f (date: $ymd)…"
    # Quote the path for curl’s form parser, including commas and semicolons.
    form_path="${f//\\/\\\\}"
    form_path="${form_path//\"/\\\"}"
    id=$(curl --fail --silent --show-error --connect-timeout 30 --max-time 300 -X POST \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -F "file=@\"${form_path}\"" \
      "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/images/v1" \
      | jq -er 'select(.success == true) | .result.id | select(type == "string" and length > 0)')
    entry=$(jq --arg id "$id" '{id: $id} + .' <<< "$metadata")
    # Save each confirmed upload before the shoot, so a failed edit is retryable.
    save_upload
    uploaded=$((uploaded + 1))
  fi

  mkdir -p "$SCRIPT_DIR/_shoots"

  DOC_DATE="${TARGET_DATE:-$ymd}"
  doc="$SCRIPT_DIR/_shoots/$DOC_DATE.md"

  if [ ! -f "$doc" ]; then
    {
      printf '%s\n' '---'
      SHOOT_DATE="$DOC_DATE" yq --null-input '
        {
          "layout": "shoot",
          "title": strenv(SHOOT_DATE),
          "date": env(SHOOT_DATE),
          "images": []
        }
      '
      printf '%s\n' '---'
    } > "$WORK_DIR/shoot.md"
    mv "$WORK_DIR/shoot.md" "$doc"
  fi

  update_shoot
done < "$WORK_DIR/files"

echo "Done: $uploaded uploaded."
