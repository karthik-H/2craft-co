#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
SELLER_USER_ID="cv_user_no_match_${CASE_SUFFIX}"
SELLER_ID="cv_seller_no_match_${CASE_SUFFIX}"
P1_ID="cv_prod_no_match_1_${CASE_SUFFIX}"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Product\" WHERE id = '$P1_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Seller\" WHERE id = '$SELLER_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE id = '$SELLER_USER_ID';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"User\" (id, email, password, role, status, \"createdAt\", \"updatedAt\") VALUES ('$SELLER_USER_ID', 'no_match_${CASE_SUFFIX}@example.com', 'test-password', 'USER', 'ACTIVE', NOW(), NOW());"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Seller\" (id, \"userId\", \"storeName\", \"createdAt\", \"updatedAt\") VALUES ('$SELLER_ID', '$SELLER_USER_ID', 'Bottle Store ${CASE_SUFFIX}', NOW(), NOW());"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Product\" (id, \"sellerId\", title, description, category, \"priceCents\", \"stockQty\", status, visible, \"createdAt\", \"updatedAt\") VALUES ('$P1_ID', '$SELLER_ID', 'Water Bottle ${CASE_SUFFIX}', 'Hydration bottle', 'misc', 1500, 10, 'ACTIVE', true, NOW(), NOW());"

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?keyword=xyznonexistent")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
BODY_COMPACT="$(tr -d '[:space:]' < "$RESPONSE_FILE")"
[ "$BODY_COMPACT" = "[]" ]

# Cleanup — undo Given side effects

printf '%s\n' 'CODEVALID_TEST_ASSERTION_OK:keyword_with_no_matches_returns_empty'
