/**
 * Creates and manages Experience Cloud dealer portal users.
 *
 * Username convention
 *   Production : <email>.miDealer
 *   Sandbox    : <email>.miDealer.<sandboxName>
 *
 * Currently uses the Identity User profile (login-based, 100 seats).
 * When dedicated Customer Community Login licenses are provisioned, update
 * PROFILE_NAME to the new profile name; the ContactId path in
 * Ctrl_DealerShop.getDealerContext() will activate automatically for those users.
 */
public without sharing class Svc_DealerUserSetup {

    @TestVisible private static final String PROFILE_NAME    = 'Identity User';
    @TestVisible private static final String PS_NAME         = 'Authenticated_DealerPortal';
    private static final String             NETWORK_PREFIX   = 'dealer';
    private static final String             USERNAME_SUFFIX  = 'miDealer';

    public class SetupException extends Exception {}

    // ── Public entry point ────────────────────────────────────────────────────

    /**
     * Creates or updates a dealer Experience Cloud user.
     *
     * The Contact's Email is kept in sync with the provided email so that
     * Ctrl_DealerShop.getDealerContext() can resolve the dealer Account via
     * email lookup for Identity-license users (who cannot carry a ContactId).
     *
     * @param email     Login email and username basis.
     * @param contactId Existing Contact on a dealer Account.
     * @return Id of the created or updated User.
     */
    @AuraEnabled
    public static Id createOrUpdateDealerUser(String email, Id contactId) {
        if (String.isBlank(email)) throw new SetupException('email is required.');
        if (contactId == null)      throw new SetupException('contactId is required.');
        email = email.trim().toLowerCase();

        Contact con = [
            SELECT Id, AccountId, FirstName, LastName, Email
            FROM Contact WHERE Id = :contactId WITH SYSTEM_MODE LIMIT 1
        ];
        if (con.AccountId == null) {
            throw new SetupException('Contact ' + contactId + ' must be linked to an Account.');
        }

        if (con.Email != email) {
            con.Email = email;
            update con;
        }

        Id     profileId = resolveProfileId();
        String username  = buildUsername(email);

        List<User> existing = [
            SELECT Id, IsActive FROM User WHERE Username = :username WITH SYSTEM_MODE LIMIT 1
        ];

        Id userId;
        if (!existing.isEmpty()) {
            User u    = existing[0];
            u.Email   = email;
            u.IsActive = true;
            update u;
            userId = u.Id;
        } else {
            User u = new User(
                ProfileId         = profileId,
                Username          = username,
                Email             = email,
                FirstName         = con.FirstName,
                LastName          = con.LastName,
                Alias             = buildAlias(con.FirstName, con.LastName),
                LocaleSidKey      = 'nl_NL',
                LanguageLocaleKey = 'nl_NL',
                TimeZoneSidKey    = 'Europe/Amsterdam',
                EmailEncodingKey  = 'UTF-8',
                IsActive          = true
            );
            insert u;
            userId = u.Id;
        }

        ensureNetworkAccess(profileId);
        assignPsIfExists(userId);

        return userId;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static String buildUsername(String email) {
        String username = email + '.' + USERNAME_SUFFIX;
        String sandboxName = Util_System.getSandboxName();
        if (String.isNotBlank(sandboxName)) {
            username += '.' + sandboxName.toLowerCase();
        }
        return username;
    }

    private static String buildAlias(String firstName, String lastName) {
        String f = String.isBlank(firstName) ? '' : firstName.left(1);
        String l = String.isBlank(lastName)  ? 'user' : lastName.left(7);
        return (f + l).toLowerCase().left(8);
    }

    private static Id resolveProfileId() {
        List<Profile> ps = [
            SELECT Id FROM Profile WHERE Name = :PROFILE_NAME WITH SYSTEM_MODE LIMIT 1
        ];
        if (ps.isEmpty()) throw new SetupException('Profile not found: ' + PROFILE_NAME);
        return ps[0].Id;
    }

    // NetworkMemberGroup DML is blocked in Apex.
    // Grant the Identity User profile access via Experience Builder:
    //   Administration → Members → Add Profiles → Identity User → Save
    private static void ensureNetworkAccess(Id profileId) {
        List<Network> nets = [
            SELECT Id FROM Network WHERE UrlPathPrefix = :NETWORK_PREFIX WITH SYSTEM_MODE LIMIT 1
        ];
        if (nets.isEmpty()) return;
        Integer alreadyMember = [
            SELECT COUNT() FROM NetworkMemberGroup
            WHERE NetworkId = :nets[0].Id AND ParentId = :profileId WITH SYSTEM_MODE
        ];
        if (alreadyMember == 0) {
            System.debug(LoggingLevel.WARN,
                'Identity User profile is not a member of the Dealer Portal network. ' +
                'Add it in Experience Builder → Administration → Members.');
        }
    }

    private static void assignPsIfExists(Id userId) {
        List<PermissionSet> pss = [
            SELECT Id FROM PermissionSet WHERE Name = :PS_NAME WITH SYSTEM_MODE LIMIT 1
        ];
        if (pss.isEmpty()) return;
        Integer already = [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetId = :pss[0].Id WITH SYSTEM_MODE
        ];
        if (already == 0) {
            insert new PermissionSetAssignment(
                AssigneeId      = userId,
                PermissionSetId = pss[0].Id
            );
        }
    }
}
