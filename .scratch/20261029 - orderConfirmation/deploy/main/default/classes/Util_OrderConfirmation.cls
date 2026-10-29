/**
 * Webshop order processing + order confirmation email (2026-10-29).
 *
 *  - A Webshop opportunity that goes to Closed Won (by hand, by the Process Order button or automatically)
 *    gets Order_Processed_At__c + its shipping day (Order_Shipping_Date__c, Order_Ships_Same_Day__c,
 *    Order_Shipping_Cutoff__c) before update, and an Order_Process__e "send" event after update. The template
 *    reads everything from the opportunity (no controller: the event runs as the Automated Process user).
 *  - Order_Process__e runs as the Automated Process user (OrderProcessEvent.trigger -> handle()), so a portal
 *    user never sends email or closes an opportunity in their own context:
 *      "process" = set Closed Won (which in turn publishes "send"); "send" = send the confirmation.
 *  - Ctrl_DealerShop.placeOrder publishes "process" when the business entity has
 *    DealerPortal_Opportunity_AutoProcess__c ticked.
 *  - The email (template Opportunity_OrderConfirmation) goes to the opportunity's signer (SignerId__c: Sales
 *    Contact, else the account's contact person), cc the account's confirmation contact / email. Sender = the
 *    first verified org-wide address that allows all profiles of: the business entity's Email (Sales), the
 *    Administration's billing email, FALLBACK_SENDER; Reply-To = Email (Sales).
 */
