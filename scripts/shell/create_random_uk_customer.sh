#!/usr/bin/env bash
# Creates a fresh, fully sanitized UK BACS test customer end-to-end:
# Account/Contact (via the real RestUpsertAccount integration path) -> Contract -> Contract Product
# -> Order/OrderItem -> Invoice -> finalize -> Payment__c (Stripe-routed).
#
# Built from a real prod RestUpsertAccount payload (Event_Log__c -> OAuth_Log__c.Request_Body__c),
# sanitized: PII replaced, real bank account swapped for Stripe's official BACS test account.
#
# Usage:
#   scripts/shell/create_random_uk_customer.sh [org] [paymentMethodCode] [price]
#   scripts/shell/create_random_uk_customer.sh dev I8 11.25
#
# Defaults: org=dev, paymentMethodCode=I8 (Stripe), price=11.25 (GBP)

set -euo pipefail

ORG="${1:-dev}"
PAYMENT_METHOD="${2:-I8}"
PRICE="${3:-11.25}"

# --- Fixed reference data (dev org UK fixtures) ---
UK_ADMINISTRATION_ID="a0Ubd0000028FdXEAU"
UK_PRICEBOOK_ID="01s3W000000TXaBQAW"          # "2022 - UK - All - Subscriptions"
UK_PRODUCT_ID="01tbR000001aD4bQAE"            # "iTrack S5 Monthly DD"
UK_PRICEBOOK_ENTRY_ID="01ubR000000W73CQAS"
TEST_EMAIL="teun.rietman@outlook.com"
BANK_ACCOUNT_NUMBER="00012345"                # Stripe's official "always succeeds" BACS test account

# --- Randomize identity ---
FIRST_NAMES=(James Oliver Harry George Jack Charlie Thomas Alfie Freddie Archie Emily Sophie Olivia Amelia Isla Grace Ava Poppy Ruby Lily)
LAST_NAMES=(Smith Jones Taylor Brown Williams Wilson Johnson Davies Robinson Wright Thompson Evans Walker White Roberts Green Hall Wood Clarke Hughes)
STREETS=("Furze Hill Road" "Mill Lane" "Church Street" "Station Road" "High Street" "Manor Way" "Elm Grove" "Oak Avenue" "Kings Road" "Victoria Street")
CITIES=("Shipston-on-Stour" "Leamington Spa" "Stratford-upon-Avon" "Coventry" "Banbury" "Warwick" "Rugby" "Kenilworth")

RAND_FIRST="${FIRST_NAMES[$RANDOM % ${#FIRST_NAMES[@]}]}"
RAND_LAST="${LAST_NAMES[$RANDOM % ${#LAST_NAMES[@]}]}"
RAND_STREET_NUM=$((RANDOM % 200 + 1))
RAND_STREET="${STREETS[$RANDOM % ${#STREETS[@]}]}"
RAND_CITY="${CITIES[$RANDOM % ${#CITIES[@]}]}"
RAND_POSTCODE="CV$((RANDOM % 99))  $((RANDOM % 9))$(printf "%c%c" $((65 + RANDOM % 26)) $((65 + RANDOM % 26)))"
RAND_PHONE_SUFFIX=$(printf "%06d" $((RANDOM % 1000000)))

# Unique fake external IDs (Ofcom-range fake phone numbers, "07700 900xxx" is the reserved fictional block)
TS=$(date +%s)
ACCOUNT_EXT_ID="9${TS: -6}0"
CONTACT_EXT_ID="9${TS: -6}1"
BILLING_EXT_ID="9${TS: -6}2"
PHONE="+4477009${RAND_PHONE_SUFFIX:0:5}"
MOBILE="+4477009${RAND_PHONE_SUFFIX:1:5}"

echo "Creating random UK test customer: ${RAND_FIRST} ${RAND_LAST} (org: ${ORG}, payment method: ${PAYMENT_METHOD}, price: ${PRICE} GBP)"

