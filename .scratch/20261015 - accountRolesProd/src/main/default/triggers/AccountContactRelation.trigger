trigger AccountContactRelation on AccountContactRelation (before delete, after insert, after update) {
	Trigger_AccountContactRelation.run();
}
