#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
USER_TOKEN="${USER_TOKEN:-user-token}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
SELLER_ID="seller_regular_${CASE_SUFFIX}"
SELLER_USER_ID="seller_user_regular_${CASE_SUFFIX}"
PROD1_ID="prod_101_${CASE_SUFFIX}"
PROD2_ID="prod_102_${CASE_SUFFIX}"
PROD3_ID="prod_103_${CASE_SUFFIX}"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM product WHERE id IN ('$PROD1_ID', '$PROD2_ID', '$PROD3_ID');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller WHERE id = '$SELLER_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"user\" WHERE id = '$SELLER_USER_ID';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"user\" (id, email, password_hash, role, status) VALUES ('$SELLER_USER_ID', 'seller-regular-${CASE_SUFFIX}@example.com', 'test-hash', 'USER', 'active');" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO seller (id, user_id, store_name) VALUES ('$SELLER_ID', '$SELLER_USER_ID', 'Regular Search Store ${CASE_SUFFIX}');" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO product (id, seller_id, title, description, category, price_cents, stock_qty, status, visible, created_at) VALUES ('$PROD1_ID', '$SELLER_ID', 'Public Item ${CASE_SUFFIX}', 'Visible item', 'books', 900, 10, 'ACTIVE', true, now() - interval '3 minutes'), ('$PROD2_ID', '$SELLER_ID', 'Hidden Item ${CASE_SUFFIX}', 'Hidden item', 'books', 1000, 10, 'ACTIVE', false, now() - interval '2 minutes'), ('$PROD3_ID', '$SELLER_ID', 'Deleted Item ${CASE_SUFFIX}', 'Removed item', 'books', 1100, 10, 'REMOVED', true, now() - interval '1 minute');" >/dev/null

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X GET -H "Authorization: Bearer $USER_TOKEN" "$BASE_URL/products?category=books")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
grep -F "$PROD1_ID" "$RESPONSE_FILE" >/dev/null
if grep -F "$PROD2_ID" "$RESPONSE_FILE" >/dev/null; then exit 1; fi
if grep -F "$PROD3_ID" "$RESPONSE_FILE" >/dev/null; then exit 1; fi

# Cleanup — undo Given side effects
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM product WHERE id IN ('$PROD1_ID', '$PROD2_ID', '$PROD3_ID');" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller WHERE id = '$SELLER_ID';" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"user\" WHERE id = '$SELLER_USER_ID';" >/dev/null

echo 'CODEVALID_TEST_ASSERTION_OK:regular_user_search_returns_only_visible_products'
