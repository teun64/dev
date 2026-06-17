@IsTest
private class Test_Util_ForwardedEmailToCase {

    @IsTest
    static void testHandleInboundEmail() {
        // Create an instance of the class to be tested
        Util_ForwardedEmailToCase handler = new Util_ForwardedEmailToCase();
        
        // Create a sample InboundEmail and InboundEnvelope
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        
        // Set email properties
        email.subject = 'Test Subject';
        email.fromAddress = 'test@example.com';
        email.toAddresses = new String[] {'aftersales@example.com'};
        email.plainTextBody = 'From: original.sender@example.com\nThis is a test email.';
        email.htmlBody = '<p>From: original.sender@example.com</p><p>This is a test email.</p>';
        
        // Call the method
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        
        // Verify results
        System.assert(result.success, 'Email handling should be successful.');
        
        // Verify the Case was created
        List<Case> cases = [SELECT Id, SuppliedEmail, OwnerId, Origin, Subject, Description, Status FROM Case];
        System.assertEquals(1, cases.size(), 'One case should be created.');
        Case newCase = cases[0];
        System.assertEquals('original.sender@example.com', newCase.SuppliedEmail, 'The supplied email should match the extracted original email.');
        System.assertEquals('Email', newCase.Origin, 'The case origin should be "Email".');
        System.assertEquals('Test Subject', newCase.Subject, 'The case subject should match the email subject.');
        System.assertEquals('From: original.sender@example.com\nThis is a test email.', newCase.Description, 'The case description should match the email body.');
        System.assertEquals('New', newCase.Status, 'The case status should be "New".');
        
        // Verify the Case Owner was set correctly
        Group afterSalesQueue = [SELECT Id FROM Group WHERE DeveloperName = 'gqAfterSalesNL' AND Type = 'Queue' LIMIT 1];
        System.assertEquals(afterSalesQueue.Id, newCase.OwnerId, 'The case owner should be set to the aftersales queue.');

        // Verify the EmailMessage was created
        List<EmailMessage> emailMessages = [SELECT Id, ParentId, FromAddress, ToAddress, Subject, HtmlBody, Incoming, Status FROM EmailMessage WHERE ParentId = :newCase.Id];
        System.assertEquals(1, emailMessages.size(), 'One email message should be created.');
        EmailMessage emailMessage = emailMessages[0];
        System.assertEquals('original.sender@example.com', emailMessage.FromAddress, 'The from address should match the extracted original email.');
        System.assertEquals('aftersales@example.com', emailMessage.ToAddress, 'The to address should match the email recipient.');
        System.assertEquals('Test Subject', emailMessage.Subject, 'The email message subject should match the email subject.');
        System.assertEquals('<p>From: original.sender@example.com</p><p>This is a test email.</p>', emailMessage.HtmlBody, 'The email message HTML body should match the email HTML body.');
        System.assert(emailMessage.Incoming, 'The email message should be marked as incoming.');
        System.assertEquals('3', emailMessage.Status, 'The email message status should be "New".');
    }
    
    @IsTest
    static void testHandleInboundEmailNoOriginalEmail() {
        // Create an instance of the class to be tested
        Util_ForwardedEmailToCase handler = new Util_ForwardedEmailToCase();
        
        // Create a sample InboundEmail and InboundEnvelope
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        
        // Set email properties
        email.subject = 'Test Subject';
        email.fromAddress = 'test@example.com';
        email.toAddresses = new String[] {'fleetsupport@example.com'};
        email.plainTextBody = 'This is a test email without an original sender.';
        email.htmlBody = '<p>This is a test email without an original sender.</p>';
        
        // Call the method
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        
        // Verify results
        System.assert(result.success, 'Email handling should be successful.');
        
        // Verify the Case was created
        List<Case> cases = [SELECT Id, SuppliedEmail, OwnerId, Origin, Subject, Description, Status FROM Case];
        System.assertEquals(1, cases.size(), 'One case should be created.');
        Case newCase = cases[0];
        System.assertEquals(null, newCase.SuppliedEmail, 'The supplied email should be null when no original email is found.');
    //    System.assertEquals('Email', newCase.Origin, 'The case origin should be "Email".');
        System.assertEquals('Test Subject', newCase.Subject, 'The case subject should match the email subject.');
        System.assertEquals('This is a test email without an original sender.', newCase.Description, 'The case description should match the email body.');
        System.assertEquals('New', newCase.Status, 'The case status should be "New".');
        
        // Verify the Case Owner was set correctly
        Group fleetSupportQueue = [SELECT Id FROM Group WHERE DeveloperName = 'gqSupportFleet1' AND Type = 'Queue' LIMIT 1];
        System.assertEquals(fleetSupportQueue.Id, newCase.OwnerId, 'The case owner should be set to the fleet support queue.');

        // Verify the EmailMessage was created
        List<EmailMessage> emailMessages = [SELECT Id, ParentId, FromAddress, ToAddress, Subject, HtmlBody, Incoming, Status FROM EmailMessage WHERE ParentId = :newCase.Id];
        System.assertEquals(1, emailMessages.size(), 'One email message should be created.');
        EmailMessage emailMessage = emailMessages[0];
        System.assertEquals('test@example.com', emailMessage.FromAddress, 'The from address should match the original email from address.');
        System.assertEquals('fleetsupport@example.com', emailMessage.ToAddress, 'The to address should match the email recipient.');
        System.assertEquals('Test Subject', emailMessage.Subject, 'The email message subject should match the email subject.');
        System.assertEquals('<p>This is a test email without an original sender.</p>', emailMessage.HtmlBody, 'The email message HTML body should match the email HTML body.');
        System.assert(emailMessage.Incoming, 'The email message should be marked as incoming.');
        System.assertEquals('3', emailMessage.Status, 'The email message status should be "New".');
    }
}