# --- Step 1: Account + Contact via the real RestUpsertAccount integration path ---
PAYLOAD_FILE="/tmp/upsert_account_$$_${RANDOM}.json"
cat > "$PAYLOAD_FILE" <<JSON
{
  "id": ${ACCOUNT_EXT_ID},
  "name": "${RAND_FIRST} ${RAND_LAST}",
  "isBusiness": false,
  "isDealer": false,
  "contactDTOs": [
    {
      "id": ${CONTACT_EXT_ID},
      "accountId": ${CONTACT_EXT_ID},
      "salutation": "Mr",
      "firstName": "${RAND_FIRST}",
      "insertion": "",
      "surName": "${RAND_LAST}",
      "email": "${TEST_EMAIL}",
      "function": null,
      "phoneNumber": "${PHONE}",
      "mobilePhone": "${MOBILE}",
      "otherPhone": "",
      "language": "en",
      "street": "${RAND_STREET_NUM} ${RAND_STREET}",
      "houseNumber": "",
      "city": "${RAND_CITY}",
      "country": "",
      "isActive": false,
      "hasDealerTaskAccess": false,
      "isAdministrator": false
    }
  ],
  "visitAddress": {
    "id": ${CONTACT_EXT_ID},
    "accountId": ${CONTACT_EXT_ID},
    "firstName": "${RAND_FIRST}",
    "insertion": "",
    "surName": "${RAND_LAST}",
    "email": "${TEST_EMAIL}",
    "phoneNumber": "${PHONE}",
    "mobilePhone": "${MOBILE}",
    "otherPhone": "",
    "street": "${RAND_STREET_NUM} ${RAND_STREET}",
    "houseNumber": "",
    "postalCode": "${RAND_POSTCODE}",
    "city": "${RAND_CITY}",
    "country": "GB"
  },
  "billingAddress": {
    "id": ${BILLING_EXT_ID},
    "accountId": ${BILLING_EXT_ID},
    "firstName": "${RAND_FIRST}",
    "surName": "${RAND_LAST}",
    "email": "${TEST_EMAIL}",
    "phoneNumber": "${PHONE}",
    "mobilePhone": "${MOBILE}",
    "otherPhone": "",
    "street": "${RAND_STREET_NUM} ${RAND_STREET}",
    "houseNumber": "",
    "postalCode": "${RAND_POSTCODE}",
    "city": "${RAND_CITY}",
    "country": "GB"
  },
  "paymentMethodExactCode": "I0",
  "resellerId": 6,
  "platformId": 3,
  "bankAccountHolder": "MR $(echo "${RAND_FIRST} ${RAND_LAST}" | tr '[:lower:]' '[:upper:]')",
  "bankAccountNumber": "${BANK_ACCOUNT_NUMBER}",
  "bankAccountBic": "",
  "directDebitReference": "TEST${ACCOUNT_EXT_ID} MI",
  "directDebitLastTakenDate": "1970-01-01 01:00:00.0000",
  "directDebitStatus": "TO_BE_SENT",
  "marketId": "1"
}
JSON

RESPONSE=$(sf api request rest "/services/apexrest/UpsertAccount" -o "$ORG" -X POST -H "Content-Type:application/json" -b "@${PAYLOAD_FILE}")
rm -f "$PAYLOAD_FILE"

ACCOUNT_ID=$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(next(r['sfId'] for r in d['addedRecords'] if r['type']=='Account'))")
echo "Account created: ${ACCOUNT_ID}"

CONTACT_ID=$(sf data query -o "$ORG" --json -q "SELECT ContactId FROM AccountContactRelation WHERE AccountId = '${ACCOUNT_ID}' AND IsActive = true LIMIT 1" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['records'][0]['ContactId'])")
echo "Contact: ${CONTACT_ID}"

# --- Step 2: Contract (set Pricebook + CurrencyIsoCode explicitly at create time -
#     both lock/mismatch after activation if left to default, see 2026-09-01 session) ---
CONTRACT_ID=$(sf data create record -o "$ORG" -s Contract --json -v \
  "AccountId=${ACCOUNT_ID} Status=Draft Subscription25__Administration__c=${UK_ADMINISTRATION_ID} StartDate=$(date +%F) ContractTerm=12 Pricebook2Id=${UK_PRICEBOOK_ID} CurrencyIsoCode=GBP" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['id'])")
sf data update record -o "$ORG" -s Contract -i "$CONTRACT_ID" -v "Status=Activated" > /dev/null
sf data update record -o "$ORG" -s Contract -i "$CONTRACT_ID" -v "Payment_Method__c=${PAYMENT_METHOD}" > /dev/null
echo "Contract activated: ${CONTRACT_ID} (Payment_Method__c=${PAYMENT_METHOD})"

