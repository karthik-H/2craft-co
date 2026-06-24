#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
ADMIN_TOKEN="${ADMIN_TOKEN:-admin-token}"
USER_TOKEN="${USER_TOKEN:-user-token}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_RESPONSE_FILE="$(mktemp)"
USER_RESPONSE_FILE="$(mktemp)"
SELLER_ID="seller_soft_deleted_${CASE_SUFFIX}"
SELLER_USER_ID="seller_user_soft_deleted_${CASE_SUFFIX}"
PROD1_ID="prod_501_${CASE_SUFFIX}"
PROD2_ID="prod_502_${CASE_SUFFIX}"
PROD3_ID="prod_503_${CASE_SUFFIX}"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM product WHERE id IN ('$PROD1_ID', '$PROD2_ID', '$PROD3_ID');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller WHERE id = '$SELLER_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"user\" WHERE id = '$SELLER_USER_ID';" >/dev/null 2>&1 || true
  rm -f "$ADMIN_RESPONSE_FILE" "$USER_RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"user\" (id, email, password_hash, role, status) VALUES ('$SELLER_USER_ID', 'seller-soft-deleted-${CASE_SUFFIX}@example.com', 'test-hash', 'USER', 'active');" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO seller (id, user_id, store_name) VALUES ('$SELLER_ID', '$SELLER_USER_ID', 'Soft Deleted Store ${CASE_SUFFIX}');" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO product (id, seller_id, title, description, category, price_cents, stock_qty, status, visible, created_at) VALUES ('$PROD1_ID', '$SELLER_ID', 'Active Product ${CASE_SUFFIX}', 'Visible toy', 'toys', 2000, 5, 'ACTIVE', true, now() - interval '3 minutes'), ('$PROD2_ID', '$SELLER_ID', 'Soft Deleted Product ${CASE_SUFFIX}', 'Removed toy', 'toys', 2100, 5, 'REMOVED', true, now() - interval '2 minutes'), ('$PROD3_ID', '$SELLER_ID', 'Hidden Deleted Product ${CASE_SUFFIX}', 'Removed hidden toy', 'toys', 2200, 0, 'REMOVED', false, now() - interval '1 minute');" >/dev/null

# When — perform the action under test
ADMIN_HTTP_CODE=$(curl -sS -o "$ADMIN_RESPONSE_FILE" -w '%{http_code}' -X GET -H "Authorization: Bearer $ADMIN_TOKEN" "$BASE_URL/products?category=toys")
USER_HTTP_CODE=$(curl -sS -o "$USER_RESPONSE_FILE" -w '%{http_code}' -X GET -H "Authorization: Bearer $USER_TOKEN" "$BASE_URL/products?category=toys")

# Then — HTTP/body assertions
[ "$ADMIN_HTTP_CODE" = "200" ]
[ "$USER_HTTP_CODE" = "200" ]
grep -F "$PROD1_ID" "$ADMIN_RESPONSE_FILE" >/dev/null
if grep -F "$PROD2_ID" "$ADMIN_RESPONSE_FILE" >/dev/null; then exit 1; fi
if grep -F "$PROD3_ID" "$ADMIN_RESPONSE_FILE" >/dev/null; then exit 1; fi
grep -F "$PROD1_ID" "$USER_RESPONSE_FILE" >/dev/null
if grep -F "$PROD2_ID" "$USER_RESPONSE_FILE" >/dev/null; then exit 1; fi
if grep -F "$PROD3_ID" "$USER_RESPONSE_FILE" >/dev/null; then exit 1; fi

# Cleanup — undo Given side effects
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM product WHERE id IN ('$PROD1_ID', '$PROD2_ID', '$PROD3_ID');" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller WHERE id = '$SELLER_ID';" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"user\" WHERE id = '$SELLER_USER_ID';" >/dev/null

echo 'CODEVALID_TEST_ASSERTION_OK:soft_deleted_products_excluded_from_all_searches'
