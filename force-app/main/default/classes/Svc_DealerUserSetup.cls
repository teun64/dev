/**
 * Creates and manages Experience Cloud dealer portal users.
 *
 * Username convention
 *   Production : <email>.miDealer
 *   Sandbox    : <email>.miDealer.<sandboxName>
 * A +tag in the email is left out of the username (name+test@x.com → name@x.com.miDealer);
 * the User and Contact keep the full email, so mail still reaches the +address.
 *
 * Users get the generic miCustomerCommunityPlus profile (Customer Community Plus licence, no
 * object access) plus pg_miDealerPortal, which carries all dealer access. The site member
 * ps_miDealerPortal_User is also assigned directly: site membership does not count through a
 * permission set inside a group (login fails with "No community access"). They are linked to the Contact via
 * ContactId, so Ctrl_DealerShop.getDealerContext() resolves the dealer Account through the
 * Contact. The Account owner needs a role for that link.
 *
 * Re-activating an existing user sends a password reset email (no welcome email is sent then).
 *
 * Entry points: the Contact actions Enable/Disable Customer User (via Inv_CustomerUser) and
 * createOrUpdateDealerUser(). Only sysadmins or holders of cp_miExperienceCloudCustomer_Admin
 * may call them; all DML runs in system mode.
 */
