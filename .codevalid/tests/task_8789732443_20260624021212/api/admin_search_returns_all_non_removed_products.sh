#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
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
  ('seller-user-${CASE_SUFFIX}', 'seller-${CASE_SUFFIX}@example.com', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW()),
  ('admin-user-${CASE_SUFFIX}', '${ADMIN_EMAIL}', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'ADMIN', 'ACTIVE', NOW())
ON CONFLICT (id) DO NOTHING;
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('seller-profile-${CASE_SUFFIX}', 'seller-user-${CASE_SUFFIX}', 'Admin Search Store ${CASE_SUFFIX}', '')
ON CONFLICT (id) DO NOTHING;
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('prod-001', 'seller-profile-${CASE_SUFFIX}', 'Widget A', 'Admin search visible product', 'electronics', 1000, 8, '[]', 'ACTIVE', true, NOW() - INTERVAL '3 minutes'),
  ('prod-002', 'seller-profile-${CASE_SUFFIX}', 'Widget B', 'Admin search hidden product', 'electronics', 1100, 4, '[]', 'ACTIVE', false, NOW() - INTERVAL '2 minutes'),
  ('prod-003', 'seller-profile-${CASE_SUFFIX}', 'Widget C', 'Admin search visible product newest', 'electronics', 1200, 2, '[]', 'ACTIVE', true, NOW() - INTERVAL '1 minute'),
  ('prod-004', 'seller-profile-${CASE_SUFFIX}', 'Deleted Widget', 'Removed product should stay hidden', 'electronics', 1300, 1, '[]', 'REMOVED', true, NOW())
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
jq -e 'type == "array"' "$RESPONSE_FILE" >/dev/null
jq -e 'length == 3' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].id == "prod-003" and .[1].id == "prod-002" and .[2].id == "prod-001"' "$RESPONSE_FILE" >/dev/null
jq -e 'map(.id) | index("prod-001") != null and index("prod-002") != null and index("prod-003") != null' "$RESPONSE_FILE" >/dev/null
jq -e 'map(.id) | index("prod-004") == null' "$RESPONSE_FILE" >/dev/null
jq -e 'all(.[]; has("id") and has("title") and has("category") and has("price_cents") and has("stock_qty") and has("status") and has("visible") and has("store_name"))' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:admin_search_returns_all_non_removed_products"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('prod-001', 'prod-002', 'prod-003', 'prod-004');
DELETE FROM seller_profiles WHERE id = 'seller-profile-${CASE_SUFFIX}';
DELETE FROM users WHERE id IN ('seller-user-${CASE_SUFFIX}', 'admin-user-${CASE_SUFFIX}');
SQL
