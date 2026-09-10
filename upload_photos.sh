#!/usr/bin/env bash

# Usage:
#   ./upload_photos.sh <folder> [--date yyyy-mm-dd]

if [ $# -lt 1 ]; then
  echo "Usage: $0 <folder> [--date yyyy-mm-dd]"
  exit 1
fi

DIR="$1"
shift

TARGET_DATE=""

# Parse optional args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --date)
      TARGET_DATE="$2"
      if ! echo "$TARGET_DATE" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        echo "Error: --date must be in format yyyy-mm-dd"
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

# -----------------------------
# 1. Build map: filepath → YYYY-MM-DD
#    using *one* exiftool call
# -----------------------------

declare -A FILE_DATES

# exiftool outputs:
#   /absolute/path/to/file.jpg <tab> 2024:11:03 12:04:55
while IFS=$'\t' read -r path dt; do
  if [[ -n "$dt" ]]; then
    ymd=$(date -jf "%Y:%m:%d %H:%M:%S" "$dt" "+%Y-%m-%d" 2>/dev/null)
    [[ -n "$ymd" ]] && FILE_DATES["$path"]="$ymd"
  fi
done < <(
  exiftool -fast -T -FilePath -DateTimeOriginal \
    -ext jpg -ext jpeg -ext png -ext heic "$DIR"
)

# -----------------------------
# 2. Iterate files (skip if no EXIF date)
# -----------------------------

for f in $(fd -e jpg -e jpeg -e png -e heic . "$DIR"); do
  ymd="${FILE_DATES["$f"]}"

  # Skip files with no EXIF date
  if [[ -z "$ymd" ]]; then
    echo "Skipping $f (no EXIF date)"
    continue
  fi

  # Apply --date filter
  if [[ -n "$TARGET_DATE" && "$ymd" != "$TARGET_DATE" ]]; then
    continue
  fi

  echo "Uploading $f (date: $ymd)…"

  id=$(curl -s -X POST \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -F "file=@${f}" \
    "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/images/v1" \
    | jq -r '.result.id')

  mkdir -p _shoots

  DOC_DATE="${TARGET_DATE:-$ymd}"
  doc="_shoots/$DOC_DATE.md"

  if [ ! -f "$doc" ]; then
    printf -- "---\nlayout: shoot\ntitle: %s\ndate: %s\nimages:\n---\n" "$DOC_DATE" "$DOC_DATE" > "$doc"
  fi

  if ! grep -Fq "  - $id" "$doc"; then
    sed -i '' "s/^images:.*/&\n  - $id/" "$doc"
  fi
done

