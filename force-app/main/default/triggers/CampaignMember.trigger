trigger CampaignMember on CampaignMember (before insert, before update) {
	Svc_CampaignResponse.stampTokens(Trigger.new);
}