public without sharing class Svc_DealerUserSetup {

    @TestVisible private static final String PROFILE_NAME    = 'miCustomerCommunityPlus';
    @TestVisible private static final String PSG_NAME        = 'pg_miDealerPortal';
    @TestVisible private static final String MEMBER_PS_NAME  = 'ps_miDealerPortal_User';
    @TestVisible private static final String PERMISSION_NAME = 'cp_miExperienceCloudCustomer_Admin';
    private static final String             NETWORK_NAME     = 'Dealer Portal';
    private static final String             USERNAME_SUFFIX  = 'miDealer';
    @TestVisible private static final String INVITE_TEMPLATE = 'DealerPortal_Invite';
    @TestVisible private static final String FALLBACK_SENDER = 'info@movingintelligence.com';

    public class SetupException extends Exception {}

    // ── Public entry points ───────────────────────────────────────────────────

    /**
     * Enables (creates or re-activates) the dealer user for a Contact, using the Contact's Email.
     *
     * @param contactId Contact on a dealer Account.
     * @return the active User.
     */
    public static User enableDealerUser(Id contactId) {
        if (contactId == null) throw new SetupException('contactId is required.');
        Contact con = getContact(contactId);
        if (String.isBlank(con.Email)) {
            throw new SetupException('The contact has no email address. Fill in Email first; it is used for the username.');
        }
        Id userId = createOrUpdateDealerUser(con.Email, contactId);
        return [SELECT Id, Username, IsActive FROM User WHERE Id = :userId WITH SYSTEM_MODE];
    }

    /**
     * Deactivates the customer user linked to a Contact. The User keeps its Contact link,
     * so enableDealerUser() can re-activate it later.
     *
     * @param contactId Contact with an active customer user.
     * @return the deactivated User.
     */
    public static User disableDealerUser(Id contactId) {
        checkAccess();
        if (contactId == null) throw new SetupException('contactId is required.');

        List<User> users = [
            SELECT Id, Username, IsActive FROM User
            WHERE ContactId = :contactId AND IsActive = true WITH SYSTEM_MODE LIMIT 1
        ];
        if (users.isEmpty()) throw new SetupException('This contact has no active customer user.');

        User u = users[0];
        u.IsActive = false;
        Database.update(u, AccessLevel.SYSTEM_MODE);
        return u;
    }

    /**
     * Creates or updates a dealer Experience Cloud user.
     *
     * An existing user is found on ContactId first (a Contact carries one portal user at most),
     * then on the username. Username, Email and IsActive are always reset to the convention.
     * The Contact's Email is kept in sync with the provided email.
     *
     * @param email     Login email and username basis.
     * @param contactId Existing Contact on a dealer Account.
     * @return Id of the created or updated User.
     */
    @AuraEnabled
    public static Id createOrUpdateDealerUser(String email, Id contactId) {
        checkAccess();
        if (String.isBlank(email)) throw new SetupException('email is required.');
        if (contactId == null)      throw new SetupException('contactId is required.');
        email = email.trim().toLowerCase();

        Contact con = getContact(contactId);
        if (con.AccountId == null) {
            throw new SetupException('Contact ' + contactId + ' must be linked to an Account.');
        }

        Boolean contactEmailNeedsSync = con.Email != email;

        Id     profileId = resolveProfileId();
        String username  = buildUsername(email);

        User existing = findExistingUser(contactId, username);

        Id userId;
        Boolean sendInvite = true;
        Boolean reactivated = false;
        if (existing != null) {
            reactivated = !existing.IsActive;
            sendInvite  = reactivated; // an already active user gets no Salesforce mail, so no heads-up either
            existing.Username = username;
            existing.Email    = email;
            existing.IsActive = true;
            applyLanguage(existing, con);
            Database.update(existing, AccessLevel.SYSTEM_MODE);
            userId = existing.Id;
        } else {
            if (con.Account.Owner.UserRoleId == null) {
                throw new SetupException('The account owner (' + con.Account.Owner.Name + ') has no role. ' +
                    'A customer user needs an account owner with a role: change the account owner or give the owner a role.');
            }
            User u = new User(
                ProfileId         = profileId,
                ContactId         = contactId,
                Username          = username,
                Email             = email,
                FirstName         = con.FirstName,
                LastName          = con.LastName,
                Alias             = buildAlias(con.FirstName, con.LastName),
                CommunityNickname = buildNickname(email),
                TimeZoneSidKey    = 'Europe/Amsterdam',
                EmailEncodingKey  = 'UTF-8',
                IsActive          = true
            );
            // Sends the Dealer Portal welcome email (network sendWelcomeEmail = true).
            applyLanguage(u, con);
            Database.DMLOptions dml = new Database.DMLOptions();
            dml.EmailHeader.triggerUserEmail = true;
            Database.insert(u, dml, AccessLevel.SYSTEM_MODE);
            userId = u.Id;
        }

        // Reactivation sends no welcome email (that only fires on insert), and a deactivate/activate
        // cycle invalidates the old welcome link: send a password reset mail instead.
        if (reactivated) {
            System.resetPassword(userId, true);
        }

        if (sendInvite) sendInviteEmail(userId, con);

        assignPsgIfExists(userId);
        Id memberPsId = assignMemberPsIfExists(userId);
        ensureNetworkAccess(memberPsId);

        // Deferred to @future: mixing DML on a setup object (User/PermissionSetAssignment,
        // above) with a non-setup object (Contact) in the same transaction throws
        // MIXED_DML_OPERATION regardless of which happens first - only running it in a
        // separate transaction avoids it.
        if (contactEmailNeedsSync) {
            syncContactEmailAsync(con.Id, email);
        }

        return userId;
    }

    /**
     * Heads-up mail from us (template DealerPortal_Invite, in the user's language): a separate Salesforce
     * mail with the login link follows. Sender = the reseller's org-wide address, like the order
     * confirmation: Business Entity Email_Sales__c, then the administration's billing email, then info@.
     * Reply-To = the reseller's sales email. Never throws: a failed heads-up must not block the user.
     */
    private static void sendInviteEmail(Id userId, Contact con) {
        try {
            List<EmailTemplate> tpl = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :INVITE_TEMPLATE WITH SYSTEM_MODE LIMIT 1];
            if (tpl.isEmpty()) return;

            String reseller = con.Account?.Reseller_Name__c;
            String salesEmail;
            String billingEmail;
            if (reseller != null) {
                for (Business_Entities__c be : [
                    SELECT Email_Sales__c FROM Business_Entities__c WHERE Reseller__c = :reseller WITH SYSTEM_MODE LIMIT 1
                ]) salesEmail = be.Email_Sales__c;
                for (Subscription25__Administration__c adm : [
                    SELECT Subscription25__Billing_Email_Address__c FROM Subscription25__Administration__c
                    WHERE Reseller__c = :reseller WITH SYSTEM_MODE LIMIT 1
                ]) billingEmail = adm.Subscription25__Billing_Email_Address__c;
            }
            Map<String, Id> senderByAddress = new Map<String, Id>();
            for (OrgWideEmailAddress owe : [
                SELECT Id, Address FROM OrgWideEmailAddress WHERE IsVerified = true AND IsAllowAllProfiles = true WITH SYSTEM_MODE
            ]) senderByAddress.put(owe.Address.toLowerCase(), owe.Id);
            Id senderId;
            for (String addr : new List<String>{ salesEmail, billingEmail, FALLBACK_SENDER }) {
                if (String.isNotBlank(addr) && senderByAddress.containsKey(addr.toLowerCase())) {
                    senderId = senderByAddress.get(addr.toLowerCase());
                    break;
                }
            }

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setTemplateId(tpl[0].Id);
            msg.setTargetObjectId(userId);
            msg.setSaveAsActivity(false);
            if (senderId != null) msg.setOrgWideEmailAddressId(senderId);
            if (String.isNotBlank(salesEmail)) msg.setReplyTo(salesEmail);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg }, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Dealer Portal invite email not sent: ' + e.getMessage());
        }
    }

    @future
    private static void syncContactEmailAsync(Id contactId, String email) {
        Database.update(new Contact(Id = contactId, Email = email), AccessLevel.SYSTEM_MODE);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    // The class runs in system mode, so the button visibility alone is not enough.
    @TestVisible
    private static void checkAccess() {
        if (FeatureManagement.checkPermission(PERMISSION_NAME)) return;
        User me = [SELECT isSysAdmin__c FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE];
        if (me.isSysAdmin__c) return;
        throw new SetupException('You are not allowed to manage customer users (' + PERMISSION_NAME + ' required).');
    }

    private static Contact getContact(Id contactId) {
        List<Contact> cons = [
            SELECT Id, AccountId, FirstName, LastName, Email, Language__c, Account.Sales_Language__c,
                   Account.Reseller_Name__c, Account.Owner.Name, Account.Owner.UserRoleId
            FROM Contact WHERE Id = :contactId WITH SYSTEM_MODE LIMIT 1
        ];
        if (cons.isEmpty()) throw new SetupException('Contact ' + contactId + ' not found.');
        return cons[0];
    }

    private static User findExistingUser(Id contactId, String username) {
        List<User> byContact = [
            SELECT Id, Username, IsActive FROM User WHERE ContactId = :contactId WITH SYSTEM_MODE LIMIT 1
        ];
        if (!byContact.isEmpty()) return byContact[0];

        List<User> byUsername = [
            SELECT Id, Username, IsActive, ContactId FROM User WHERE Username = :username WITH SYSTEM_MODE LIMIT 1
        ];
        if (byUsername.isEmpty()) return null;
        throw new SetupException('Username ' + username + ' is already used by another user (' + byUsername[0].Id + '). ' +
            'Change or free up that user first.');
    }

    // Also used by Ctrl_DealerPortalLogin to turn the email a dealer types into the username.
    public static String buildUsername(String email) {
        String local = email.substringBefore('@');
        if (local.contains('+')) local = local.substringBefore('+');
        return local + '@' + email.substringAfter('@') + usernameSuffix();
    }

    // '.miDealer' in production, '.miDealer.<sandbox>' in a sandbox.
    public static String usernameSuffix() {
        String suffix = '.' + USERNAME_SUFFIX;
        String sandboxName = Util_System.getSandboxName();
        if (String.isNotBlank(sandboxName)) {
            suffix += '.' + sandboxName.toLowerCase();
        }
        return suffix;
    }

    // Language + locale of the portal user (welcome / password emails, Salesforce login pages).
    private static final Map<String, List<String>> LANGUAGE_LOCALES = new Map<String, List<String>>{
        'nl' => new List<String>{ 'nl_NL', 'nl_NL' },
        'en' => new List<String>{ 'en_US', 'en_GB' },
        'de' => new List<String>{ 'de',    'de_DE' },
        'fr' => new List<String>{ 'fr',    'fr_FR' }
    };

    // Contact.Language__c holds country-style codes; BE is ambiguous (nl/fr) and falls through.
    private static final Map<String, String> CONTACT_LANGUAGES = new Map<String, String>{
        'NL' => 'nl',
        'DE' => 'de', 'AT' => 'de', 'CH' => 'de',
        'EN' => 'en', 'GB' => 'en',
        'FR' => 'fr', 'LU' => 'fr', 'MC' => 'fr'
    };

    // Contact.Language__c first, then Account.Sales_Language__c, else nl.
    @TestVisible
    private static String resolveLanguage(String contactLanguage, String accountLanguage) {
        if (String.isNotBlank(contactLanguage) && CONTACT_LANGUAGES.containsKey(contactLanguage.toUpperCase())) {
            return CONTACT_LANGUAGES.get(contactLanguage.toUpperCase());
        }
        if (String.isNotBlank(accountLanguage) && LANGUAGE_LOCALES.containsKey(accountLanguage.toLowerCase())) {
            return accountLanguage.toLowerCase();
        }
        return 'nl';
    }

    private static void applyLanguage(User u, Contact con) {
        List<String> keys = LANGUAGE_LOCALES.get(resolveLanguage(con.Language__c, con.Account?.Sales_Language__c));
        u.LanguageLocaleKey = keys[0];
        u.LocaleSidKey      = keys[1];
    }

    private static String buildAlias(String firstName, String lastName) {
        String f = String.isBlank(firstName) ? '' : firstName.left(1);
        String l = String.isBlank(lastName)  ? 'user' : lastName.left(7);
        return (f + l).toLowerCase().left(8);
    }

    // CommunityNickname must be unique org-wide (max 40).
    private static String buildNickname(String email) {
        return email.substringBefore('@').left(30) + '.' + String.valueOf(Crypto.getRandomInteger()).right(6);
    }

    private static Id resolveProfileId() {
        List<Profile> ps = [
            SELECT Id FROM Profile WHERE Name = :PROFILE_NAME WITH SYSTEM_MODE LIMIT 1
        ];
        if (ps.isEmpty()) throw new SetupException('Profile not found: ' + PROFILE_NAME);
        return ps[0].Id;
    }

    // NetworkMemberGroup DML is blocked in Apex.
    // Grant the permission set access via Experience Workspaces:
    //   Administration → Members → Select Permission Sets → ps_miDealerPortal_User → Save
    private static void ensureNetworkAccess(Id memberPsId) {
        if (memberPsId == null) return;
        List<Network> nets = [
            SELECT Id FROM Network WHERE Name = :NETWORK_NAME WITH SYSTEM_MODE LIMIT 1
        ];
        if (nets.isEmpty()) return;
        Integer alreadyMember = [
            SELECT COUNT() FROM NetworkMemberGroup
            WHERE NetworkId = :nets[0].Id AND ParentId = :memberPsId WITH SYSTEM_MODE
        ];
        if (alreadyMember == 0) {
            System.debug(LoggingLevel.WARN,
                MEMBER_PS_NAME + ' is not a member of the Dealer Portal network. ' +
                'Add it in Experience Workspaces → Administration → Members.');
        }
    }

    private static void assignPsgIfExists(Id userId) {
        List<PermissionSetGroup> psgs = [
            SELECT Id FROM PermissionSetGroup WHERE DeveloperName = :PSG_NAME WITH SYSTEM_MODE LIMIT 1
        ];
        if (psgs.isEmpty()) return;
        Integer already = [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetGroupId = :psgs[0].Id WITH SYSTEM_MODE
        ];
        if (already == 0) {
            Database.insert(new PermissionSetAssignment(
                AssigneeId           = userId,
                PermissionSetGroupId = psgs[0].Id
            ), AccessLevel.SYSTEM_MODE);
        }
    }

    private static Id assignMemberPsIfExists(Id userId) {
        List<PermissionSet> pss = [
            SELECT Id FROM PermissionSet WHERE Name = :MEMBER_PS_NAME WITH SYSTEM_MODE LIMIT 1
        ];
        if (pss.isEmpty()) return null;
        Integer already = [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetId = :pss[0].Id AND PermissionSetGroupId = null WITH SYSTEM_MODE
        ];
        if (already == 0) {
            Database.insert(new PermissionSetAssignment(
                AssigneeId      = userId,
                PermissionSetId = pss[0].Id
            ), AccessLevel.SYSTEM_MODE);
        }
        return pss[0].Id;
    }
}
