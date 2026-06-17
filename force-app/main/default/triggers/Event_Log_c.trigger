/**
 * Created by Gerbrand Spaans (Gen25) on 04/01/2024.
 */

trigger Event_Log_c on Event_Log__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    Trigger_Event_Log.run();
}