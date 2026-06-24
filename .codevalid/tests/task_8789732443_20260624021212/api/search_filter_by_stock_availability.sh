#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/search_filter_by_stock_availability_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/search_filter_by_stock_availability_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('seller-user-${CASE_SUFFIX}', 'seller-${CASE_SUFFIX}@example.com', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW())
ON CONFLICT (id) DO NOTHING;
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('seller-profile-${CASE_SUFFIX}', 'seller-user-${CASE_SUFFIX}', 'Stock Store ${CASE_SUFFIX}', '')
ON CONFLICT (id) DO NOTHING;
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('prod-401', 'seller-profile-${CASE_SUFFIX}', 'In Stock Item', 'Available home item', 'home', 2200, 50, '[]', 'ACTIVE', true, NOW() - INTERVAL '3 minutes'),
  ('prod-402', 'seller-profile-${CASE_SUFFIX}', 'Out of Stock Item', 'Unavailable home item', 'home', 2300, 0, '[]', 'SOLD_OUT', true, NOW() - INTERVAL '2 minutes'),
  ('prod-403', 'seller-profile-${CASE_SUFFIX}', 'Low Stock Item', 'Limited home item', 'home', 2400, 3, '[]', 'ACTIVE', true, NOW() - INTERVAL '1 minute')
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

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?category=home&in_stock=true" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'type == "array" and length == 2' "$RESPONSE_FILE" >/dev/null
jq -e 'map(.id) | index("prod-401") != null and index("prod-403") != null and index("prod-402") == null' "$RESPONSE_FILE" >/dev/null
jq -e 'all(.[]; .stock_qty > 0)' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:search_filter_by_stock_availability"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('prod-401', 'prod-402', 'prod-403');
DELETE FROM seller_profiles WHERE id = 'seller-profile-${CASE_SUFFIX}';
DELETE FROM users WHERE id = 'seller-user-${CASE_SUFFIX}';
SQL
