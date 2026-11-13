trigger CampaignMember on CampaignMember (before insert, before update, after insert, after update) {
	if (Trigger.isBefore) {
		Svc_CampaignResponse.stampTokens(Trigger.new);
		Svc_CampaignCallMe.beforeSave(Trigger.new, Trigger.oldMap);
	} else {
		Svc_CampaignCallMe.afterSave(Trigger.new, Trigger.oldMap);
	}
}
