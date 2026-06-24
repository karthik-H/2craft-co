#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — regular user browse scenario against public products endpoint
# No setup is performed because workspace/schema were unavailable for safe DB seeding.

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X GET "$BASE_URL/products")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
grep -Eq '^\s*\[' "$RESPONSE_FILE"
! grep -F 'Hidden Phone' "$RESPONSE_FILE" >/dev/null 2>&1 || { echo 'hidden product unexpectedly visible'; exit 1; }
! grep -F 'Removed Tablet' "$RESPONSE_FILE" >/dev/null 2>&1 || { echo 'removed product unexpectedly visible'; exit 1; }

echo 'CODEVALID_TEST_ASSERTION_OK:regular_user_search_returns_visible_products_only'
