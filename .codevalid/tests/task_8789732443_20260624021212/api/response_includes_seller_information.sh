#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-001-${CASE_SUFFIX}"
PROD1_ID="prod-801-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/response_includes_seller_information_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/response_includes_seller_information_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'seller-${CASE_SUFFIX}@example.com', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Tech Store', '');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'Gadget', 'Useful gadget', 'electronics', 4500, 11, '[]', 'ACTIVE', true, NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'type == "array"' "$RESPONSE_FILE" >/dev/null
jq -e --arg prod "$PROD1_ID" '
  map(select(.id == $prod)) as $matches |
  ($matches | length) == 1 and
  $matches[0].store_name == "Tech Store" and
  $matches[0].seller_status == "ACTIVE"
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:response_includes_seller_information"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id = '${PROD1_ID}';
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
SQL
