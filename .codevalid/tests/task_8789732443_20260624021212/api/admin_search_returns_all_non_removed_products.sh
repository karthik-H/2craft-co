#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
ADMIN_TOKEN="${ADMIN_TOKEN:-admin-token}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
SELLER_ID="seller_admin_${CASE_SUFFIX}"
SELLER_USER_ID="seller_user_admin_${CASE_SUFFIX}"
PROD1_ID="prod_001_${CASE_SUFFIX}"
PROD2_ID="prod_002_${CASE_SUFFIX}"
PROD3_ID="prod_003_${CASE_SUFFIX}"
PROD4_ID="prod_004_${CASE_SUFFIX}"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM product WHERE id IN ('$PROD1_ID', '$PROD2_ID', '$PROD3_ID', '$PROD4_ID');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller WHERE id = '$SELLER_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"user\" WHERE id = '$SELLER_USER_ID';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"user\" (id, email, password_hash, role, status) VALUES ('$SELLER_USER_ID', 'seller-admin-${CASE_SUFFIX}@example.com', 'test-hash', 'USER', 'active');" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO seller (id, user_id, store_name) VALUES ('$SELLER_ID', '$SELLER_USER_ID', 'Admin Search Store ${CASE_SUFFIX}');" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO product (id, seller_id, title, description, category, price_cents, stock_qty, status, visible, created_at) VALUES ('$PROD1_ID', '$SELLER_ID', 'Widget A ${CASE_SUFFIX}', 'Admin visible product', 'electronics', 1000, 10, 'ACTIVE', true, now() - interval '3 minutes'), ('$PROD2_ID', '$SELLER_ID', 'Widget B ${CASE_SUFFIX}', 'Admin hidden product', 'electronics', 1100, 5, 'ACTIVE', false, now() - interval '2 minutes'), ('$PROD3_ID', '$SELLER_ID', 'Widget C ${CASE_SUFFIX}', 'Another visible product', 'electronics', 1200, 7, 'ACTIVE', true, now() - interval '1 minute'), ('$PROD4_ID', '$SELLER_ID', 'Deleted Widget ${CASE_SUFFIX}', 'Removed product', 'electronics', 1300, 1, 'REMOVED', true, now());" >/dev/null

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X GET -H "Authorization: Bearer $ADMIN_TOKEN" "$BASE_URL/products?category=electronics")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
grep -F "$PROD1_ID" "$RESPONSE_FILE" >/dev/null
grep -F "$PROD2_ID" "$RESPONSE_FILE" >/dev/null
grep -F "$PROD3_ID" "$RESPONSE_FILE" >/dev/null
if grep -F "$PROD4_ID" "$RESPONSE_FILE" >/dev/null; then exit 1; fi
grep -F '"store_name"' "$RESPONSE_FILE" >/dev/null
grep -F '"seller_status"' "$RESPONSE_FILE" >/dev/null
grep -F '"visible":false' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM product WHERE id IN ('$PROD1_ID', '$PROD2_ID', '$PROD3_ID', '$PROD4_ID');" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller WHERE id = '$SELLER_ID';" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"user\" WHERE id = '$SELLER_USER_ID';" >/dev/null

echo 'CODEVALID_TEST_ASSERTION_OK:admin_search_returns_all_non_removed_products'
