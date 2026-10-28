# Email templates: Arial inline (2026-10-28)

Context: marketing pointed out the mixed fonts in the Dealer Portal reset email. The templates had Arial only on the container, and Outlook desktop doesn't reliably pass that font down to `p`/`a`. Rule: see memory `feedback_email_template_font_arial.md`.

## Scope (user's decision 2026-10-28)
`scope.json` holds the 42 prod templates in use:
- sent in the last 180 days (EmailMessage)
- referenced by an email alert, auto-response rule or Network
- looked up by name in a flow or Apex (paymentDirectDebit*, auto-responses, "Aanvraag wijzigen rechtspersoon (contractant)")

This includes the Classic letterhead templates and the 2 private ones (Jonas Maassen, Tim Salimans). It also covers all EnhancedLetterhead records.

The Dealer Portal VF templates and the `emailLetterheadPreferences` component are done through metadata (repo), not through this script.

Not in scope: Classic BrandTemplates (already `font-family="arial"`), Salesforce samples, text-only templates, and the standard Community* templates.

## Scripts
- `arialfix.py`: `transform()` puts `font-family:Arial,Helvetica,sans-serif` inline on every text element.
  - It also rewrites `<font face>`, `mso-*-font-family` and `<style>` blocks.
  - For Classic `html` templates it only touches the content inside CDATA.
  - `normalize()` is the safety check: the HTML minus all font declarations must stay identical.
- `dryrun.py <S> <org>`: needs `et2_<org>.json` (fresh query). Shows what changes.
- `apply.py <dir> <org> [--write]`: takes a fresh backup to `backup_<org>_<ts>.json`, transforms, PATCHes, and reads back to verify.
- `apply_lh.py <dir> <org> --write`: the same for EnhancedLetterhead.
- Run from this folder: `python3 -I apply.py "$PWD" <org> --write`.

## Status
- dev ✅ 2026-10-28: 33 templates and 7 letterheads. 14 samples rendered and sent to Teun (twice by mistake).
- acc ✅ 2026-10-28: 35 templates and 4 letterheads. Re-run shows 0 changes.
  - ⚠ The Dealer Portal VF templates and component reached acc only with `0AfG500000TFQvxKAH` (15:11 UTC). `0Afbd00000Bpp0XCAR` (07:18) was a **dev** deploy, not acc.