public without sharing class Util_OrderConfirmation {

    public static final String ACTION_PROCESS = 'process';
    public static final String ACTION_SEND    = 'send';
    @TestVisible private static final String TEMPLATE_NAME   = 'Opportunity_OrderConfirmation';
    @TestVisible private static final String FALLBACK_SENDER = 'do-not-reply@movingintelligence.com';
    private static final String DEFAULT_TIME_ZONE = 'Europe/Amsterdam';
    private static final Time   DEFAULT_CUTOFF    = Time.newInstance(15, 0, 0, 0);

    @TestVisible private static List<Messaging.SingleEmailMessage> lastSent = new List<Messaging.SingleEmailMessage>();

    private static Id webshopRecordTypeId {
        get {
            if (webshopRecordTypeId == null) {
                webshopRecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Webshop').getRecordTypeId();
            }
            return webshopRecordTypeId;
        }
        set;
    }

    // ── Publishing ────────────────────────────────────────────────────────────

    public static void publish(Set<Id> opportunityIds, String action) {
        List<Order_Process__e> events = new List<Order_Process__e>();
        for (Id oppId : opportunityIds) {
            events.add(new Order_Process__e(Opportunity_Id__c = oppId, Action__c = action));
        }
        if (!events.isEmpty()) EventBus.publish(events);
    }

    // ── Opportunity trigger hooks (Trigger_Opportunity) ─────────────────────────

    private static Boolean isNewlyWonWebshop(Opportunity opp, Opportunity old) {
        return opp.RecordTypeId == webshopRecordTypeId && opp.IsWon && (old == null || !old.IsWon);
    }

    public static void beforeUpdate(List<Opportunity> newList, Map<Id, SObject> oldMap) {
        List<Opportunity> won = new List<Opportunity>();
        for (Opportunity opp : newList) {
            if (isNewlyWonWebshop(opp, (Opportunity) oldMap.get(opp.Id))) {
                if (opp.Order_Processed_At__c == null) opp.Order_Processed_At__c = System.now();
                won.add(opp);
            }
        }
        stampShipping(won);
    }

    // Order_Shipping_Date__c / Order_Ships_Same_Day__c / Order_Shipping_Cutoff__c from Order_Processed_At__c and
    // the business entity of the account's reseller (Business_Hours_Shipping__c, Shipping_Cutoff_Time__c).
    // Sets the fields on the records passed in; the caller saves them (or is a before trigger).
    @TestVisible
    private static void stampShipping(List<Opportunity> opps) {
        if (opps.isEmpty()) return;
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : opps) accountIds.add(opp.AccountId);
        Map<Id, String> resellerByAccount = new Map<Id, String>();
        for (Account acc : [SELECT Id, Reseller_Name__c FROM Account WHERE Id IN :accountIds WITH SYSTEM_MODE]) {
            resellerByAccount.put(acc.Id, acc.Reseller_Name__c);
        }
        Map<String, Business_Entities__c> entityByReseller = new Map<String, Business_Entities__c>();
        for (Business_Entities__c be : [
            SELECT Reseller__c, Business_Hours_Shipping__c, Shipping_Cutoff_Time__c
            FROM Business_Entities__c WHERE Reseller__c IN :resellerByAccount.values() WITH SYSTEM_MODE
        ]) entityByReseller.put(be.Reseller__c, be);
        for (Opportunity opp : opps) {
            Business_Entities__c be = entityByReseller.get(resellerByAccount.get(opp.AccountId));
            ShippingDay day = shippingDay(opp.Order_Processed_At__c, be?.Business_Hours_Shipping__c, be?.Shipping_Cutoff_Time__c);
            opp.Order_Shipping_Date__c   = day.day;
            opp.Order_Ships_Same_Day__c  = day.sameDay;
            opp.Order_Shipping_Cutoff__c = day.cutoff;
        }
    }

    public static void afterUpdate(List<Opportunity> newList, Map<Id, SObject> oldMap) {
        // Automatically only the first time: an order that order creation put back on Administration and is
        // set to Closed Won again doesn't send a second confirmation (the button can resend on purpose).
        Set<Id> toSend = new Set<Id>();
        for (Opportunity opp : newList) {
            if (isNewlyWonWebshop(opp, (Opportunity) oldMap.get(opp.Id)) && opp.Order_Confirmation_Sent__c == null) toSend.add(opp.Id);
        }
        publish(toSend, ACTION_SEND);
    }

    // ── Event handler (OrderProcessEvent.trigger, Automated Process user) ──────

    public static void handle(List<Order_Process__e> events) {
        Set<Id> toProcess = new Set<Id>();
        Set<Id> toSend    = new Set<Id>();
        for (Order_Process__e e : events) {
            if (String.isBlank(e.Opportunity_Id__c)) continue;
            Id oppId = Id.valueOf(e.Opportunity_Id__c);
            if (e.Action__c == ACTION_PROCESS) toProcess.add(oppId);
            else if (e.Action__c == ACTION_SEND) toSend.add(oppId);
        }
        if (!toProcess.isEmpty()) processOrders(toProcess);
        if (!toSend.isEmpty()) sendConfirmations(toSend);
    }

    // Closed Won; the Opportunity trigger then stamps Order_Processed_At__c and publishes "send". A refusal
    // (e.g. rbu_Opportunity: account not financial-ready) leaves the order on its stage with the reason.
    @TestVisible
    private static void processOrders(Set<Id> opportunityIds) {
        List<Opportunity> toClose = new List<Opportunity>();
        for (Opportunity opp : [
            SELECT Id FROM Opportunity
            WHERE Id IN :opportunityIds AND RecordTypeId = :webshopRecordTypeId AND IsClosed = false
            WITH SYSTEM_MODE
        ]) {
            toClose.add(new Opportunity(Id = opp.Id, StageName = 'Closed Won', Order_Process_Error__c = null));
        }
        List<Database.SaveResult> results = Database.update(toClose, false, AccessLevel.SYSTEM_MODE);
        List<Opportunity> failed = new List<Opportunity>();
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                failed.add(new Opportunity(Id = toClose[i].Id,
                    Order_Process_Error__c = ('Automatic processing failed: ' + errorText(results[i].getErrors())).left(255)));
            }
        }
        if (!failed.isEmpty()) Database.update(failed, false, AccessLevel.SYSTEM_MODE);
    }

    @TestVisible
    private static void sendConfirmations(Set<Id> opportunityIds) {
        List<Opportunity> opps = [
            SELECT Id, SignerId__c, Account.Reseller_Name__c,
                   Account.Confirmation_Contact__r.Email, Account.Confimation_Email__c
            FROM Opportunity
            WHERE Id IN :opportunityIds AND RecordTypeId = :webshopRecordTypeId AND Order_Processed_At__c != null
            WITH SYSTEM_MODE
        ];
        // Processed, not "still won": the order creation that runs alongside can put the stage back on
        // Administration (Order_Creation_Fault_Message__c) before this runs; the customer still gets the mail.
        if (opps.isEmpty()) return;

        Set<String> resellers = new Set<String>();
        for (Opportunity opp : opps) resellers.add(opp.Account.Reseller_Name__c);
        Map<String, Business_Entities__c> entityByReseller = new Map<String, Business_Entities__c>();
        for (Business_Entities__c be : [
            SELECT Reseller__c, Email_Sales__c FROM Business_Entities__c WHERE Reseller__c IN :resellers WITH SYSTEM_MODE
        ]) entityByReseller.put(be.Reseller__c, be);
        Map<String, String> billingByReseller = new Map<String, String>();
        for (Subscription25__Administration__c adm : [
            SELECT Reseller__c, Subscription25__Billing_Email_Address__c
            FROM Subscription25__Administration__c WHERE Reseller__c IN :resellers WITH SYSTEM_MODE
        ]) billingByReseller.put(adm.Reseller__c, adm.Subscription25__Billing_Email_Address__c);
        Map<String, Id> senderByAddress = new Map<String, Id>();
        for (OrgWideEmailAddress owe : [
            SELECT Id, Address FROM OrgWideEmailAddress WHERE IsVerified = true AND IsAllowAllProfiles = true WITH SYSTEM_MODE
        ]) senderByAddress.put(owe.Address.toLowerCase(), owe.Id);
        Id templateId = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :TEMPLATE_NAME WITH SYSTEM_MODE LIMIT 1].Id;

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<Opportunity> messageOpps = new List<Opportunity>();
        List<Opportunity> updates = new List<Opportunity>();
        for (Opportunity opp : opps) {
            if (String.isBlank(opp.SignerId__c)) {
                updates.add(new Opportunity(Id = opp.Id,
                    Order_Process_Error__c = 'Order confirmation not sent: no Sales Contact and no contact person on the account.'));
                continue;
            }
            Business_Entities__c be = entityByReseller.get(opp.Account.Reseller_Name__c);
            String salesEmail = be?.Email_Sales__c;

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setTemplateId(templateId);
            msg.setTargetObjectId(Id.valueOf(opp.SignerId__c));
            msg.setWhatId(opp.Id);
            msg.setSaveAsActivity(true);
            List<String> cc = ccAddresses(opp);
            if (!cc.isEmpty()) msg.setCcAddresses(cc);
            Id senderId = pickSender(senderByAddress, new List<String>{
                salesEmail, billingByReseller.get(opp.Account.Reseller_Name__c), FALLBACK_SENDER });
            if (senderId != null) msg.setOrgWideEmailAddressId(senderId);
            if (String.isNotBlank(salesEmail)) msg.setReplyTo(salesEmail);
            messages.add(msg);
            messageOpps.add(opp);
        }

        if (!messages.isEmpty()) {
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(messages, false);
            lastSent = messages;
            for (Integer i = 0; i < results.size(); i++) {
                updates.add(results[i].isSuccess()
                    ? new Opportunity(Id = messageOpps[i].Id, Order_Confirmation_Sent__c = System.now(), Order_Process_Error__c = null)
                    : new Opportunity(Id = messageOpps[i].Id,
                        Order_Process_Error__c = ('Order confirmation not sent: ' + errorText(results[i].getErrors())).left(255)));
            }
        }
        if (!updates.isEmpty()) Database.update(updates, false, AccessLevel.SYSTEM_MODE);
    }

    private static List<String> ccAddresses(Opportunity opp) {
        Set<String> seen = new Set<String>();
        List<String> cc = new List<String>();
        for (String address : new List<String>{ opp.Account.Confirmation_Contact__r?.Email, opp.Account.Confimation_Email__c }) {
            if (String.isNotBlank(address) && seen.add(address.toLowerCase())) cc.add(address);
        }
        return cc;
    }

    @TestVisible
    private static Id pickSender(Map<String, Id> senderByAddress, List<String> candidates) {
        for (String address : candidates) {
            if (String.isNotBlank(address) && senderByAddress.containsKey(address.toLowerCase())) {
                return senderByAddress.get(address.toLowerCase());
            }
        }
        return null;
    }

    private static String errorText(List<Object> errors) {
        List<String> parts = new List<String>();
        for (Object err : errors) {
            parts.add(err instanceof Database.Error ? ((Database.Error) err).getMessage()
                                                     : ((Messaging.SendEmailError) err).getMessage());
        }
        return String.join(parts, '; ');
    }

    // ── Shipping date (used by the email component) ──────────────────────────

    public class ShippingDay {
        public Date    day;
        public Boolean sameDay;
        public String  cutoff;   // HH:mm
    }

    // Processed on a working day before the cut-off (local time of the business hours) = shipped that day,
    // otherwise on the next working day. Working day = inside the business hours at noon (weekends and
    // holidays of that Business Hours entry are not); without business hours: Monday to Friday.
    public static ShippingDay shippingDay(Datetime processedAt, String businessHoursName, Time cutoff) {
        BusinessHours bh = null;
        if (String.isNotBlank(businessHoursName)) {
            List<BusinessHours> found = [
                SELECT Id, TimeZoneSidKey FROM BusinessHours WHERE Name = :businessHoursName AND IsActive = true WITH SYSTEM_MODE LIMIT 1
            ];
            if (!found.isEmpty()) bh = found[0];
        }
        TimeZone tz = TimeZone.getTimeZone(bh != null ? bh.TimeZoneSidKey : DEFAULT_TIME_ZONE);
        Time cut = cutoff != null ? cutoff : DEFAULT_CUTOFF;
        Datetime at = processedAt != null ? processedAt : System.now();

        String local = at.format('yyyy-MM-dd HH:mm:ss', tz.getID());
        Date localDay = Date.valueOf(local.left(10));
        Time localTime = Time.newInstance(Integer.valueOf(local.mid(11, 2)), Integer.valueOf(local.mid(14, 2)), Integer.valueOf(local.mid(17, 2)), 0);

        ShippingDay result = new ShippingDay();
        result.cutoff = String.valueOf(cut.hour()).leftPad(2, '0') + ':' + String.valueOf(cut.minute()).leftPad(2, '0');
        result.sameDay = isWorkingDay(localDay, bh, tz) && localTime < cut;
        Date candidate = result.sameDay ? localDay : localDay.addDays(1);
        for (Integer i = 0; i < 30 && !isWorkingDay(candidate, bh, tz); i++) candidate = candidate.addDays(1);
        result.day = candidate;
        return result;
    }

    private static Boolean isWorkingDay(Date day, BusinessHours bh, TimeZone tz) {
        if (bh == null) {
            Integer weekday = Math.mod(Date.newInstance(1900, 1, 7).daysBetween(day), 7); // 0 = Sunday
            return weekday != 0 && weekday != 6;
        }
        Datetime noonGmt = Datetime.newInstanceGmt(day, Time.newInstance(12, 0, 0, 0));
        Datetime localNoon = noonGmt.addSeconds(-tz.getOffset(noonGmt) / 1000);
        return BusinessHours.isWithin(bh.Id, localNoon);
    }

    // ── Process Order / Resend Confirmation button (scr_Opportunity_Process_Order) ─

    @InvocableMethod(label='Process Order / Resend Confirmation'
        description='Webshop opportunity: not yet won = set Closed Won (the confirmation follows); won = send the order confirmation again.')
    public static List<String> processOrResend(List<Id> opportunityIds) {
        Map<Id, Opportunity> opps = new Map<Id, Opportunity>([
            SELECT Id, AccountId, RecordTypeId, IsWon, IsClosed, CloseDate, Order_Processed_At__c, Order_Shipping_Date__c
            FROM Opportunity WHERE Id IN :opportunityIds WITH SYSTEM_MODE
        ]);
        List<Opportunity> missingShipping = new List<Opportunity>();
        List<String> messages = new List<String>();
        Set<Id> toProcess = new Set<Id>();
        Set<Id> toSend = new Set<Id>();
        for (Id oppId : opportunityIds) {
            Opportunity opp = opps.get(oppId);
            if (opp == null || opp.RecordTypeId != webshopRecordTypeId) {
                messages.add('Only Webshop orders can be processed here.');
            } else if (opp.IsWon) {
                toSend.add(oppId);
                if (opp.Order_Shipping_Date__c == null) {
                    // won before the confirmation existed: base the shipping day on the close date
                    Opportunity stamp = new Opportunity(Id = opp.Id, AccountId = opp.AccountId,
                        Order_Processed_At__c = opp.Order_Processed_At__c != null ? opp.Order_Processed_At__c
                            : Datetime.newInstance(opp.CloseDate, Time.newInstance(12, 0, 0, 0)));
                    missingShipping.add(stamp);
                }
                messages.add('The order confirmation is being sent again. The send date shows in Order Confirmation Sent.');
            } else if (opp.IsClosed) {
                messages.add('This order is closed and not won: nothing was sent.');
            } else {
                toProcess.add(oppId);
                messages.add('The order is being set to Closed Won; the order confirmation follows. If it stays open, Order Process Error shows why.');
            }
        }
        if (!missingShipping.isEmpty()) {
            stampShipping(missingShipping);
            List<Opportunity> toSave = new List<Opportunity>();
            for (Opportunity o : missingShipping) {
                toSave.add(new Opportunity(Id = o.Id, Order_Processed_At__c = o.Order_Processed_At__c,
                    Order_Shipping_Date__c = o.Order_Shipping_Date__c, Order_Ships_Same_Day__c = o.Order_Ships_Same_Day__c,
                    Order_Shipping_Cutoff__c = o.Order_Shipping_Cutoff__c));
            }
            Database.update(toSave, false, AccessLevel.SYSTEM_MODE);
        }
        publish(toProcess, ACTION_PROCESS);
        publish(toSend, ACTION_SEND);
        return messages;
    }
}
