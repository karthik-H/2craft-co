#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
ADMIN_RESPONSE_FILE="$(mktemp)"
USER_RESPONSE_FILE="$(mktemp)"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"
USER_TOKEN="${USER_TOKEN:-}"

cleanup() {
  rm -f "$ADMIN_RESPONSE_FILE" "$USER_RESPONSE_FILE"
}
trap cleanup EXIT

# Given — removed products exclusion scenario for both roles

# When — perform the action under test
if [ -n "$ADMIN_TOKEN" ]; then
  ADMIN_HTTP_CODE=$(curl -sS -o "$ADMIN_RESPONSE_FILE" -w '%{http_code}' -X GET -H "Authorization: Bearer $ADMIN_TOKEN" "$BASE_URL/products")
else
  ADMIN_HTTP_CODE=$(curl -sS -o "$ADMIN_RESPONSE_FILE" -w '%{http_code}' -X GET "$BASE_URL/products")
fi
if [ -n "$USER_TOKEN" ]; then
  USER_HTTP_CODE=$(curl -sS -o "$USER_RESPONSE_FILE" -w '%{http_code}' -X GET -H "Authorization: Bearer $USER_TOKEN" "$BASE_URL/products")
else
  USER_HTTP_CODE=$(curl -sS -o "$USER_RESPONSE_FILE" -w '%{http_code}' -X GET "$BASE_URL/products")
fi

# Then — HTTP/body assertions
[ "$ADMIN_HTTP_CODE" = "200" ]
[ "$USER_HTTP_CODE" = "200" ]
grep -Eq '^\s*\[' "$ADMIN_RESPONSE_FILE"
grep -Eq '^\s*\[' "$USER_RESPONSE_FILE"
! grep -F 'Soft Deleted Table' "$ADMIN_RESPONSE_FILE" >/dev/null 2>&1 || { echo 'removed product visible to admin'; exit 1; }
! grep -F 'Hidden Removed Desk' "$ADMIN_RESPONSE_FILE" >/dev/null 2>&1 || { echo 'removed hidden product visible to admin'; exit 1; }
! grep -F 'Soft Deleted Table' "$USER_RESPONSE_FILE" >/dev/null 2>&1 || { echo 'removed product visible to user'; exit 1; }
! grep -F 'Hidden Removed Desk' "$USER_RESPONSE_FILE" >/dev/null 2>&1 || { echo 'removed hidden product visible to user'; exit 1; }

echo 'CODEVALID_TEST_ASSERTION_OK:soft_deleted_products_excluded_for_all_users'
