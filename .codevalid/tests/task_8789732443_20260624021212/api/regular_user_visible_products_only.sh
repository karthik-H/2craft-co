#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
SELLER_USER_ID="cv_user_rvpo_${CASE_SUFFIX}"
SELLER_ID="cv_seller_rvpo_${CASE_SUFFIX}"
P1_ID="cv_prod_rvpo_1_${CASE_SUFFIX}"
P2_ID="cv_prod_rvpo_2_${CASE_SUFFIX}"
P3_ID="cv_prod_rvpo_3_${CASE_SUFFIX}"
P4_ID="cv_prod_rvpo_4_${CASE_SUFFIX}"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Product\" WHERE id IN ('$P1_ID','$P2_ID','$P3_ID','$P4_ID');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Seller\" WHERE id = '$SELLER_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE id = '$SELLER_USER_ID';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"User\" (id, email, password, role, status, \"createdAt\", \"updatedAt\") VALUES ('$SELLER_USER_ID', 'rvpo_${CASE_SUFFIX}@example.com', 'test-password', 'USER', 'ACTIVE', NOW(), NOW());"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Seller\" (id, \"userId\", \"storeName\", \"createdAt\", \"updatedAt\") VALUES ('$SELLER_ID', '$SELLER_USER_ID', 'Visible Store ${CASE_SUFFIX}', NOW(), NOW());"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Product\" (id, \"sellerId\", title, description, category, \"priceCents\", \"stockQty\", status, visible, \"createdAt\", \"updatedAt\") VALUES ('$P1_ID', '$SELLER_ID', 'Smartphone X ${CASE_SUFFIX}', 'Visible phone', 'electronics', 19999, 10, 'ACTIVE', true, NOW() - INTERVAL '4 minutes', NOW()), ('$P2_ID', '$SELLER_ID', 'Laptop Pro ${CASE_SUFFIX}', 'Visible laptop', 'electronics', 99999, 0, 'ACTIVE', true, NOW() - INTERVAL '3 minutes', NOW()), ('$P3_ID', '$SELLER_ID', 'Hidden Gadget ${CASE_SUFFIX}', 'Hidden gadget', 'electronics', 29999, 5, 'ACTIVE', false, NOW() - INTERVAL '2 minutes', NOW()), ('$P4_ID', '$SELLER_ID', 'Old Phone ${CASE_SUFFIX}', 'Removed phone', 'electronics', 9999, 2, 'REMOVED', true, NOW() - INTERVAL '1 minute', NOW());"

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?category=electronics")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
grep -F 'Smartphone X' "$RESPONSE_FILE" >/dev/null
grep -F 'Laptop Pro' "$RESPONSE_FILE" >/dev/null
! grep -F 'Hidden Gadget' "$RESPONSE_FILE" >/dev/null
! grep -F 'Old Phone' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects

printf '%s\n' 'CODEVALID_TEST_ASSERTION_OK:regular_user_visible_products_only'
