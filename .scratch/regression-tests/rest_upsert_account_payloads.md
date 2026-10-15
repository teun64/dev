# Rest_UpsertAccount regression payloads

Re-run these against `/UpsertAccount` (dev sandbox) whenever automation on
Account, AccountContactRelation, or Contact changes — specifically:
`Rest_UpsertAccount.cls`, `Rest_UpsertAccountV2.cls`,
`afl_AccountContactRelation_Roles`, `rab_AccountContactRelation_Roles`,
`rbb_AccountContactRelation`, `rbb_Account`, or any Validation Rule on these
three objects.

They reproduce the operator-precedence bug fixed in `Rest_UpsertAccount.cls`
(2026-07-02/03): a contact with blank `Roles` could pick up `Invoice` on a
repeat sync even when it wasn't the designated billing contact, and the
Flow's role-exclusivity logic would then strip `Invoice` from the *actual*
billing contact instead.

## Customer 1: REBEL Lease B.V. (external id `48767`)

Use a **fresh** external id (`48767` was reused multiple times during testing
and the account was deleted/recreated — pick a new one, or delete the
existing account+contacts first). Set `salesforceId` to `null` at both the
account and contact level for a true fresh-creation test.

### Call 1 — initial creation

```json
{"id":"48767","salesforceId":null,"debtorNumber":"12218365","name":"REBEL Lease B.V.","isBusiness":true,"isDealer":false,"vatNumber":"NL855684914B01","cocNumber":"64482960","paymentMethodExactCode":"08","bankAccountHolder":"Rebel Lease bv","bankAccountNumber":"NL53ABNA0840799292","bankAccountBic":"ABNANL2A","contactDTOs":[{"id":"283490","salesforceId":null,"accountId":"48767","firstName":"Mart ","insertion":"van den","surName":"Heuvel","email":"m.vandenheuvel@psv.nl","function":null,"phoneNumber":"+31653456398","language":"nl","street":null,"postalCode":null,"city":null,"country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":false,"mobilePhone":null,"otherPhone":null,"isDeleted":false}],"visitAddress":{"id":"50819","accountId":"48767","firstName":"Chris","insertion":null,"surName":"Jonker","email":"chris@rebellease.nl","phoneNumber":"+31889960101","street":"Hondsruglaan 87","postalCode":"5628 DB","city":"Eindhoven","country":"NL","mobilePhone":null,"otherPhone":null,"language":null},"billingAddress":{"id":"65297","accountId":"48767","firstName":"Afdeling","insertion":null,"surName":"Administratie","email":"facturen@rebellease.nl","phoneNumber":"+31889960101","street":"Lijnbaan 12","postalCode":"2352 CK","city":"Leiderdorp","country":"NL","mobilePhone":null,"otherPhone":null,"language":null},"isBlocked":false,"resellerId":1,"primarySbiCode":"77111","secondarySbiCode1":"","secondarySbiCode2":"","privacyMode":false,"platformId":1,"personnelCount":1,"fulltimePersonnelCount":1,"directDebitStatus":null,"directDebitReference":null,"directDebitLastTakenDate":null,"marketId":"1","previousDebtorNumber":null,"shortName":null,"orderOffsetTerm":null,"echoesAccountId":null}
```

**Expected result:**
| Contact | Roles |
|---|---|
| Mart van den Heuvel | *(none)* |
| Chris Jonker (visitAddress) | `Main;Shipping` (accountIsNew=true) |
| Afdeling Administratie (billingAddress) | `Invoice;Digital` |

`Account.Contact_Billing__c` → Afdeling Administratie.

### Call 2+ — repeat/re-sync (this is the case that used to break)

Resend the same payload (optionally add a new `contactDTOs` entry, e.g. a
"Frans Janssen" contact, to also confirm new-contact-on-repeat-call
behavior). Repeat several times.

**Expected result — must NOT change on repeat calls:**
- Mart van den Heuvel stays roleless.
- Afdeling Administratie stays `Invoice;Digital`.
- Chris Jonker **keeps** `Main;Shipping` (since 2026-10-15 Shipping moves with Main;
  before, it dropped to `Main` on every update).
- Roles set in Salesforce (Reminder, Payment, Sales, Service, ASR) survive every call.
- `Contact_Billing__c` never moves off Afdeling Administratie.

