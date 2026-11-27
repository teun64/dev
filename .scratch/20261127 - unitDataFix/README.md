# Unit of measure data fix (Product2.QuantityUnitOfMeasure)
Decision 2026-11-27: use Quantity Unit Of Measure ALONE for the e-invoice unit code (BR-23), then drop the cost-type fallback in `Svc_CIIInvoiceXmlBuilder.resolveUneceUnitCode`.
- `dryrun.apex` read-only list of what would change; `prod_dryrun.txt` = prod output 2026-11-27 (447 rows).
- `apply.apex` (DRY=true by default) fixes the safe groups only: 369 NON_RECURRING without unit -> Piece(s); 50 RECURRING with junk (`Month` 39, `12` 9, `24` 2) -> Month(s). 419 products in prod.
- NOT touched: 28 NON_RECURRING with Month(s) (prepaid bundles, e.g. White.36.P, Orange.12.P, 800.900.3610/3710/3905/9005): decide Month(s) vs Piece(s).
- Applied 2026-11-27 in dev and acc (418 each, 0 failed). PROD: not run, only on the user's explicit command.
- After prod: remove the fallback + the cost-type tests, deploy, re-run the test set.
