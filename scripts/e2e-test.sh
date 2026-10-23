#!/usr/bin/env bash
# Quick end-to-end smoke test WITHOUT n8n editor, WhatsApp or Telegram clicks.
# Usage:  BASE=https://your-n8n.example.com ./hgt-e2e-test.sh
BASE="${BASE:-http://localhost:5678}"
DATE=$(date -d "+1 day" +%F 2>/dev/null || date -v+1d +%F)
H='Content-Type: application/json'
pass(){ echo "✅ $1"; }; fail(){ echo "❌ $1"; FAILED=1; }

echo "1) Part 1 - customer asks in Italian"
R1=$(curl -s -X POST "$BASE/webhook/hgt-whatsapp" -H "$H" -d '{"from":"e2e","text":"Ciao! Quali tour avete e quanto costano?"}')
echo "$R1" | grep -q '"reply"' && pass "agent replied: $(echo "$R1" | head -c 140)" || fail "no reply: $R1"

echo "2) Part 2 - create booking + payment link"
R2=$(curl -s -X POST "$BASE/webhook/hgt-create-booking" -H "$H" -d "{\"tour_id\":\"sunset\",\"date\":\"$DATE\",\"time\":\"18:00\",\"people\":2,\"customer_name\":\"E2E Test\"}")
REF=$(echo "$R2" | sed -n 's/.*"booking_reference":"\([^"]*\)".*/\1/p')
[ -n "$REF" ] && pass "booking $REF" || fail "no booking: $R2"
echo "$R2" | grep -q '"amount_eur":98' && pass "price 98 correct" || fail "wrong price: $R2"

echo "3) Stripe 'paid' event -> Part 2 marks paid -> Part 3 dispatches"
R3=$(curl -s -X POST "$BASE/webhook/hgt-stripe-webhook" -H "$H" -d "{\"type\":\"checkout.session.completed\",\"data\":{\"object\":{\"amount_total\":9800,\"metadata\":{\"booking_ref\":\"$REF\",\"bokun_booking_id\":\"BK-$REF\",\"tour_name\":\"Sunset Viewpoints Tour\",\"date\":\"$DATE\",\"time\":\"18:00\",\"people\":\"2\",\"customer_name\":\"E2E Test\"}}}}")
echo "$R3" | grep -q 'received' && pass "Stripe event acknowledged" || fail "no ack: $R3"

echo "4) Part 4 - driver reports cash (replies in your Telegram chat)"
CHAT="${CHAT_ID:-0}"
curl -s -o /dev/null -w "ledger webhook HTTP %{http_code}\n" -X POST "$BASE/webhook/hgt-ledger" -H "$H" -d "{\"chat_id\":\"$CHAT\",\"driver\":\"E2E Test Driver\",\"text\":\"/cash $REF 98\"}"
echo "Now check Google Sheet tabs: Jobs has $REF (OPEN), CashLedger has $REF cash 98."
[ -z "$FAILED" ] && echo "ALL API CHECKS PASSED" || { echo "SOME CHECKS FAILED"; exit 1; }
