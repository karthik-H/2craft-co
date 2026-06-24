#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_USER_ID="buyer-user-${CASE_SUFFIX}"
BUYER_EMAIL="buyer-${CASE_SUFFIX}@example.com"
BUYER_PASSWORD='BuyerPass123!'
SELLER_USER_ID="seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-${CASE_SUFFIX}"
PROD1_ID="prod-101-${CASE_SUFFIX}"
PROD2_ID="prod-102-${CASE_SUFFIX}"
PROD3_ID="prod-103-${CASE_SUFFIX}"
LOGIN_RESPONSE="/tmp/regular_user_login_${CASE_SUFFIX}.json"
LOGIN_STATUS="/tmp/regular_user_login_${CASE_SUFFIX}.status"
RESPONSE_FILE="/tmp/regular_user_search_returns_only_visible_products_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/regular_user_search_returns_only_visible_products_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$LOGIN_RESPONSE" "$LOGIN_STATUS" "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${SELLER_USER_ID}', 'seller-${CASE_SUFFIX}@example.com', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW()),
  ('${BUYER_USER_ID}', '${BUYER_EMAIL}', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'BUYER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Regular Search Store ${CASE_SUFFIX}', '');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'Public Item', 'Visible book result', 'books', 1500, 7, '[]', 'ACTIVE', true, NOW() - INTERVAL '3 minutes'),
  ('${PROD2_ID}', '${SELLER_PROFILE_ID}', 'Hidden Item', 'Hidden book result', 'books', 1600, 5, '[]', 'ACTIVE', false, NOW() - INTERVAL '2 minutes'),
  ('${PROD3_ID}', '${SELLER_PROFILE_ID}', 'Deleted Item', 'Removed book result', 'books', 1700, 4, '[]', 'REMOVED', true, NOW() - INTERVAL '1 minute');
SQL

curl -sS -o "$LOGIN_RESPONSE" -w '%{http_code}' -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"${BUYER_PASSWORD}\"}" > "$LOGIN_STATUS"
[ "$(cat "$LOGIN_STATUS")" = "200" ]
BUYER_TOKEN="$(jq -r '.token' "$LOGIN_RESPONSE")"
[ "$BUYER_TOKEN" != "null" ]

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?category=books" \
  -H "Authorization: Bearer ${BUYER_TOKEN}" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'type == "array" and length == 1' "$RESPONSE_FILE" >/dev/null
jq -e --arg p1 "$PROD1_ID" --arg p2 "$PROD2_ID" --arg p3 "$PROD3_ID" '
  .[0].id == $p1 and .[0].visible == true and
  (map(.id) | index($p2) == null) and
  (map(.id) | index($p3) == null)
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:regular_user_search_returns_only_visible_products"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}', '${PROD3_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id IN ('${SELLER_USER_ID}', '${BUYER_USER_ID}');
SQL
