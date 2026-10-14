# Payment page hotfix (release 1) — 2026-10-14

Bug: Ctrl_Payment.getPaymentData created a new PaymentIntent on every page load; with a mandate on the Account it was
created with confirm=true → every opening of the link (incl. D+2/D+4 reminders) debited the customer again.
Marc Stone PM#000201568: 3x £15 succeeded → refund pi_3UNz6pGliYpbpuQB1aP6Swga + pi_3UNz9OGliYpbpuQB0ms7N837
(keep pi_3UNEnbGliYpbpuQB1OgEokZV, the real 05-10 checkout).

Fix:
- Status Processing counts as already processed (with Paid/Collected).
- Mandate + payment method on file → alreadyScheduled, no intent; Batch_ProcessPayments collects on the collection date.
- confirm=true / off_session branch removed from Ctrl_Payment; SEPA without mandate always setup mode.
- paymentPage: new "Direct Debit scheduled" state (en/nl/de/fr) with the collection date.

Status: dev ✓ (19/19, 0 callouts for a mandate customer), acc ✓ (20/20, republished), prod ✓ 2026-10-14 deployed (19/19) + Customer Hub republished (Complete).

## acc
sf api request rest "/services/data/v67.0/connect/communities/0DBG50000004lI5OAI/publish" --method POST -o acc

## prod
sf project deploy start -o prod -d force-app/main/default/classes/Ctrl_Payment.cls -d force-app/main/default/classes/Test_Ctrl_Payment.cls -d force-app/main/default/lwc/paymentPage --test-level RunSpecifiedTests --tests Test_Ctrl_Payment -w 30
sf api request rest "/services/data/v67.0/connect/communities/0DBTx000000188POAQ/publish" --method POST -o prod
(the Apex fix is live immediately after the deploy; the new page text only after the republish)
