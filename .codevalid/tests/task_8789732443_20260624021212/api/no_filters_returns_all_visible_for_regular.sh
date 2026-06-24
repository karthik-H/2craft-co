#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
SELLER_USER_ID="cv_user_no_filters_${CASE_SUFFIX}"
SELLER_ID="cv_seller_no_filters_${CASE_SUFFIX}"
P1_ID="cv_prod_no_filters_1_${CASE_SUFFIX}"
P2_ID="cv_prod_no_filters_2_${CASE_SUFFIX}"
P3_ID="cv_prod_no_filters_3_${CASE_SUFFIX}"
P4_ID="cv_prod_no_filters_4_${CASE_SUFFIX}"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Product\" WHERE id IN ('$P1_ID','$P2_ID','$P3_ID','$P4_ID');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Seller\" WHERE id = '$SELLER_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE id = '$SELLER_USER_ID';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"User\" (id, email, password, role, status, \"createdAt\", \"updatedAt\") VALUES ('$SELLER_USER_ID', 'no_filters_${CASE_SUFFIX}@example.com', 'test-password', 'USER', 'ACTIVE', NOW(), NOW());"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Seller\" (id, \"userId\", \"storeName\", \"createdAt\", \"updatedAt\") VALUES ('$SELLER_ID', '$SELLER_USER_ID', 'Misc Store ${CASE_SUFFIX}', NOW(), NOW());"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Product\" (id, \"sellerId\", title, description, category, \"priceCents\", \"stockQty\", status, visible, \"createdAt\", \"updatedAt\") VALUES ('$P1_ID', '$SELLER_ID', 'Product A ${CASE_SUFFIX}', 'Visible item one', 'misc', 1000, 1, 'ACTIVE', true, NOW() - INTERVAL '4 minutes', NOW()), ('$P2_ID', '$SELLER_ID', 'Product B ${CASE_SUFFIX}', 'Visible item two', 'misc', 1100, 0, 'ACTIVE', true, NOW() - INTERVAL '3 minutes', NOW()), ('$P3_ID', '$SELLER_ID', 'Product C ${CASE_SUFFIX}', 'Hidden item', 'misc', 1200, 3, 'ACTIVE', false, NOW() - INTERVAL '2 minutes', NOW()), ('$P4_ID', '$SELLER_ID', 'Product D ${CASE_SUFFIX}', 'Removed item', 'misc', 1300, 5, 'REMOVED', true, NOW() - INTERVAL '1 minute', NOW());"

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
grep -F 'Product A' "$RESPONSE_FILE" >/dev/null
grep -F 'Product B' "$RESPONSE_FILE" >/dev/null
! grep -F 'Product C' "$RESPONSE_FILE" >/dev/null
! grep -F 'Product D' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects

printf '%s\n' 'CODEVALID_TEST_ASSERTION_OK:no_filters_returns_all_visible_for_regular'
