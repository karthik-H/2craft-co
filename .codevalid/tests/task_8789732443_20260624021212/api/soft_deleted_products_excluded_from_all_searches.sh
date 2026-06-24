#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-soft-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
BUYER_EMAIL="buyer-soft-${CASE_SUFFIX}@example.com"
BUYER_PASSWORD='BuyerPass123!'
ADMIN_LOGIN_RESPONSE="/tmp/admin_soft_login_${CASE_SUFFIX}.json"
ADMIN_LOGIN_STATUS="/tmp/admin_soft_login_${CASE_SUFFIX}.status"
BUYER_LOGIN_RESPONSE="/tmp/buyer_soft_login_${CASE_SUFFIX}.json"
BUYER_LOGIN_STATUS="/tmp/buyer_soft_login_${CASE_SUFFIX}.status"
ADMIN_RESPONSE="/tmp/soft_deleted_admin_${CASE_SUFFIX}.json"
ADMIN_STATUS="/tmp/soft_deleted_admin_${CASE_SUFFIX}.status"
BUYER_RESPONSE="/tmp/soft_deleted_buyer_${CASE_SUFFIX}.json"
BUYER_STATUS="/tmp/soft_deleted_buyer_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$ADMIN_LOGIN_RESPONSE" "$ADMIN_LOGIN_STATUS" "$BUYER_LOGIN_RESPONSE" "$BUYER_LOGIN_STATUS" "$ADMIN_RESPONSE" "$ADMIN_STATUS" "$BUYER_RESPONSE" "$BUYER_STATUS"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('seller-user-${CASE_SUFFIX}', 'seller-${CASE_SUFFIX}@example.com', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW()),
  ('admin-user-${CASE_SUFFIX}', '${ADMIN_EMAIL}', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'ADMIN', 'ACTIVE', NOW()),
  ('buyer-user-${CASE_SUFFIX}', '${BUYER_EMAIL}', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'BUYER', 'ACTIVE', NOW())
ON CONFLICT (id) DO NOTHING;
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('seller-profile-${CASE_SUFFIX}', 'seller-user-${CASE_SUFFIX}', 'Soft Delete Store ${CASE_SUFFIX}', '')
ON CONFLICT (id) DO NOTHING;
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('prod-501', 'seller-profile-${CASE_SUFFIX}', 'Active Product', 'Visible toy product', 'toys', 2500, 9, '[]', 'ACTIVE', true, NOW() - INTERVAL '3 minutes'),
  ('prod-502', 'seller-profile-${CASE_SUFFIX}', 'Soft Deleted Product', 'Removed toy product', 'toys', 2600, 5, '[]', 'REMOVED', true, NOW() - INTERVAL '2 minutes'),
  ('prod-503', 'seller-profile-${CASE_SUFFIX}', 'Hidden Deleted Product', 'Removed hidden toy product', 'toys', 2700, 1, '[]', 'REMOVED', false, NOW() - INTERVAL '1 minute')
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

curl -sS -o "$ADMIN_LOGIN_RESPONSE" -w '%{http_code}' -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}" > "$ADMIN_LOGIN_STATUS"
[ "$(cat "$ADMIN_LOGIN_STATUS")" = "200" ]
ADMIN_TOKEN="$(jq -r '.token' "$ADMIN_LOGIN_RESPONSE")"
[ "$ADMIN_TOKEN" != "null" ]

curl -sS -o "$BUYER_LOGIN_RESPONSE" -w '%{http_code}' -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"${BUYER_PASSWORD}\"}" > "$BUYER_LOGIN_STATUS"
[ "$(cat "$BUYER_LOGIN_STATUS")" = "200" ]
BUYER_TOKEN="$(jq -r '.token' "$BUYER_LOGIN_RESPONSE")"
[ "$BUYER_TOKEN" != "null" ]

# When
curl -sS -o "$ADMIN_RESPONSE" -w '%{http_code}' "$BASE_URL/products?category=toys" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" > "$ADMIN_STATUS"
curl -sS -o "$BUYER_RESPONSE" -w '%{http_code}' "$BASE_URL/products?category=toys" \
  -H "Authorization: Bearer ${BUYER_TOKEN}" > "$BUYER_STATUS"

# Then
[ "$(cat "$ADMIN_STATUS")" = "200" ]
[ "$(cat "$BUYER_STATUS")" = "200" ]
jq -e 'type == "array" and length == 1 and .[0].id == "prod-501"' "$ADMIN_RESPONSE" >/dev/null
jq -e 'map(.id) | index("prod-502") == null and index("prod-503") == null' "$ADMIN_RESPONSE" >/dev/null
jq -e 'type == "array" and length == 1 and .[0].id == "prod-501"' "$BUYER_RESPONSE" >/dev/null
jq -e 'map(.id) | index("prod-502") == null and index("prod-503") == null' "$BUYER_RESPONSE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:soft_deleted_products_excluded_from_all_searches"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('prod-501', 'prod-502', 'prod-503');
DELETE FROM seller_profiles WHERE id = 'seller-profile-${CASE_SUFFIX}';
DELETE FROM users WHERE id IN ('seller-user-${CASE_SUFFIX}', 'admin-user-${CASE_SUFFIX}', 'buyer-user-${CASE_SUFFIX}');
SQL
