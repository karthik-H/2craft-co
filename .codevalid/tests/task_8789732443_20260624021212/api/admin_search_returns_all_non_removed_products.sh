#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_USER_ID="admin-user-${CASE_SUFFIX}"
ADMIN_EMAIL="admin-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER_USER_ID="seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-${CASE_SUFFIX}"
PROD1_ID="prod-001-${CASE_SUFFIX}"
PROD2_ID="prod-002-${CASE_SUFFIX}"
PROD3_ID="prod-003-${CASE_SUFFIX}"
PROD4_ID="prod-004-${CASE_SUFFIX}"
ADMIN_RESPONSE="/tmp/admin_login_${CASE_SUFFIX}.json"
ADMIN_STATUS="/tmp/admin_login_${CASE_SUFFIX}.status"
RESPONSE_FILE="/tmp/admin_search_returns_all_non_removed_products_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/admin_search_returns_all_non_removed_products_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$ADMIN_RESPONSE" "$ADMIN_STATUS" "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${SELLER_USER_ID}', 'seller-${CASE_SUFFIX}@example.com', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW()),
  ('${ADMIN_USER_ID}', '${ADMIN_EMAIL}', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'ADMIN', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Admin Search Store ${CASE_SUFFIX}', '');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'Widget A', 'Admin search visible product', 'electronics', 1000, 8, '[]', 'ACTIVE', true, NOW() - INTERVAL '3 minutes'),
  ('${PROD2_ID}', '${SELLER_PROFILE_ID}', 'Widget B', 'Admin search hidden product', 'electronics', 1100, 4, '[]', 'ACTIVE', false, NOW() - INTERVAL '2 minutes'),
  ('${PROD3_ID}', '${SELLER_PROFILE_ID}', 'Widget C', 'Admin search visible product newest', 'electronics', 1200, 2, '[]', 'ACTIVE', true, NOW() - INTERVAL '1 minute'),
  ('${PROD4_ID}', '${SELLER_PROFILE_ID}', 'Deleted Widget', 'Removed product should stay hidden', 'electronics', 1300, 1, '[]', 'REMOVED', true, NOW());
SQL

curl -sS -o "$ADMIN_RESPONSE" -w '%{http_code}' -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}" > "$ADMIN_STATUS"
[ "$(cat "$ADMIN_STATUS")" = "200" ]
ADMIN_TOKEN="$(jq -r '.token' "$ADMIN_RESPONSE")"
[ "$ADMIN_TOKEN" != "null" ]

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?category=electronics" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'type == "array" and length == 3' "$RESPONSE_FILE" >/dev/null
jq -e --arg p1 "$PROD1_ID" --arg p2 "$PROD2_ID" --arg p3 "$PROD3_ID" --arg p4 "$PROD4_ID" '
  .[0].id == $p3 and .[1].id == $p2 and .[2].id == $p1 and
  (map(.id) | index($p1) != null) and
  (map(.id) | index($p2) != null) and
  (map(.id) | index($p3) != null) and
  (map(.id) | index($p4) == null)
' "$RESPONSE_FILE" >/dev/null
jq -e 'all(.[]; has("id") and has("title") and has("category") and has("price_cents") and has("stock_qty") and has("status") and has("visible") and has("store_name") and has("seller_status"))' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:admin_search_returns_all_non_removed_products"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}', '${PROD3_ID}', '${PROD4_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id IN ('${SELLER_USER_ID}', '${ADMIN_USER_ID}');
SQL
