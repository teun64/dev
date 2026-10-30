@IsTest(SeeAllData=false)
private class Test_Ctrl_OrderDeliveryRecipient {

    // Two attention lines: line 1 bold, line 2 plain, the account name left out.
    @IsTest
    static void testAttentionReplacesAccountName() {
        Ctrl_OrderDeliveryRecipient ctrl = new Ctrl_OrderDeliveryRecipient();
        ctrl.attentionText = 'Jan de Vries\r\nAfdeling Inkoop';
        ctrl.recipientAccountName = 'Test Dealer B.V.';
        System.assertEquals('<strong>Jan de Vries</strong><br/>Afdeling Inkoop', ctrl.getRecipientHtml());
    }

    // No attention: the account name in bold.
    @IsTest
    static void testAccountNameFallback() {
        Ctrl_OrderDeliveryRecipient ctrl = new Ctrl_OrderDeliveryRecipient();
        ctrl.attentionText = '  \n ';
        ctrl.recipientAccountName = 'Test & Dealer';
        System.assertEquals('<strong>Test &amp; Dealer</strong>', ctrl.getRecipientHtml());

        ctrl.recipientAccountName = null;
        System.assertEquals('', ctrl.getRecipientHtml());
    }

    // Blank lines dropped, lines trimmed, max 2 lines of max 100 chars, HTML escaped.
    @IsTest
    static void testAttentionLines() {
        System.assertEquals(new List<String>(), Ctrl_OrderDeliveryRecipient.attentionLines(null));
        System.assertEquals(
            new List<String>{ 'a', 'b' },
            Ctrl_OrderDeliveryRecipient.attentionLines('\n  a  \n\n b\nc')
        );
        System.assertEquals(100, Ctrl_OrderDeliveryRecipient.attentionLines('x'.repeat(150))[0].length());

        Ctrl_OrderDeliveryRecipient ctrl = new Ctrl_OrderDeliveryRecipient();
        ctrl.attentionText = '<b>x</b>';
        System.assertEquals('<strong>&lt;b&gt;x&lt;/b&gt;</strong>', ctrl.getRecipientHtml());
    }
}
