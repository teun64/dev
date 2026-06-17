global with sharing class Queue_FinancialSystemOrderSync implements Queueable, Database.AllowsCallouts {
	private Id orderId;
	private String mainLogGuid;

	global Queue_FinancialSystemOrderSync(Order orderRecord, String mainLogGuid) {
		this(orderRecord.Id, mainLogGuid);
	}

	global Queue_FinancialSystemOrderSync(Id orderId, String mainLogGuid) {
		this.orderId = orderId;
		this.mainLogGuid = mainLogGuid;
	}

	global void execute(QueueableContext context) {
		List<String> messages = Util_FinancialSystem.syncOrder(this.orderId, this.mainLogGuid);

		if (messages.isEmpty()) {
			Database.update(new Order(
				Id = this.orderId,
				Status = 'Activated'
			), false);
		}
	}
}
