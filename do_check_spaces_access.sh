#!/usr/bin/env bash
# Secure DigitalOcean Spaces access diagnostic
# Usage: chmod +x check_spaces_access.sh && ./check_spaces_access.sh

####################################################
export AWS_ACCESS_KEY_ID="DO00BVMX6PZ6KPJHJJED"
export AWS_SECRET_ACCESS_KEY="UC2zYabKkoYK3cuCBO9XN5BShE4qm1tZmC6hBdTC6ZA"
####################################################

set -e

# ==== CONFIG ====
BUCKET="boutique-dev"
REGION="sfo3"
ENDPOINT="https://${REGION}.digitaloceanspaces.com"

# ==== ENVIRONMENT ====
if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
  echo "❌ AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY not set."
  echo "   Please export them first or source your .env file."
  exit 1
fi

echo "🔍 Checking access for bucket: $BUCKET in region: $REGION"
echo "   Using endpoint: $ENDPOINT"
echo

# ==== BUCKET LIST TEST ====
echo "📦 1. Testing ListObjects..."
if aws --endpoint-url "$ENDPOINT" s3 ls "s3://$BUCKET" >/dev/null 2>&1; then
  echo "✅ List access OK"
else
  echo "❌ Cannot list bucket contents"
  exit 1
fi

# ==== UPLOAD TEST ====
TMPFILE="spaces_test_$(date +%s).txt"
echo "test upload $(date)" > "$TMPFILE"
echo
echo "⬆️ 2. Testing PutObject (upload)..."
if aws --endpoint-url "$ENDPOINT" s3 cp "$TMPFILE" "s3://$BUCKET/$TMPFILE" >/dev/null 2>&1; then
  echo "✅ Upload OK"
else
  echo "❌ Upload failed (AccessDenied or endpoint mismatch)"
  rm -f "$TMPFILE"
  exit 1
fi

# ==== DOWNLOAD TEST ====
echo
echo "⬇️ 3. Testing GetObject (download)..."
if aws --endpoint-url "$ENDPOINT" s3 cp "s3://$BUCKET/$TMPFILE" ./download_test.txt >/dev/null 2>&1; then
  echo "✅ Download OK"
else
  echo "❌ Download failed"
  exit 1
fi

# ==== DELETE TEST ====
echo
echo "🗑️ 4. Testing DeleteObject..."
if aws --endpoint-url "$ENDPOINT" s3 rm "s3://$BUCKET/$TMPFILE" >/dev/null 2>&1; then
  echo "✅ Delete OK"
else
  echo "❌ Delete failed"
  exit 1
fi

# ==== CLEANUP ====
rm -f "$TMPFILE" download_test.txt
echo
echo "🎉 All tests passed! Your Spaces credentials and permissions are working correctly."