- prod ⏳ needs an explicit go. Dry run: 40 templates (DealerPortal excluded), 0 BAD. The 4 letterheads (lh_M_Payment, lh_M_Service, lh_E_Service, Header_2024) aren't changed yet.
  - The prod Dealer Portal templates and component go through a metadata deploy (repo, NoTestRun isn't possible in prod, so RunSpecifiedTests).
- repo: the 22 `.email` files went through `transform()`. Remaining differences from dev are only character encoding (`ü` vs `&uuml;`).

## Rollback
Write the `HtmlValue` from `backups/backup_<org>_<ts>.json` back per Id (letterheads: `backup_lh_*`).

## Standard letterheads (2026-10-28, user's go for dev + acc)
Cause of the missing images in the dev tests: the Classic letterheads `2023_Styling600/660/883` pointed to Document Ids that don't exist in dev. dev has the same images under new Ids (`015bd0000071iKj/k/l`). acc and prod were fine.

`standardize_lh.py <dir> <org> [--write] [--classic-only NAME]`:
- **Lightning (EnhancedLetterhead):**
  - every `file-asset-public` image points to the prod URL (`movingintelligence.file.force.com …?oid=00D1t000000uTfK`), so sandboxes don't need their own copy
  - the header image style is standard: `max-width:600px; width:100%; height:auto; display:block; border:0;`
  - echoes footer link `echeos.solution` → `https://echoes.solutions` (it was a dead link)
- **Classic (BrandTemplate):**
  - every `servlet.ImageServer` reference points to the Document with the same DeveloperName **in its own org**, with that org's own oid
  - an absolute prod URL does NOT work: Salesforce rewrites it to its own domain and the image comes out empty
- It writes backups to `backups/backup_lh_<org>_<ts>_std.json` and `backups/backup_bt_<org>_<ts>.json`, and reads every write back to check it.

Status:
- dev ✅: 7 Lightning + 3 Classic letterheads.
  - `MI 3 Arrows (Email)` was left as is because its Document `mi_logo_new_png` doesn't exist in dev. It isn't used by any template in scope.
  - 7 samples sent ("[TEST dev letterhead]").
- acc ✅: 4 Lightning letterheads. Classic already pointed to acc's own Documents, so nothing to change. 7 samples sent ("[TEST acc letterhead]").
- prod ⏳: needs an explicit go. Expected changes: the header style on the 4 Lightning letterheads, the echoes link, and 0 Classic.

## Standard header (user's decision 2026-10-28)
**One header on every template:** the red-› bridge banner `miemailheader` (600×118, `https://movingintelligence.file.force.com/file-asset-public/miemailheader?oid=00D1t000000uTfK`). The only exception is the echoes brand (`lh_E_Service`: mi4 EN/FR, reseller 4), which keeps its own header.

Before this there were 6 variants:
- white › on the Classic BT600/BT660 and the CMS `MCUVG5` image
- red › on the Lightning letterheads and the Dealer Portal mails
- a short banner on InvoiceNL
- the 3-arrows logo on InvoiceUK/DE
- no header on DD and Noodsleutel. In DD, `milogoblack` is the *signature* logo, not a header.

The banner art was byte-identical in dev, acc and prod. The differences were between templates, not between orgs.

Scripts:
- `header.py <dir> <org> [--write]`: templates without a letterhead.
  - Replaces the header `<img>` (CMS `MCUVG5`/`MCRT3A`/`MCTJTU`) with the standard one, or inserts the banner right after `<body>` (`paymentDirectDebit*`, `Noodsleutel_*`).
  - Skips templates that already contain `miemailheader`, so it's idempotent.
  - Skips templates with a letterhead.
  - Safety check: the HTML with the header swapped for a placeholder must be identical before and after.
  - Backup: `backups/backup_hdr_<org>_<ts>.json`.
- `header_bt.py <dir> <org> [--write]`: Classic `lh2023_Styling600/660/883`.
  - Uploads `miemailheader.png` as the public Document `MiEmailHeader600_2024` into the folder of the current header Document (`00lAO000000MCKfYAO` "Email", the same Id in all 3 orgs).
  - Repoints `headerImage` to it, as a relative URL with the org's own oid.
  - Backup: `backups/backup_bthdr_<org>_<ts>.json`.
- `copy_from_prod.py <dir> <org> --write` (sandbox only): creates in-scope templates that exist only in prod, so dev/acc can go first.
  - Private (user) folders become "Email Templates from Salesforce" (`00lbR0000001Y9KQAU`).

Status:
- dev ✅ 2026-10-28:
  - 7 prod-only templates copied in, then Arial.
  - header.py: 9 templates. DD and Invoice already get the banner through `lh_M_Preferences_*` in dev.
  - Classic: Document `015bd000007jcBZ`.
  - 6 samples "[TEST dev header]".
- acc ✅ 2026-10-28:
  - 5 prod-only templates copied in, then Arial.
  - header.py: 21 templates.
  - Classic: Document `015G500000IASbl`.
  - 6 samples "[TEST acc header]".
  - Both Documents return the same PNG as prod's `miemailheader` (md5 check).
- prod ✅ 2026-10-28: steps 1–6 done (step 1 15:33, steps 2–5 15:35–15:37 UTC, user's go). Classic Document `015Tx00000ChiV7`. Dealer Portal VF emails + `emailLetterheadPreferences` deployed to prod separately on 2026-10-28 (`0AfTx0000014H3JKAU`, RunSpecifiedTests Test_Ctrl_DealerPortalEmail 2/2, run by the user). Retrieve == repo apart from whitespace.

Fixed on 2026-10-28: `apply_lh.py` always wrote, even without `--write`, because the `exec` of apply.py hardcoded `write=True`. It now honours the flag. `apply.py` and `apply_lh.py` now write their backups to `backups/`.

---

# prod deploy runbook: email templates (Arial + standard header)

**Needs the user's explicit go.** No test sends from prod (memory: no test activity in prod). If a visual check in prod is wanted, ask first; render only (`Messaging.renderStoredEmailTemplate` without `sendEmail`).

The Dealer Portal VF templates and `emailLetterheadPreferences` are **not** in this runbook. They ship with the Dealer Shop package (`../20261028 - dealerShopBatchProd/`, metadata deploy with RunSpecifiedTests). Their header is already `miemailheader`, so this runbook doesn't change them.

Run everything from this folder: `cd ".scratch/20261028 - emailTemplatesArial"`. Every script takes a fresh backup in `backups/` on every run, dry run included.

## Expected counts (dry run 2026-10-28 15:25 UTC)
| step | script | prod objects |
|---|---|---|
| 1 | `apply.py` (Arial) | 40 templates |
| 2 | `apply_lh.py` (Arial) | 4 letterheads: lh_M_Payment, lh_M_Service, Header_2024, lh_E_Service |
| 3 | `standardize_lh.py` | all 4 letterheads (header style; echoes footer link) |
| 4 | `header.py` | 21 templates: 8× MCUVG5, InvoiceNL, InvoiceUK/DE, 9× DD inserted, Noodsleutel inserted |
| 5 | `header_bt.py` | 1 new Document + 3 BrandTemplates |

**Blast radius (prod, 2026-10-28).** A letterhead change hits *every* template on that letterhead, not only the in-scope ones:
- `lh2023_Styling600`: 28 active templates (10 in scope)
- `lh2023_Styling660`: 7 active templates (2 in scope)
- `lh2023_Styling883`: 0
- `lh_M_Service`: 5 (auto-responses)
- `lh_E_Service`: 2 (echoes; only Arial and the footer link, the header stays echoes)
- `lh_M_Payment` and `Header_2024`: 0

The Classic `Standaard` (3 active and 32 inactive templates) and `MI_3Arrows_Email` are **not** touched: none of their templates were used in the last 180 days.

In scope and prod-only (not in the repo): the 3 SFX `Verzoek_tot_be_indiging_dienstverlening_*` variants (Asset/Account/Case), Review_verzoek_Google_1762259301403, Review_verzoek_Google_Recovery_1753080970119 (Tim Salimans, private), Verzenden_SEPA_machtiging_incasso_formulier_1747233830743 and Noodsleutel_2_of_3_pins_1779268609732 (Jonas Maassen, private).

## Steps
0. **Dry run everything** and compare with the table. Stop on any difference, `BAD`, `NO HEADER FOUND` or assert.
   ```
   for s in apply.py apply_lh.py standardize_lh.py header.py header_bt.py; do python3 -I $s "$PWD" prod; done
   ```
1. Arial on templates: `python3 -I apply.py "$PWD" prod --write`. Every line must read `WROTE`.
   - ✅ **Done 2026-10-28 15:33 UTC** (user's go "do 1 for prod"): 40× `WROTE` (read back identical). Re-run: `changed 0`. Rollback backup: `backups/backup_prod_20261028T153256Z.json`.
   - Step 0 dry run just before it matched the table: 40 / 4 / 4 / 21 / 1 Document + 3 BT.
2. Arial on letterheads: `python3 -I apply_lh.py "$PWD" prod --write`
3. Standard letterheads: `python3 -I standardize_lh.py "$PWD" prod --write`. Classic: 0 changes expected, because prod already points to its own Documents.
4. Header on templates: `python3 -I header.py "$PWD" prod --write`. 21× `WROTE`.
   - ✅ Steps 2–5 done 2026-10-28 (user's go "do 2 to 5 for prod"). Rollback backups (the run with `--write`):
     - step 2: `backups/backup_lh_prod_20261028T153513Z.json`, 4× WROTE
     - step 3: `backups/backup_lh_prod_20261028T153521Z_std.json` + `backup_bt_prod_20261028T153521Z.json`, 4× WROTE
     - step 4: `backups/backup_hdr_prod_20261028T153546Z.json`, 21× WROTE
     - step 5: `backups/backup_bthdr_prod_20261028T153637Z.json`. New Document `015Tx00000ChiV7`; 3 BT WROTE.
   - ✅ Step 6:
     - All 5 scripts re-run show 0 changes.
     - The image serves with md5 `ce79f8b0…`, the same as `miemailheader.png`.
     - survey: all 42 in-scope templates on the standard header (echoes on its own). `NOT standard: []`.
5. Classic letterheads: `python3 -I header_bt.py "$PWD" prod --write`.
   - Then check the image serves: `curl -s "https://movingintelligence.file.force.com/servlet/servlet.ImageServer?id=<new id>&oid=00D1t000000uTfK" | md5`, which must equal `md5 miemailheader.png` (`ce79f8b0…`).
6. **Verify:**
   - Re-run step 0. Everything should report 0 changes (`changed 0`, `unchanged`, `already`, `(unchanged)`).
   - Run `python3 -I survey.py "$PWD" prod`. Every non-echoes template has `miemailheader` inline, a letterhead `lh_M_*`/`Header_2024`, or BT `lh2023_*`.
7. Update this runbook, memory `feedback_email_template_font_arial.md` and `reference_classic_letterhead_images.md`.

## Rollback (per step, Ids from the backup of that same run)
- 1 and 4: PATCH `HtmlValue` per Id from `backups/backup_prod_<ts>.json` (step 1) or `backups/backup_hdr_prod_<ts>.json` (step 4). Rolling back step 1 also undoes step 4 if it has already run.
- 2: PATCH `LetterheadHeader`/`LetterheadFooter` from `backups/backup_lh_prod_<ts>.json`.
- 3: the same from `backups/backup_lh_prod_<ts>_std.json`.
- 5: PATCH `BrandTemplate.Value` from `backups/backup_bthdr_prod_<ts>.json`. The Document `MiEmailHeader600_2024` can stay.

## Repo
The repo `.email` files (DD, Invoicing, auto-responses) are dev's version. In dev, DD and Invoice hang on `lh_M_Preferences_*`, which already carries the banner, so header.py doesn't change them. prod's DD and Invoice templates are a different (older) version, so they're done through the API in step 4, not through a metadata deploy. Don't deploy the repo DD/Invoice files to prod as part of this runbook: that's the invoice-consolidation rollout.
