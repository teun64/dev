trigger CampaignConfirmationEvent on CampaignConfirmation__e (after insert) {
    Svc_CampaignConfirmation.send(Trigger.new);
}
