#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
RESPONSE_FILE="$(mktemp)"
USER_TOKEN="${USER_TOKEN:-}"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — keyword search scenario

# When — perform the action under test
if [ -n "$USER_TOKEN" ]; then
  HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X GET -H "Authorization: Bearer $USER_TOKEN" "$BASE_URL/products?keyword=wireless")
else
  HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X GET "$BASE_URL/products?keyword=wireless")
fi

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
grep -Eq '^\s*\[' "$RESPONSE_FILE"
! grep -F 'Wired Earbuds' "$RESPONSE_FILE" >/dev/null 2>&1 || { echo 'non-matching keyword product returned'; exit 1; }

echo 'CODEVALID_TEST_ASSERTION_OK:keyword_filter_matches_title_and_description'
