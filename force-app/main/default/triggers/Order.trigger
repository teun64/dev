trigger Order on Order (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    Trigger_Order.run();
}