#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
RESPONSE_FILE="$(mktemp)"
USER_TOKEN="${USER_TOKEN:-}"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — combined filters scenario

# When — perform the action under test
if [ -n "$USER_TOKEN" ]; then
  HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X GET -H "Authorization: Bearer $USER_TOKEN" "$BASE_URL/products?category=ELECTRONICS&keyword=wireless&in_stock=true")
else
  HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X GET "$BASE_URL/products?category=ELECTRONICS&keyword=wireless&in_stock=true")
fi

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
grep -Eq '^\s*\[' "$RESPONSE_FILE"
! grep -F 'Wired Keyboard' "$RESPONSE_FILE" >/dev/null 2>&1 || { echo 'zero-stock product returned'; exit 1; }
! grep -F 'Wireless Networking Guide' "$RESPONSE_FILE" >/dev/null 2>&1 || { echo 'wrong-category product returned'; exit 1; }

echo 'CODEVALID_TEST_ASSERTION_OK:combined_filters_apply_all_criteria'
