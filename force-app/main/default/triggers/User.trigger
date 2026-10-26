trigger User on User (after insert, after update) {
	Trigger_User.run();
}
