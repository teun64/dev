global class Util_ForwardedEmailToCase implements Messaging.InboundEmailHandler {

    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        
        // Initialize the Case object
        Case newCase = new Case();
        
        // Extract original sender email from the forwarded email body
        String originalEmail = extractOriginalEmail(email.plainTextBody);
        
        if (originalEmail != null) {
            // Set the Case's contact email
            newCase.SuppliedEmail = originalEmail;
        }
        
        // Capture the recipient email address
        String recipientEmail = (email.toAddresses != null && !email.toAddresses.isEmpty()) ? email.toAddresses[0] : null;
        
        // Determine the queue based on the recipient email
        Group queue = null;
        if (recipientEmail != null && recipientEmail.contains('aftersales')) {
            queue = [SELECT Id FROM Group WHERE DeveloperName = 'gqAfterSalesNL' AND Type = 'Queue' LIMIT 1];
        } else if (recipientEmail != null && recipientEmail.contains('fleetsupport')) {
            queue = [SELECT Id FROM Group WHERE DeveloperName = 'gqSupportFleet1' AND Type = 'Queue' LIMIT 1];
        }
        
        if (queue != null) {
            // Assign the found queue as the case owner
            newCase.OwnerId = queue.Id;
        }
        
        // Set other Case fields as needed
        newCase.Origin = 'Email';
        newCase.Subject = email.subject;
        
        // Limit the description to a maximum of 500 characters
        String emailBody = email.plainTextBody;
        if (emailBody != null && emailBody.length() > 500) {
            emailBody = emailBody.substring(0, 500);
        }
        newCase.Description = emailBody;
        
        newCase.Status = 'New';
        
        // Insert the Case into Salesforce
        try {
            insert newCase;

            // Create an EmailMessage related to the Case
            EmailMessage emailMessage = new EmailMessage();
            emailMessage.ParentId = newCase.Id;
            emailMessage.FromAddress = originalEmail != null ? originalEmail : email.fromAddress;
            emailMessage.ToAddress = recipientEmail;
            emailMessage.Subject = email.subject;
            emailMessage.HtmlBody = email.htmlBody != null ? email.htmlBody : email.plainTextBody;
            emailMessage.Incoming = true;
            emailMessage.Status = '3'; // Set to 'New'
            insert emailMessage;

            result.success = true;
        } catch (Exception e) {
            // Handle any errors
            System.debug('Error creating case or email message: ' + e.getMessage());
            result.success = false;
            result.message = 'Error creating case or email message: ' + e.getMessage();
        }
        
        return result;
    }
    
    private String extractOriginalEmail(String emailBody) {
        // Regex pattern to match "From" in multiple languages: English (From), Dutch (Van), German (Von), French (De)
        Pattern fromPattern = Pattern.compile('(?m)(?im)^\\s*(From|Van|Von|De):\\s*(.+?)\\s*<(.+?)>|^\\s*(From|Van|Von|De):\\s*(.+?)$');
        Matcher matcher = fromPattern.matcher(emailBody);
        
        if (matcher.find()) {
            // Check if the email address is in the third capturing group or the fifth
            if (matcher.group(3) != null) {
                return matcher.group(3).trim();
            } else if (matcher.group(5) != null) {
                return matcher.group(5).trim();
            }
        }
        
        return null;
    }
}