#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
SELLER_USER_ID="cv_user_instock_${CASE_SUFFIX}"
SELLER_ID="cv_seller_instock_${CASE_SUFFIX}"
P1_ID="cv_prod_instock_1_${CASE_SUFFIX}"
P2_ID="cv_prod_instock_2_${CASE_SUFFIX}"
P3_ID="cv_prod_instock_3_${CASE_SUFFIX}"
P4_ID="cv_prod_instock_4_${CASE_SUFFIX}"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Product\" WHERE id IN ('$P1_ID','$P2_ID','$P3_ID','$P4_ID');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Seller\" WHERE id = '$SELLER_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE id = '$SELLER_USER_ID';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"User\" (id, email, password, role, status, \"createdAt\", \"updatedAt\") VALUES ('$SELLER_USER_ID', 'instock_${CASE_SUFFIX}@example.com', 'test-password', 'USER', 'ACTIVE', NOW(), NOW());"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Seller\" (id, \"userId\", \"storeName\", \"createdAt\", \"updatedAt\") VALUES ('$SELLER_ID', '$SELLER_USER_ID', 'Clothing Store ${CASE_SUFFIX}', NOW(), NOW());"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Product\" (id, \"sellerId\", title, description, category, \"priceCents\", \"stockQty\", status, visible, \"createdAt\", \"updatedAt\") VALUES ('$P1_ID', '$SELLER_ID', 'T-shirt ${CASE_SUFFIX}', 'In stock shirt', 'clothing', 1999, 10, 'ACTIVE', true, NOW() - INTERVAL '4 minutes', NOW()), ('$P2_ID', '$SELLER_ID', 'Jeans ${CASE_SUFFIX}', 'Out of stock jeans', 'clothing', 4999, 0, 'ACTIVE', true, NOW() - INTERVAL '3 minutes', NOW()), ('$P3_ID', '$SELLER_ID', 'Jacket ${CASE_SUFFIX}', 'Hidden jacket', 'clothing', 7999, 5, 'ACTIVE', false, NOW() - INTERVAL '2 minutes', NOW()), ('$P4_ID', '$SELLER_ID', 'Socks ${CASE_SUFFIX}', 'Removed socks', 'clothing', 999, 2, 'REMOVED', true, NOW() - INTERVAL '1 minute', NOW());"

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?in_stock=true")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
grep -F 'T-shirt' "$RESPONSE_FILE" >/dev/null
! grep -F 'Jeans' "$RESPONSE_FILE" >/dev/null
! grep -F 'Jacket' "$RESPONSE_FILE" >/dev/null
! grep -F 'Socks' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects

printf '%s\n' 'CODEVALID_TEST_ASSERTION_OK:in_stock_filter_regular_user'
