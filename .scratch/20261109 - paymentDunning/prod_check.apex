// READ-ONLY prod check before the dunning deploy (2026-11-10). Nothing is written in Salesforce or Stripe.
// 1. per Stripe account: are iDEAL and bank transfer (customer_balance) available in live mode?
// 2. failure codes of real failed payments (last 365 days) to compare with Svc_PaymentDunning RENEW_CODES / PAY_CODES
// 3. the gqCasePayment<reseller> queues the suspension Case goes to
// Run: sf apex run -o prod -f ".scratch/20261109 - paymentDunning/prod_check.apex" | grep CHECK

Map<String, Object> stripeGet(Id stripeAccount, String endpoint) {
    stripeGC.RawInvocableParameters params = new stripeGC.RawInvocableParameters();
    params.method = 'GET';
    params.endpoint = endpoint;
    params.accountId = stripeAccount;
    List<String> results = stripeGC.AgnosticInvocable.callStripeEndpoint(new List<stripeGC.RawInvocableParameters>{ params });
    return (Map<String, Object>) JSON.deserializeUntyped(results[0]);
}

// 1. payment methods per Stripe account (Belgium shares the Netherlands account)
Set<Id> seen = new Set<Id>();
for (Business_Entities__c be : [SELECT Name, PayProv_Account__c FROM Business_Entities__c WHERE PayProv_Account__c != null ORDER BY Name]) {
    if (!seen.add(be.PayProv_Account__c)) continue;
    try {
        Map<String, Object> acct = stripeGet(be.PayProv_Account__c, '/v1/account');
        Map<String, Object> caps = (Map<String, Object>) acct.get('capabilities');
        System.debug('CHECK account ' + be.Name + ' ' + acct.get('id') + ' country=' + acct.get('country') + ' livemode? charges_enabled=' + acct.get('charges_enabled')
            + ' ideal=' + (caps == null ? null : caps.get('ideal_payments'))
            + ' bank_transfer=' + (caps == null ? null : caps.get('bank_transfer_payments'))
            + ' sepa=' + (caps == null ? null : caps.get('sepa_debit_payments'))
            + ' bacs=' + (caps == null ? null : caps.get('bacs_debit_payments'))
            + ' card=' + (caps == null ? null : caps.get('card_payments')));
    } catch (Exception e) {
        System.debug('CHECK account ' + be.Name + ' capabilities not readable: ' + e.getMessage());
    }
    try {
        Map<String, Object> configs = stripeGet(be.PayProv_Account__c, '/v1/payment_method_configurations?limit=10');
        for (Object o : (List<Object>) configs.get('data')) {
            Map<String, Object> c = (Map<String, Object>) o;
            if (c.get('is_default') != true) continue;
            List<String> line = new List<String>();
            for (String pm : new List<String>{ 'card', 'ideal', 'customer_balance', 'sepa_debit', 'bacs_debit', 'apple_pay', 'google_pay' }) {
                Map<String, Object> m = (Map<String, Object>) c.get(pm);
                Map<String, Object> pref = m == null ? null : (Map<String, Object>) m.get('display_preference');
                line.add(pm + '=' + (m == null ? 'n/a' : 'available:' + m.get('available') + '/' + (pref == null ? null : pref.get('value'))));
            }
            System.debug('CHECK config ' + be.Name + ' livemode=' + c.get('livemode') + ' ' + String.join(line, ' '));
        }
    } catch (Exception e) {
        System.debug('CHECK config ' + be.Name + ' not readable: ' + e.getMessage());
    }
}

// 2. failure codes (code / decline_code) of failed payment events
Map<String, Integer> codes = new Map<String, Integer>();
Integer events = 0;
for (stripeGC__Stripe_Event__c evt : [
    SELECT stripeGC__Event_Name__c, stripeGC__Request_Body__c FROM stripeGC__Stripe_Event__c
    WHERE stripeGC__Event_Name__c IN ('payment_intent.payment_failed', 'charge.failed') AND CreatedDate = LAST_N_DAYS:365
    ORDER BY CreatedDate DESC LIMIT 400
]) {
    events++;
    try {
        Map<String, Object> obj = (Map<String, Object>) ((Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(evt.stripeGC__Request_Body__c)).get('data')).get('object');
        String code;
        String decline;
        String type;
        Map<String, Object> err = (Map<String, Object>) obj.get('last_payment_error');
        if (err != null) {
            code = (String) err.get('code');
            decline = (String) err.get('decline_code');
            Map<String, Object> pm = (Map<String, Object>) err.get('payment_method');
            type = pm == null ? null : (String) pm.get('type');
        } else {
            code = (String) obj.get('failure_code');
            Map<String, Object> outcome = (Map<String, Object>) obj.get('outcome');
            decline = outcome == null ? null : (String) outcome.get('reason');
            Map<String, Object> pmd = (Map<String, Object>) obj.get('payment_method_details');
            type = pmd == null ? null : (String) pmd.get('type');
        }
        String key = evt.stripeGC__Event_Name__c + ' | ' + type + ' | ' + code + ' | ' + decline;
        codes.put(key, (codes.containsKey(key) ? codes.get(key) : 0) + 1);
    } catch (Exception e) {
        codes.put('unparsed', (codes.containsKey('unparsed') ? codes.get('unparsed') : 0) + 1);
    }
}
System.debug('CHECK failed events read: ' + events + ' (max 400)');
for (String k : codes.keySet()) System.debug('CHECK code ' + codes.get(k) + 'x ' + k);

// 3. queues
for (Group g : [SELECT DeveloperName FROM Group WHERE Type = 'Queue' AND DeveloperName LIKE 'gqCasePayment%']) System.debug('CHECK queue ' + g.DeveloperName);
for (AggregateResult r : [SELECT Reseller_Name__c n, COUNT(Id) c FROM Account WHERE PayProv_CustomerId__c != null GROUP BY Reseller_Name__c]) {
    System.debug('CHECK reseller ' + r.get('n') + ' accounts with Stripe customer: ' + r.get('c'));
}
