/**
 * Business days (2026-11-10): adds N business days to a date, by the business hours "Sales (NL)" (weekends and the
 * holidays on those hours don't count; the same hours as the sales call-back). Without those business hours: Monday
 * to Friday. Used by afl_CampaignMember_Mail_Cycle: the campaign Mail Schedule (Days) counts business days after the
 * release, e.g. "3,8,14" = mail 2 on business day 3, mail 3 on business day 8, closed on business day 14.
 * A day is a business day when the business hours open on that date (nextStartDate from its midnight).
 */
public without sharing class Util_BusinessDays {

	public static final String DEFAULT_BUSINESS_HOURS = 'Sales (NL)';

	// tests of the flow: count every day, so their dates don't depend on the weekday they run on
	@TestVisible
	private static Boolean everyDayForTest = false;
	@TestVisible
	private static String businessHoursOverride;

	private static Map<String, BusinessHours> hoursByName = new Map<String, BusinessHours>();
	private static Map<String, Boolean> businessByKey = new Map<String, Boolean>();

	public class Request {
		@InvocableVariable(label='Start Date')
		public Date startDate;
		@InvocableVariable(label='Business Days' description='Number of business days to add (negative: back)')
		public Integer days;
		@InvocableVariable(label='Business Hours' description='Name of the business hours; empty = Sales (NL)')
		public String businessHoursName;
	}

	public class Result {
		@InvocableVariable(label='Date')
		public Date resultDate;
	}

	@InvocableMethod(label='Add Business Days' description='Start date + N business days (business hours Sales (NL): weekends and holidays skipped).')
	public static List<Result> run(List<Request> requests) {
		List<Result> results = new List<Result>();
		for (Request r : requests) {
			Result res = new Result();
			if (r != null && r.startDate != null && r.days != null) res.resultDate = add(r.startDate, r.days, r.businessHoursName);
			results.add(res);
		}
		return results;
	}

	public static Date add(Date startDate, Integer days, String businessHoursName) {
		if (startDate == null || days == null) return null;
		BusinessHours bh = hours(String.isBlank(businessHoursName) ? DEFAULT_BUSINESS_HOURS : businessHoursName);
		Integer step = days < 0 ? -1 : 1;
		Date d = startDate;
		Integer counted = 0;
		// safety: never more than a year of walking
		for (Integer i = 0; counted < Math.abs(days) && i < 366; i++) {
			d = d.addDays(step);
			if (isBusinessDay(d, bh)) counted++;
		}
		return d;
	}

	public static Boolean isBusinessDay(Date d, BusinessHours bh) {
		if (everyDayForTest) return true;
		String key = (bh == null ? 'weekdays' : bh.Id) + '|' + d;
		if (businessByKey.containsKey(key)) return businessByKey.get(key);
		Boolean business;
		if (bh == null) {
			// Monday = 0 … Sunday = 6 (1900-01-01 was a Monday)
			business = Math.mod(Date.newInstance(1900, 1, 1).daysBetween(d), 7) < 5;
		} else {
			TimeZone tz = TimeZone.getTimeZone(bh.TimeZoneSidKey);
			Datetime gmtMidnight = Datetime.newInstanceGmt(d, Time.newInstance(0, 0, 0, 0));
			Datetime localMidnight = gmtMidnight.addSeconds(-tz.getOffset(gmtMidnight) / 1000);
			Datetime opens = BusinessHours.nextStartDate(bh.Id, localMidnight);
			business = opens != null && opens.format('yyyy-MM-dd', bh.TimeZoneSidKey) == String.valueOf(d);
		}
		businessByKey.put(key, business);
		return business;
	}

	private static BusinessHours hours(String name) {
		if (businessHoursOverride != null) name = businessHoursOverride;
		if (!hoursByName.containsKey(name)) {
			List<BusinessHours> found = [
				SELECT Id, TimeZoneSidKey FROM BusinessHours WHERE Name = :name AND IsActive = true WITH SYSTEM_MODE LIMIT 1
			];
			hoursByName.put(name, found.isEmpty() ? null : found[0]);
		}
		return hoursByName.get(name);
	}
}
