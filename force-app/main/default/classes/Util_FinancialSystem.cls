/**
 * Generic financial system (Exact Online) layer, shared by Util_FinancialSystemAccount,
 * Util_FinancialSystem_Order and Util_FinancialSystem_Invoice.
 *
 * - Every call goes through the administration's Named Credential (Util_OAuth: transport + OAuth_Log__c).
 * - Sandbox guard: a call is refused unless Util_System.isFinancialSyncAllowed(admin), so a sandbox can
 *   never reach the production financial system.
 * - Rate limits: Exact returns X-RateLimit-* headers on every response (minutely + daily, per app and
 *   division). Batch_FinancialSystemRateLimitCheck reads them daily into the administration; every
 *   response updates them in memory and saveLimits() stores them after the callouts. Batches ask
 *   hasBatchCapacity(n) before a unit of work: minutely reserve + at most FinancialRateLimitMaxPercentage__c
 *   of the daily limit. A 429 marks the administration as limited.
 * - Errors are never swallowed: an Exact error, a non-2xx status or a callout exception becomes a
 *   Util_System.FinancialSyncException (isRateLimited tells a 429 apart).
 */
public without sharing class Util_FinancialSystem {
	public static final String SYNC_EXACT = 'Exact';

	// calls kept free per minute for manual "sync now" actions; daily: see FinancialRateLimitMaxPercentage__c
	public static final Integer MINUTELY_RESERVE = 5;
	// daily reserve used only when the daily limit itself is unknown
	public static final Integer DAILY_RESERVE = 250;

	private static final Set<String> RESPONSE_FIELDS_TO_STRIP = new Set<String>{
		'SalesOrderLines', 'Approved', 'Created', 'DeliveryDate', 'Modified', 'OrderDate', 'BankAccounts'
	};

	public class RateLimitException extends Exception {}

	// ---------------------------------------------------------------- administration

	/**
	 * The administration for a reseller (Account.Reseller_Name__c), or null when there is none.
	 */
	public static Subscription25__Administration__c getAdministrationForReseller(String reseller) {
		if (String.isBlank(reseller)) {
			return null;
		}
		return Util_System.getAdministration(Util_System.getAdminExternalId(Long.valueOf(reseller)));
	}

	/**
	 * True when the administration syncs to Exact, is active and may be called from this org.
	 */
	public static Boolean isSyncEnabled(Subscription25__Administration__c admin) {
		return admin != null
			&& admin.Subscription25__Active__c
			&& admin.Subscription25__Synchronisation__c == Util_FinancialSystem.SYNC_EXACT
			&& String.isNotBlank(admin.Subscription25__Named_Credential__c)
			&& Util_System.isFinancialSyncAllowed(admin);
	}

	// ---------------------------------------------------------------- requests

	/**
	 * Calls the financial system and returns the serialized "d" payload ('' for 204 No Content).
	 * Throws Util_System.FinancialSyncException on any failure; RateLimitException on 429 / no capacity.
	 */
	public static String doRequest(Subscription25__Administration__c admin, String endpoint, Map<String, String> params,
			String method, String requestBody, String logGuid) {
		if (admin == null || !Util_System.isFinancialSyncAllowed(admin)) {
			throw new Util_System.FinancialSyncException('Financial system sync is not allowed for this administration from this org.');
		}
		Util_FinancialSystem.Limits lim = Util_FinancialSystem.getLimits(admin);
		if (!lim.hasCapacity(1)) {
			throw new Util_FinancialSystem.RateLimitException('Financial system rate limit reached for ' + admin.Name + '; retry after the reset.');
		}

		HttpResponse res;
		try {
			res = Util_OAuth.getInstance(admin.Subscription25__Named_Credential__c, logGuid).doRequest(endpoint, params, method, requestBody);
		} catch (CalloutException e) {
			throw new Util_System.FinancialSyncException('Callout to the financial system failed: ' + e.getMessage());
		}
		lim.register(res);

		Integer status = res.getStatusCode();
		if (status == 204) {
			return '';
		}
		if (status == 429) {
			throw new Util_FinancialSystem.RateLimitException('Financial system rate limit reached (429) for ' + admin.Name + '.');
		}
		// Exact answers 500 when a bank account already exists; callers handle this marker
		if (status == 500 && endpoint.contains('BankAccounts')) {
			return '500';
		}

		String body = res.getBody();
		Object parsed;
		try {
			parsed = String.isBlank(body) ? null : JSON.deserializeUntyped(body);
		} catch (JSONException e) {
			throw new Util_System.FinancialSyncException('Unreadable response from the financial system (HTTP ' + status + '): ' + body?.left(255));
		}
		if (parsed instanceof Map<String, Object>) {
			Map<String, Object> dirty = (Map<String, Object>) parsed;
			if (dirty.containsKey('error')) {
				throw new Util_System.FinancialSyncException(Util_FinancialSystem.getErrorMessage(dirty));
			}
			if (status < 200 || status > 299) {
				throw new Util_System.FinancialSyncException('Financial system returned HTTP ' + status + ': ' + body.left(255));
			}
			Object d = dirty.get('d');
			if (d instanceof Map<String, Object>) {
				// some fields break deserialization into the request wrappers
				for (String field : Util_FinancialSystem.RESPONSE_FIELDS_TO_STRIP) {
					((Map<String, Object>) d).remove(field);
				}
			}
			return JSON.serialize(d);
		}
		if (status < 200 || status > 299) {
			throw new Util_System.FinancialSyncException('Financial system returned HTTP ' + status + ': ' + body?.left(255));
		}
		return parsed == null ? '' : JSON.serialize(parsed);
	}

	private static String getErrorMessage(Map<String, Object> dirty) {
		try {
			Map<String, Object> errMap = (Map<String, Object>) dirty.get('error');
			Object msg = errMap.get('message');
			if (msg instanceof Map<String, Object>) {
				return (String) ((Map<String, Object>) msg).get('value');
			}
			return String.valueOf(msg);
		} catch (Exception e) {
			return JSON.serialize(dirty.get('error')).left(255);
		}
	}

	/**
	 * Escapes and normalises a value for an OData string literal in a $filter (same rules as Util_Exact).
	 */
	public static String odataString(String str) {
		if (String.isBlank(str)) {
			return str;
		}
		String retStr = str.replaceAll('\'', '\'\'');
		retStr = retStr.replaceAll('[\\s]', ' ');
		retStr = retStr.replaceAll('[*|\\t]', '');
		retStr = retStr.replace('  ', ' ');
		retStr = retStr.trim();
		return EncodingUtil.urlEncode(retStr, 'UTF-8');
	}

	// ---------------------------------------------------------------- logging

	/**
	 * Saves the Event_Log__c and the OAuth logs of the given named credentials. Call once, after all callouts.
	 */
	public static void saveLogs(List<Event_Log__c> eventLogs, Set<String> namedCredentials, String logGuid) {
		if (eventLogs != null && !eventLogs.isEmpty()) {
			Database.upsert(eventLogs, Event_Log__c.GUID__c, false, AccessLevel.SYSTEM_MODE);
		}
		if (namedCredentials != null) {
			for (String nc : namedCredentials) {
				if (String.isNotBlank(nc)) {
					Util_OAuth.getInstance(nc, logGuid).saveToken();
				}
			}
		}
	}

	// ---------------------------------------------------------------- rate limits

	public static final Decimal DEFAULT_MAX_PERCENTAGE = 90;

	private static Map<Id, Util_FinancialSystem.Limits> limitsByAdmin = new Map<Id, Util_FinancialSystem.Limits>();

	public static Util_FinancialSystem.Limits getLimits(Subscription25__Administration__c admin) {
		if (!Util_FinancialSystem.limitsByAdmin.containsKey(admin.Id)) {
			Util_FinancialSystem.limitsByAdmin.put(admin.Id, new Util_FinancialSystem.Limits(admin));
		}
		return Util_FinancialSystem.limitsByAdmin.get(admin.Id);
	}

	/**
	 * Stores the rate-limit state seen in this transaction on the administrations (Daily_Limit__c,
	 * FinancialRateLimitRemaining__c, ...ResetOn__c, ...CheckedOn__c). Call once, after all callouts.
	 */
	public static void saveLimits() {
		List<Subscription25__Administration__c> toUpdate = new List<Subscription25__Administration__c>();
		for (Id adminId : Util_FinancialSystem.limitsByAdmin.keySet()) {
			Util_FinancialSystem.Limits lim = Util_FinancialSystem.limitsByAdmin.get(adminId);
			if (lim.callsMade == 0) {
				continue;
			}
			toUpdate.add(new Subscription25__Administration__c(
				Id = adminId,
				Daily_Limit__c = lim.dailyLimit,
				FinancialRateLimitRemaining__c = lim.dailyRemaining,
				FinancialRateLimitResetOn__c = lim.dailyReset == null ? null : Datetime.newInstance(lim.dailyReset),
				FinancialRateLimitCheckedOn__c = System.now()
			));
		}
		if (!toUpdate.isEmpty()) {
			Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
		}
	}

	/**
	 * Rate-limit state of one administration. Starts from what is stored on the administration
	 * (daily check / previous batch run) and is kept up to date by Exact's X-RateLimit-* response headers.
	 * Unknown values are treated as available.
	 */
	public class Limits {
		public Integer dailyLimit;
		public Integer dailyRemaining;
		public Long dailyReset;
		public Integer minutelyRemaining;
		public Long minutelyReset;
		public Decimal maxPercentage;
		public Boolean limited = false;
		public Integer callsMade = 0;

		public Limits(Subscription25__Administration__c admin) {
			this.dailyLimit = admin.Daily_Limit__c == null ? null : admin.Daily_Limit__c.intValue();
			this.maxPercentage = admin.FinancialRateLimitMaxPercentage__c == null
				? Util_FinancialSystem.DEFAULT_MAX_PERCENTAGE : admin.FinancialRateLimitMaxPercentage__c;
			// the stored remaining value only counts until its reset moment
			if (admin.FinancialRateLimitResetOn__c != null && admin.FinancialRateLimitResetOn__c > System.now()
					&& admin.FinancialRateLimitRemaining__c != null) {
				this.dailyRemaining = admin.FinancialRateLimitRemaining__c.intValue();
				this.dailyReset = admin.FinancialRateLimitResetOn__c.getTime();
			}
		}

		/**
		 * Hard limit: true when n more calls fit at all (used for single, manual syncs).
		 */
		public Boolean hasCapacity(Integer n) {
			Long now = System.now().getTime();
			if (this.minutelyRemaining != null && (this.minutelyReset == null || this.minutelyReset > now)
					&& this.minutelyRemaining - n < 0) {
				return false;
			}
			if (this.dailyRemaining != null && (this.dailyReset == null || this.dailyReset > now)
					&& this.dailyRemaining - n < 0) {
				return false;
			}
			return true;
		}

		/**
		 * Batch budget: true when a unit of work of n calls fits while keeping the minutely reserve free
		 * and staying under maxPercentage of the daily limit.
		 */
		public Boolean hasBatchCapacity(Integer n) {
			Long now = System.now().getTime();
			if (this.minutelyRemaining != null && (this.minutelyReset == null || this.minutelyReset > now)
					&& this.minutelyRemaining - n < Util_FinancialSystem.MINUTELY_RESERVE) {
				return false;
			}
			Boolean dailyKnown = this.dailyRemaining != null && (this.dailyReset == null || this.dailyReset > now);
			if (dailyKnown && this.dailyLimit != null) {
				Integer used = this.dailyLimit - this.dailyRemaining;
				Integer allowed = (this.dailyLimit * this.maxPercentage / 100).intValue();
				if (used + n > allowed) {
					return false;
				}
			} else if (dailyKnown && this.dailyRemaining - n < Util_FinancialSystem.DAILY_RESERVE) {
				return false;
			}
			return this.hasCapacity(n);
		}

		/**
		 * Share of the daily limit used so far (0-100), or null when unknown.
		 */
		public Decimal usedPercentage() {
			if (this.dailyLimit == null || this.dailyLimit == 0 || this.dailyRemaining == null) {
				return null;
			}
			return ((this.dailyLimit - this.dailyRemaining) * 100.0 / this.dailyLimit).setScale(1);
		}

		public void register(HttpResponse res) {
			this.callsMade++;
			this.dailyLimit = Util_FinancialSystem.headerInt(res, 'X-RateLimit-Limit', this.dailyLimit);
			this.dailyRemaining = Util_FinancialSystem.headerInt(res, 'X-RateLimit-Remaining', this.dailyRemaining);
			this.dailyReset = Util_FinancialSystem.headerLong(res, 'X-RateLimit-Reset', this.dailyReset);
			this.minutelyRemaining = Util_FinancialSystem.headerInt(res, 'X-RateLimit-Minutely-Remaining', this.minutelyRemaining);
			this.minutelyReset = Util_FinancialSystem.headerLong(res, 'X-RateLimit-Minutely-Reset', this.minutelyReset);
			if (res.getStatusCode() == 429) {
				this.limited = true;
				this.minutelyRemaining = 0;
				if (this.minutelyReset == null || this.minutelyReset <= System.now().getTime()) {
					this.minutelyReset = System.now().addMinutes(1).getTime();
				}
			}
		}
	}

	private static Integer headerInt(HttpResponse res, String name, Integer fallback) {
		String v = res.getHeader(name);
		try {
			return String.isBlank(v) ? fallback : Integer.valueOf(v.trim());
		} catch (Exception e) {
			return fallback;
		}
	}

	private static Long headerLong(HttpResponse res, String name, Long fallback) {
		String v = res.getHeader(name);
		try {
			return String.isBlank(v) ? fallback : Long.valueOf(v.trim());
		} catch (Exception e) {
			return fallback;
		}
	}
}
