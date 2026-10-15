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
- Chris Jonker **keeps** `Main;Shipping` (since 2026-10-15: Shipping is only set on
  create and never removed by a platform update; before, it dropped to `Main`).
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
- Shipping: only set when the account is created; never removed.
- Reminder, Payment, Sales, Service, ASR: never touched. Payload wins over the lookups;
  afl_AccountContactRelation_Roles moves the lookups and keeps one Main/Invoice/Shipping per account.
Dev run 2026-10-15 (external id 948767): 3 calls stable + Reminder/Payment kept on a 4th call.
