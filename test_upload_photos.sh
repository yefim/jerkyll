#!/usr/bin/env bash
# Run with: bash test_upload_photos.sh
set -euo pipefail

test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
cp "$(dirname -- "${BASH_SOURCE[0]}")/upload_photos.sh" "$test_dir/"
mkdir -p "$test_dir/bin" "$test_dir/photos/nested"
cat > "$test_dir/bin/curl" <<'MOCK'
#!/usr/bin/env bash
echo upload >> "$UPLOAD_LOG"
echo '{"success":true,"result":{"id":"test-image"}}'
MOCK
chmod +x "$test_dir/bin/curl"
export PATH="$test_dir/bin:$PATH" CF_ACCOUNT_ID=test CF_API_TOKEN=test
export UPLOAD_LOG="$test_dir/uploads.log"

magick -size 4x3 gradient:black-white "$test_dir/photos/nested/a photo.jpg"
exiftool -overwrite_original '-DateTimeOriginal=2026:09:10 12:00:00' \
  "$test_dir/photos/nested/a photo.jpg" >/dev/null
cp "$test_dir/photos/nested/a photo.jpg" "$test_dir/photos/copy.jpg"
"$BASH" "$test_dir/upload_photos.sh" "$test_dir/photos" --date 2026-09-10
"$BASH" "$test_dir/upload_photos.sh" "$test_dir/photos" --date 2026-09-10
[[ $(wc -l < "$UPLOAD_LOG") -eq 1 ]]
[[ $(yq 'length' "$test_dir/_photo_uploads.yml") -eq 1 ]]
[[ $(yq --front-matter=extract '.images | length' "$test_dir/_shoots/2026-09-10.md") -eq 1 ]]

yq -i 'with(.[]; del(.blurhash))' "$test_dir/_photo_uploads.yml"
if "$BASH" "$test_dir/upload_photos.sh" "$test_dir/photos" > "$test_dir/rejected.log" 2>&1; then
  echo 'FAIL: incomplete history was accepted' >&2
  exit 1
fi
[[ $(wc -l < "$UPLOAD_LOG") -eq 1 ]]
echo 'Photo upload smoke check passed.'
