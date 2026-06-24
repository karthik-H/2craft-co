#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
RESPONSE_FILE="$(mktemp)"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — admin browse scenario; token may be supplied by the runtime if available

# When — perform the action under test
if [ -n "$ADMIN_TOKEN" ]; then
  HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X GET -H "Authorization: Bearer $ADMIN_TOKEN" "$BASE_URL/products")
else
  HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X GET "$BASE_URL/products")
fi

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
grep -Eq '^\s*\[' "$RESPONSE_FILE"
! grep -F 'Removed Pants' "$RESPONSE_FILE" >/dev/null 2>&1 || { echo 'removed product unexpectedly visible'; exit 1; }

echo 'CODEVALID_TEST_ASSERTION_OK:admin_user_search_returns_all_non_removed_products'
