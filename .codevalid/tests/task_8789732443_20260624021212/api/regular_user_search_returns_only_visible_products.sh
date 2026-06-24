#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_EMAIL="buyer-${CASE_SUFFIX}@example.com"
BUYER_PASSWORD='BuyerPass123!'
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
  ('seller-user-${CASE_SUFFIX}', 'seller-${CASE_SUFFIX}@example.com', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW()),
  ('user-123', '${BUYER_EMAIL}', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'BUYER', 'ACTIVE', NOW())
ON CONFLICT (id) DO NOTHING;
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('seller-profile-${CASE_SUFFIX}', 'seller-user-${CASE_SUFFIX}', 'Regular Search Store ${CASE_SUFFIX}', '')
ON CONFLICT (id) DO NOTHING;
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('prod-101', 'seller-profile-${CASE_SUFFIX}', 'Public Item', 'Visible book result', 'books', 1500, 7, '[]', 'ACTIVE', true, NOW() - INTERVAL '3 minutes'),
  ('prod-102', 'seller-profile-${CASE_SUFFIX}', 'Hidden Item', 'Hidden book result', 'books', 1600, 5, '[]', 'ACTIVE', false, NOW() - INTERVAL '2 minutes'),
  ('prod-103', 'seller-profile-${CASE_SUFFIX}', 'Deleted Item', 'Removed book result', 'books', 1700, 4, '[]', 'REMOVED', true, NOW() - INTERVAL '1 minute')
ON CONFLICT (id) DO UPDATE SET
  seller_id = EXCLUDED.seller_id,
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  category = EXCLUDED.category,
  price_cents = EXCLUDED.price_cents,
  stock_qty = EXCLUDED.stock_qty,
  photos = EXCLUDED.photos,
  status = EXCLUDED.status,
  visible = EXCLUDED.visible,
  created_at = EXCLUDED.created_at;
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
jq -e '.[0].id == "prod-101" and .[0].visible == true' "$RESPONSE_FILE" >/dev/null
jq -e 'map(.id) | index("prod-102") == null and index("prod-103") == null' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:regular_user_search_returns_only_visible_products"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('prod-101', 'prod-102', 'prod-103');
DELETE FROM seller_profiles WHERE id = 'seller-profile-${CASE_SUFFIX}';
DELETE FROM users WHERE id IN ('seller-user-${CASE_SUFFIX}', 'user-123');
SQL
