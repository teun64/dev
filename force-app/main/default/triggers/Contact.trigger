trigger Contact on Contact (before insert, before update, before delete, after delete) {
	Trigger_Contact.run();
}
