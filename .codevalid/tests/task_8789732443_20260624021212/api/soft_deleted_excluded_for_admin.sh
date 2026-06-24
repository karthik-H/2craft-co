#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
ADMIN_JWT="${ADMIN_JWT:-}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
SELLER_USER_ID="cv_user_soft_deleted_${CASE_SUFFIX}"
SELLER_ID="cv_seller_soft_deleted_${CASE_SUFFIX}"
P1_ID="cv_prod_soft_deleted_1_${CASE_SUFFIX}"
P2_ID="cv_prod_soft_deleted_2_${CASE_SUFFIX}"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Product\" WHERE id IN ('$P1_ID','$P2_ID');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Seller\" WHERE id = '$SELLER_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE id = '$SELLER_USER_ID';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

[ -n "$ADMIN_JWT" ]

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"User\" (id, email, password, role, status, \"createdAt\", \"updatedAt\") VALUES ('$SELLER_USER_ID', 'soft_deleted_${CASE_SUFFIX}@example.com', 'test-password', 'USER', 'ACTIVE', NOW(), NOW());"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Seller\" (id, \"userId\", \"storeName\", \"createdAt\", \"updatedAt\") VALUES ('$SELLER_ID', '$SELLER_USER_ID', 'Home Store ${CASE_SUFFIX}', NOW(), NOW());"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Product\" (id, \"sellerId\", title, description, category, \"priceCents\", \"stockQty\", status, visible, \"createdAt\", \"updatedAt\") VALUES ('$P1_ID', '$SELLER_ID', 'Active Product ${CASE_SUFFIX}', 'Shown home item', 'home', 2099, 4, 'ACTIVE', true, NOW() - INTERVAL '2 minutes', NOW()), ('$P2_ID', '$SELLER_ID', 'Removed Product ${CASE_SUFFIX}', 'Deleted home item', 'home', 3099, 1, 'REMOVED', true, NOW() - INTERVAL '1 minute', NOW());"

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -H "Authorization: Bearer $ADMIN_JWT" "$BASE_URL/products?category=home")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
grep -F 'Active Product' "$RESPONSE_FILE" >/dev/null
! grep -F 'Removed Product' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects

printf '%s\n' 'CODEVALID_TEST_ASSERTION_OK:soft_deleted_excluded_for_admin'