**Bug symptom if it regresses:** Mart van den Heuvel's `Roles` flips to
`Invoice`, Afdeling Administratie's `Roles` drops to `Digital` (loses
`Invoice`), and `Contact_Billing__c` moves to Mart.

## Customer 2: Horizon Exploitatie B.V. (external id `28378`)

**TODO — payload not captured.** This test used a "same person is both
visitAddress and billingAddress" edge case (Femke Gasseling), which combines
to `Main;Shipping;Invoice;Digital` on first creation, then `Main;Invoice;Digital`
on repeat (since 2026-10-15 `Shipping` is kept on repeat). A second contact ("Westfort (wiely)knuiman", then later "Fleetmanagement
Flexcraft", then "Vion Boxtel (daan)") was added across repeat calls, each
landing with no role. Ask Teun for the actual request bodies to fill this in.

**Expected result:**
- Femke Gasseling (visit+billing, same person): `Main;Invoice;Digital` (or
  `Main;Shipping;Invoice;Digital` on the very first/fresh call).
- All other contacts: roleless.
- `Contact_Billing__c` → Femke Gasseling, never drifts across repeat calls.


## Role rules since 2026-10-15 (Rest_UpsertAccount.platformRoles, user decision)
- Main follows the visit contact (only changed when the payload has a visit address).
- Invoice follows the billing contact, or the visit contact when billing is empty / the same.
- Digital: B2B only, and only on a relation that has Invoice (before or after); then follows the payload.
- Shipping and Payment: move with Main (only changed on a relation that has Main before or after; the
  visit contact always carries Main;Shipping;Payment), no B2B check.
- Reminder: moves with Invoice (only changed on a relation that has Invoice before or after; the invoice
  contact carries Invoice;Reminder), no B2B check.
- Sales, Service, ASR: never touched. Payload wins over the lookups;
  afl_AccountContactRelation_Roles moves the lookups and keeps one Main/Invoice/Shipping per account.
Dev run 2026-10-15 (external id 948767): 3 calls stable + Reminder/Payment kept on a 4th call; rerun after the Shipping-with-Main change (848768): 3 calls stable.

### acc run 2026-10-15 (fix deployed 0AfG500000T16kDKAR, role flows activated to the prod versions afl v5 / rab v2)
- REBEL Lease 748767 (acc 001G500001TfKeSIAV): 3 calls stable, Reminder/Payment kept on a 4th call.
- 12 prod requests replayed twice each (OAuth_Log__c.Request_Body__c of RestUpsertAccount, salesforceIds cleared):
  roles identical after create and update; lookups set by the async roles flow.

| Prod event log | Account (ext id, platform) | acc account | Roles after 2 calls |
| --- | --- | --- | --- |
| a1ITx0000049JFdMAM | Nerisa Research B.V. (99239, 1) B2B | 001G500001TgSY9IAN | Felipe Admiraal: Main;Invoice;Shipping;Digital |
| a1ITx0000049IY5MAM | Jelle van der Sanden (124732, 1) B2C | 001G500001TgElLIAV | Jelle van der Sanden: Main;Invoice;Shipping |
| a1ITx0000049G1eMAE | Roundabout Food & Beverage B.V. (89268, 1) B2B, separate billing | 001G500001TgB5MIAV | Petro Blesing (petro@): Main;Shipping; Petro Blesing (finance@): Invoice;Digital |
| a1ITx0000049FvBMAU | Thomas Roeleveld (15105, 5) B2C | 001G500001Tg8wiIAB | Thomas Roeleveld: Main;Invoice;Shipping |
| a1ITx0000048WtFMAU | Klaas Bakker (124735, 1) B2C | 001G500001TgQZaIAN | Klaas Bakker: Main;Invoice;Shipping |
| a1ITx0000048WWfMAM | Newboyz (31007, 1) B2B | 001G500001TgQXyIAN | Ralph Ernst: Main;Invoice;Shipping;Digital |
| a1ITx0000048O4TMAU | L.I. Holding Zeeland B.V. (124733, 1) B2B | 001G500001TgDsWIAV | Pelo De Cock: Main;Invoice;Shipping;Digital |
| a1ITx0000048BonMAE | Schoen Transport B.V. (75281, 5) B2B | 001G500001TgSjRIAV | Nicolaas Schoen: Main;Invoice;Shipping;Digital |
| a1ITx00000489BtMAI | Dawn Cottam (84991, 3) B2C | 001G500001TgPAWIA3 | Dawn Cottam: Main;Invoice;Shipping |
| a1ITx0000047rq5MAA | Open Minded IT B.V. (54970, 1) B2B | 001G500001Tg1wEIAR | Simon van Sleuwen: Main;Invoice;Shipping;Digital |
| a1ITx0000047lW9MAI | J Kane (85062, 3) B2C | 001G500001TgS9yIAF | J Kane: Main;Invoice;Shipping |
| a1ITx0000045z3lMAA | FOUTHOUT Academy B.V. (91394, 5) B2B | 001G500001Tg38YIAR | Peter van Eijsden: Main;Invoice;Shipping;Digital |

### acc retest 2026-10-15 with Payment/Reminder rules (acc 0AfG500000T16U6KAJ, dev 0Afbd00000Bfk6zCAB, 23/23)
Per account: call 1, then random Sales/Service/ASR on every relation (+ Payment on non-Main, Reminder on non-Invoice
relations), wait for the roles flow, call 2. REBEL Lease 748768 (001G500001TgOuMIAV) + the 12 accounts above.
- Sales/Service/ASR untouched on every relation of all 13 accounts.
- Payment back on the visit contact, Reminder back on the invoice contact after call 2 (REBEL, Roundabout).
- The roles flow keeps Main/Invoice/Shipping/Reminder/Digital/Payment unique per account, so hand-added Payment /
  Reminder on another contact are moved by the flow, not by the REST call.
- **Found: lost-update race in afl_AccountContactRelation_Roles.** Two role changes in one transaction (Chris gets
  Payment, Afdeling gets Reminder) start two async runs that both rewrite Mart from the same snapshot; the last one
  wins → REBEL ends with Payment on Chris AND Mart. Pre-existing flow issue, not the REST code.

### Roles flow replaced by Apex (dev 2026-10-15, 0Afbd00000BfkYRCAZ)
`Svc_AccountContactRelationRoles` (AccountContactRelation trigger, after insert/update) replaces rab_/afl_AccountContactRelation_Roles
(rab deactivated in dev, repo status Obsolete). Per account once per save: owner per unique role = the relation that gained it
(last one wins), others lose it, lookups follow the owners, no-email removal + alert; synchronous.
Dev rerun of the acc race (848768): Mart held Payment;Reminder;Service, platform call gave Chris Payment and Afdeling Reminder
→ Mart = Service only, Chris Sales;Main;Shipping;Payment, Afdeling ASR;Reminder;Invoice;Digital, lookups correct immediately.
Tests: Test_Svc_AccountContactRelationRoles 6/6 (90%), with Test_Rest_UpsertAccount + Test_Svc_FinancialSystemContactRemoval 36/36;
20 role/lookup test classes: 177/190, the 13 failures are dev setup only (no integration user, no MI connection config).

### acc round 2026-10-15 – Apex roles logic (acc 0AfG500000T1DiTKAV, 36/36; rab_AccountContactRelation_Roles deactivated in acc)
- REBEL Lease 748769 (001G500001Th3RGIAZ): 3 calls → Chris Main;Payment;Shipping, Afdeling Digital;Invoice;Reminder, Mart none.
  Race scenario (Mart Payment;Reminder;Service, Chris/Afdeling without) + platform call → Mart Service only, Chris
  Main;Payment;Sales;Shipping, Afdeling ASR;Digital;Invoice;Reminder.
- 12 replayed prod accounts with random roles first: every unique role on at most one contact, lookups on the owners,
  Sales/Service/ASR untouched on all.
- Leftover test data from the flow era: REBEL 748768 (001G500001TgOuMIAV) still has Payment on Chris and Mart (pre-fix).

### acc run 2 – 21 fresh prod requests (2026-10-15, Apex roles + REST rules live in acc)
Each request: call 1, random Sales/Service/ASR (+ Payment on non-Main, Reminder on non-Invoice contacts), call 2. Checks: visit contact
(by payload email) has Main;Shipping;Payment, invoice contact Invoice;Reminder (+ Digital B2B), every unique role on at most one
contact, lookups on the owners, Sales/Service/ASR untouched. **All 21: both calls OK, no issues, Sales/Service/ASR untouched.**
Includes 4 German PascalCase payloads (platform 2). Found: 1,720 of 2,083 acc relations have no CompositeKey__c (prod: 0 of 229,085),
so on 3 pre-existing acc accounts call 1 could not update the relations (upsert on CompositeKey__c, allOrNone=false, failures
ignored = silent); call 2 fixed them after a save had filled the key. acc data drift; the silent failure is an open point.

| Prod event log | Account (ext id, platform) | Case | acc account |
| --- | --- | --- | --- |
| a1ITx0000049a8PMAQ | J W van Heezik (124740, 1) | camel / B2C / billing=visit / dtos1 | 001G500001TgEx8IAF |
| a1ITx0000049XyXMAU | Theo Laport (124739, 1) | camel / B2C / billing=visit / dtos1 | 001G500001Tgxc2IAB |
| a1ITx0000049a6nMAA | Koot Infrawerken (9685, 1) | camel / B2B / sep-billing / dtos0 | 001G500001TgnLFIAZ |
| a1ITx0000049TbZMAU | Gerard de Nijs Transport en Kraanverhuur (97868, 1) | camel / B2B / sep-billing / dtos0 | 001G500000sZ6t4IAC |
| a1ITx0000049a3ZMAQ | John Trainor (16461, 3) | camel / B2C / billing=visit / dtos1 | 001G500001Tgs63IAB |
| a1ITx0000049Xk1MAE | M__ Tustian (85055, 3) | camel / B2C / billing=visit / dtos1 | 001G500001TgHBnIAN |
| a1ITx0000049OvGMAU | Moving Intelligence B.V. (1, 1) | camel / B2B / billing=visit / dtos1 | 001G500000rBs9pIAC |
| a1ITx0000049S2nMAE | Hanneman B.V. (124737, 1) | camel / B2B / billing=visit / dtos1 | 001G500001Th3uKIAR |
| a1ITx0000049Jp8MAE | Solutio 365 B.V. (76483, 1) | camel / B2B / billing=visit / dtos0 | 001G500001ThAyzIAF |
| a1ITx0000049PJRMA2 | Schoenmaker Elektrotechniek (53266, 1) | camel / B2B / billing=visit / dtos0 | 001G500001TgWA8IAN |
| a1ITx0000049VwjMAE | E.S.J. Dudok (51318, 1) | camel / B2C / sep-billing / dtos0 | 001G500001Th024IAB |
| a1ITx0000049M5SMAU | HDR elektrotechniek (37424, 5) | camel / B2B / billing=visit / dtos0 | 001G500001ThBAHIA3 |
| a1ITx0000049UhJMAU | VSJ Cleaning (78131, 5) | camel / B2B / billing=visit / dtos0 | 001G500001Th8CSIAZ |
| a1ITx0000049Qx3MAE | Pouw Dealer B.V. (3685, 1) | camel / B2B / sep-billing / dtos1 | 001G500000sW0c6IAC |
| a1ITx0000047hU9MAI | Multicom B.V. (15304, 1) | camel / B2B / sep-billing / dtos1 | 001G500001Th4lUIAR |
| a1ITx0000049PMfMAM | GastroPfaff AG (9724, 2) | Pascal / B2B / sep-billing / dtos1 | 001G500001Th1YEIAZ |
| a1ITx0000048najMAA | FDB Frischdienst Berlin GmbH & Co. KG (7510, 2) | Pascal / B2B / sep-billing / dtos1 | 001G500001TgtqEIAR |
| a1ITx0000049JifMAE | Peter Meijers (17964, 1) | camel / B2C / billing=visit / dtos0 | 001G500001Tgu6GIAR |
| a1ITx0000048PQLMA2 | Kübra Özge Yiğit (124734, 1) | camel / B2C / billing=visit / dtos0 | 001G500001TgfOzIAJ |
| a1ITx0000048hwlMAA | Sanft Mobil GmbH (15569, 2) | Pascal / B2B / billing=visit / dtos1 | 001G500001ThCj3IAF |
| a1ITx0000048ncLMAQ | Janus Diagnostik GmbH (13698, 2) | Pascal / B2B / billing=visit / dtos1 | 001G500001ThCr7IAF |
