#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-${CASE_SUFFIX}"
PROD1_ID="prod-601-${CASE_SUFFIX}"
PROD2_ID="prod-602-${CASE_SUFFIX}"
PROD3_ID="prod-603-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/combined_filters_category_and_stock_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/combined_filters_category_and_stock_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'seller-${CASE_SUFFIX}@example.com', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Combined Filter Store ${CASE_SUFFIX}', '');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'Gaming Laptop', 'Electronics with stock', 'electronics', 150000, 10, '[]', 'ACTIVE', true, NOW() - INTERVAL '3 minutes'),
  ('${PROD2_ID}', '${SELLER_PROFILE_ID}', 'Gaming Mouse', 'Electronics out of stock', 'electronics', 5000, 0, '[]', 'ACTIVE', true, NOW() - INTERVAL '2 minutes'),
  ('${PROD3_ID}', '${SELLER_PROFILE_ID}', 'Fiction Book', 'Books with stock', 'books', 2000, 15, '[]', 'ACTIVE', true, NOW() - INTERVAL '1 minute');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?category=electronics&in_stock=true" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'type == "array" and length == 1' "$RESPONSE_FILE" >/dev/null
jq -e --arg p1 "$PROD1_ID" --arg p2 "$PROD2_ID" --arg p3 "$PROD3_ID" '
  .[0].id == $p1 and
  .[0].category == "electronics" and
  .[0].stock_qty > 0 and
  (map(.id) | index($p2) == null) and
  (map(.id) | index($p3) == null)
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:combined_filters_category_and_stock"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}', '${PROD3_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
SQL
