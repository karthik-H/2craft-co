#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
ADMIN_JWT="${ADMIN_JWT:-}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
SELLER_USER_ID="cv_user_admin_books_${CASE_SUFFIX}"
SELLER_ID="cv_seller_admin_books_${CASE_SUFFIX}"
P1_ID="cv_prod_admin_books_1_${CASE_SUFFIX}"
P2_ID="cv_prod_admin_books_2_${CASE_SUFFIX}"
P3_ID="cv_prod_admin_books_3_${CASE_SUFFIX}"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Product\" WHERE id IN ('$P1_ID','$P2_ID','$P3_ID');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Seller\" WHERE id = '$SELLER_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE id = '$SELLER_USER_ID';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

[ -n "$ADMIN_JWT" ]

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"User\" (id, email, password, role, status, \"createdAt\", \"updatedAt\") VALUES ('$SELLER_USER_ID', 'admin_books_${CASE_SUFFIX}@example.com', 'test-password', 'USER', 'ACTIVE', NOW(), NOW());"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Seller\" (id, \"userId\", \"storeName\", \"createdAt\", \"updatedAt\") VALUES ('$SELLER_ID', '$SELLER_USER_ID', 'Books Store ${CASE_SUFFIX}', NOW(), NOW());"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Product\" (id, \"sellerId\", title, description, category, \"priceCents\", \"stockQty\", status, visible, \"createdAt\", \"updatedAt\") VALUES ('$P1_ID', '$SELLER_ID', 'Novel A ${CASE_SUFFIX}', 'Visible novel', 'books', 1599, 3, 'ACTIVE', true, NOW() - INTERVAL '3 minutes', NOW()), ('$P2_ID', '$SELLER_ID', 'Novel B ${CASE_SUFFIX}', 'Hidden novel', 'books', 1699, 0, 'ACTIVE', false, NOW() - INTERVAL '2 minutes', NOW()), ('$P3_ID', '$SELLER_ID', 'Deleted Novel ${CASE_SUFFIX}', 'Removed novel', 'books', 1799, 1, 'REMOVED', true, NOW() - INTERVAL '1 minute', NOW());"

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -H "Authorization: Bearer $ADMIN_JWT" "$BASE_URL/products?category=books")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
grep -F 'Novel A' "$RESPONSE_FILE" >/dev/null
grep -F 'Novel B' "$RESPONSE_FILE" >/dev/null
! grep -F 'Deleted Novel' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects

printf '%s\n' 'CODEVALID_TEST_ASSERTION_OK:admin_sees_all_non_removed_products'
