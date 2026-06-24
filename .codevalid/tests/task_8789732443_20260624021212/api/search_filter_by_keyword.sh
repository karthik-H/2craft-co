#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/search_filter_by_keyword_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/search_filter_by_keyword_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('seller-user-${CASE_SUFFIX}', 'seller-${CASE_SUFFIX}@example.com', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW())
ON CONFLICT (id) DO NOTHING;
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('seller-profile-${CASE_SUFFIX}', 'seller-user-${CASE_SUFFIX}', 'Keyword Store ${CASE_SUFFIX}', '')
ON CONFLICT (id) DO NOTHING;
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('prod-301', 'seller-profile-${CASE_SUFFIX}', 'Wireless Mouse', 'Fast wireless mouse', 'electronics', 2500, 8, '[]', 'ACTIVE', true, NOW() - INTERVAL '3 minutes'),
  ('prod-302', 'seller-profile-${CASE_SUFFIX}', 'Mechanical Keyboard', 'Clicky keyboard', 'electronics', 6500, 5, '[]', 'ACTIVE', true, NOW() - INTERVAL '2 minutes'),
  ('prod-303', 'seller-profile-${CASE_SUFFIX}', 'Studio Headphones', 'Wireless audio with great battery', 'electronics', 8900, 6, '[]', 'ACTIVE', true, NOW() - INTERVAL '1 minute')
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
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?keyword=wireless" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'type == "array" and length == 2' "$RESPONSE_FILE" >/dev/null
jq -e 'map(.id) | index("prod-301") != null and index("prod-303") != null and index("prod-302") == null' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:search_filter_by_keyword"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('prod-301', 'prod-302', 'prod-303');
DELETE FROM seller_profiles WHERE id = 'seller-profile-${CASE_SUFFIX}';
DELETE FROM users WHERE id = 'seller-user-${CASE_SUFFIX}';
SQL
