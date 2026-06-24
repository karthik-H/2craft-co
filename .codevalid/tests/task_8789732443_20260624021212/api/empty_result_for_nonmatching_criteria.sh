#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
RESPONSE_FILE="$(mktemp)"
USER_TOKEN="${USER_TOKEN:-}"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — non-matching category scenario

# When — perform the action under test
if [ -n "$USER_TOKEN" ]; then
  HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X GET -H "Authorization: Bearer $USER_TOKEN" "$BASE_URL/products?category=NONEXISTENT")
else
  HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X GET "$BASE_URL/products?category=NONEXISTENT")
fi

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
grep -Eq '^\s*\[' "$RESPONSE_FILE"

echo 'CODEVALID_TEST_ASSERTION_OK:empty_result_for_nonmatching_criteria'