# --- Step 3: Contract Product ---
CP_ID=$(sf data create record -o "$ORG" -s Subscription25__Contract_Product__c --json -v \
  "Subscription25__Contract__c=${CONTRACT_ID} Subscription25__Product__c=${UK_PRODUCT_ID} Subscription25__Quantity__c=1 Subscription25__Price__c=${PRICE} Subscription25__Start_Date__c=$(date +%F) Subscription25__Status__c=Draft CurrencyIsoCode=GBP" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['id'])")
sf data update record -o "$ORG" -s Subscription25__Contract_Product__c -i "$CP_ID" -v "Subscription25__Status__c=Activated" > /dev/null
echo "Contract Product activated: ${CP_ID}"

# --- Step 4: Invoice (DRAFT) ---
GROSS=$(python3 -c "print(round(${PRICE} * 1.2, 2))")
INVOICE_ID=$(sf data create record -o "$ORG" -s Subscription25__Invoice__c --json -v \
  "Subscription25__Account__c=${ACCOUNT_ID} Subscription25__Administration__c=${UK_ADMINISTRATION_ID} Subscription25__Contact_Person__c=${CONTACT_ID} Subscription25__Invoice_Date__c=$(date +%F) Subscription25__Due_Date__c=$(date -v+8d +%F 2>/dev/null || date -d '+8 days' +%F) Subscription25__Total_Amount__c=${PRICE} Subscription25__Gross_Amount__c=${GROSS} Payment_Method__c=${PAYMENT_METHOD} CurrencyIsoCode=GBP Subscription25__Status__c=DRAFT Subscription25__Billing_Country__c='United Kingdom'" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['id'])")
echo "Invoice (draft): ${INVOICE_ID}"

# --- Step 5: Order + OrderItem, linked to the Invoice, activated ---
ORDER_ID=$(sf data create record -o "$ORG" -s Order --json -v \
  "AccountId=${ACCOUNT_ID} Status=Draft EffectiveDate=$(date +%F) EndDate=$(date -v+1m +%F 2>/dev/null || date -d '+1 month' +%F) Pricebook2Id=${UK_PRICEBOOK_ID} Subscription25__Administration__c=${UK_ADMINISTRATION_ID} CurrencyIsoCode=GBP" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['id'])")
sf data create record -o "$ORG" -s OrderItem -v \
  "OrderId=${ORDER_ID} Product2Id=${UK_PRODUCT_ID} PricebookEntryId=${UK_PRICEBOOK_ENTRY_ID} Quantity=1 UnitPrice=${PRICE} Subscription25__Product__c=${UK_PRODUCT_ID}" > /dev/null
sf data update record -o "$ORG" -s Order -i "$ORDER_ID" -v "Status=Activated" > /dev/null
sf data update record -o "$ORG" -s Order -i "$ORDER_ID" -v "Subscription25__Invoice__c=${INVOICE_ID}" > /dev/null
echo "Order activated: ${ORDER_ID}"

# --- Step 6: Finalize the Invoice -> triggers rau_Subscription25_Invoice_c_Finalized_Create_Payment ---
sf data update record -o "$ORG" -s Subscription25__Invoice__c -i "$INVOICE_ID" -v "Subscription25__Status__c=FINALIZED" > /dev/null
echo "Invoice finalized, waiting for async Payment creation..."
sleep 10

PAYMENT=$(sf data query -o "$ORG" --json -q "SELECT Id, Name, Status__c, Processor__c, Amount_Gross__c FROM Payment__c WHERE Invoice__c = '${INVOICE_ID}'")
echo "$PAYMENT" | python3 -c "
import json, sys
recs = json.load(sys.stdin)['result']['records']
if not recs:
    print('No Payment created yet - check Payment_Setting__mdt for Reseller=6, Method=${PAYMENT_METHOD} (AutoCreate__c must be true, Processor__c=Stripe).')
else:
    p = recs[0]
    print(f\"Payment created: {p['Name']} ({p['Id']}) - {p['Status__c']} - {p['Amount_Gross__c']} GBP - {p['Processor__c']}\")
"

echo ""
echo "Summary: Account=${ACCOUNT_ID}  Contract=${CONTRACT_ID}  ContractProduct=${CP_ID}  Order=${ORDER_ID}  Invoice=${INVOICE_ID}"
