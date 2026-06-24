#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
SELLER_ID="seller_info_${CASE_SUFFIX}"
SELLER_USER_ID="seller_user_info_${CASE_SUFFIX}"
PROD1_ID="prod_801_${CASE_SUFFIX}"
STORE_NAME="Tech Store ${CASE_SUFFIX}"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM product WHERE id = '$PROD1_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller WHERE id = '$SELLER_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"user\" WHERE id = '$SELLER_USER_ID';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"user\" (id, email, password_hash, role, status) VALUES ('$SELLER_USER_ID', 'seller-info-${CASE_SUFFIX}@example.com', 'test-hash', 'USER', 'active');" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO seller (id, user_id, store_name) VALUES ('$SELLER_ID', '$SELLER_USER_ID', '$STORE_NAME');" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO product (id, seller_id, title, description, category, price_cents, stock_qty, status, visible, created_at) VALUES ('$PROD1_ID', '$SELLER_ID', 'Gadget ${CASE_SUFFIX}', 'Seller info verification product', 'electronics', 8700, 5, 'ACTIVE', true, now());" >/dev/null

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X GET "$BASE_URL/products")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
grep -F "$PROD1_ID" "$RESPONSE_FILE" >/dev/null
grep -F '"store_name"' "$RESPONSE_FILE" >/dev/null
grep -F "$STORE_NAME" "$RESPONSE_FILE" >/dev/null
grep -F '"seller_status"' "$RESPONSE_FILE" >/dev/null
grep -F 'active' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM product WHERE id = '$PROD1_ID';" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller WHERE id = '$SELLER_ID';" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"user\" WHERE id = '$SELLER_USER_ID';" >/dev/null

echo 'CODEVALID_TEST_ASSERTION_OK:response_includes_seller_information'
