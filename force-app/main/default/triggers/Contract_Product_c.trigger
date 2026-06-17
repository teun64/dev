trigger Contract_Product_c on Subscription25__Contract_Product__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    Trigger_Contract_Product_c.run();
}