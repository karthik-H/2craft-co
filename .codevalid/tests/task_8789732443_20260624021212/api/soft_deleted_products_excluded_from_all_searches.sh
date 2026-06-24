#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_USER_ID="admin-user-${CASE_SUFFIX}"
ADMIN_EMAIL="admin-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
BUYER_USER_ID="buyer-user-${CASE_SUFFIX}"
BUYER_EMAIL="buyer-${CASE_SUFFIX}@example.com"
BUYER_PASSWORD='BuyerPass123!'
SELLER_USER_ID="seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-${CASE_SUFFIX}"
PROD1_ID="prod-501-${CASE_SUFFIX}"
PROD2_ID="prod-502-${CASE_SUFFIX}"
PROD3_ID="prod-503-${CASE_SUFFIX}"
ADMIN_LOGIN_RESPONSE="/tmp/soft_deleted_admin_login_${CASE_SUFFIX}.json"
ADMIN_LOGIN_STATUS="/tmp/soft_deleted_admin_login_${CASE_SUFFIX}.status"
BUYER_LOGIN_RESPONSE="/tmp/soft_deleted_buyer_login_${CASE_SUFFIX}.json"
BUYER_LOGIN_STATUS="/tmp/soft_deleted_buyer_login_${CASE_SUFFIX}.status"
ADMIN_RESPONSE_FILE="/tmp/soft_deleted_admin_response_${CASE_SUFFIX}.json"
ADMIN_STATUS_FILE="/tmp/soft_deleted_admin_response_${CASE_SUFFIX}.status"
BUYER_RESPONSE_FILE="/tmp/soft_deleted_buyer_response_${CASE_SUFFIX}.json"
BUYER_STATUS_FILE="/tmp/soft_deleted_buyer_response_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$ADMIN_LOGIN_RESPONSE" "$ADMIN_LOGIN_STATUS" "$BUYER_LOGIN_RESPONSE" "$BUYER_LOGIN_STATUS" "$ADMIN_RESPONSE_FILE" "$ADMIN_STATUS_FILE" "$BUYER_RESPONSE_FILE" "$BUYER_STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${SELLER_USER_ID}', 'seller-${CASE_SUFFIX}@example.com', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW()),
  ('${ADMIN_USER_ID}', '${ADMIN_EMAIL}', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'ADMIN', 'ACTIVE', NOW()),
  ('${BUYER_USER_ID}', '${BUYER_EMAIL}', '\$2a\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'BUYER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Soft Delete Store ${CASE_SUFFIX}', '');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'Active Product', 'Toy product available', 'toys', 1200, 5, '[]', 'ACTIVE', true, NOW() - INTERVAL '3 minutes'),
  ('${PROD2_ID}', '${SELLER_PROFILE_ID}', 'Soft Deleted Product', 'Removed toy visible', 'toys', 1300, 4, '[]', 'REMOVED', true, NOW() - INTERVAL '2 minutes'),
  ('${PROD3_ID}', '${SELLER_PROFILE_ID}', 'Hidden Deleted Product', 'Removed toy hidden', 'toys', 1400, 0, '[]', 'REMOVED', false, NOW() - INTERVAL '1 minute');
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
curl -sS -o "$ADMIN_RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?category=toys" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" > "$ADMIN_STATUS_FILE"
curl -sS -o "$BUYER_RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?category=toys" \
  -H "Authorization: Bearer ${BUYER_TOKEN}" > "$BUYER_STATUS_FILE"

# Then
[ "$(cat "$ADMIN_STATUS_FILE")" = "200" ]
[ "$(cat "$BUYER_STATUS_FILE")" = "200" ]
jq -e 'type == "array" and length == 1' "$ADMIN_RESPONSE_FILE" >/dev/null
jq -e 'type == "array" and length == 1' "$BUYER_RESPONSE_FILE" >/dev/null
jq -e --arg active "$PROD1_ID" --arg removed1 "$PROD2_ID" --arg removed2 "$PROD3_ID" '
  .[0].id == $active and
  (map(.id) | index($removed1) == null) and
  (map(.id) | index($removed2) == null)
' "$ADMIN_RESPONSE_FILE" >/dev/null
jq -e --arg active "$PROD1_ID" --arg removed1 "$PROD2_ID" --arg removed2 "$PROD3_ID" '
  .[0].id == $active and
  (map(.id) | index($removed1) == null) and
  (map(.id) | index($removed2) == null)
' "$BUYER_RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:soft_deleted_products_excluded_from_all_searches"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}', '${PROD3_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id IN ('${SELLER_USER_ID}', '${ADMIN_USER_ID}', '${BUYER_USER_ID}');
SQL
