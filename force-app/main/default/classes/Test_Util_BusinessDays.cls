/**
 * Tests Util_BusinessDays: weekdays without business hours (fixed dates), and the Sales (NL) business hours skip at
 * least the weekends.
 */
@IsTest
private class Test_Util_BusinessDays {

	static Date d(Integer y, Integer m, Integer day) {
		return Date.newInstance(y, m, day);
	}

	@IsTest
	static void weekdays_skipWeekend() {
		Util_BusinessDays.businessHoursOverride = 'No such business hours';
		// Friday 13 Nov 2026 + 3 → Wednesday 18 Nov; + 8 → Wednesday 25 Nov
		Assert.areEqual(d(2026, 11, 18), Util_BusinessDays.add(d(2026, 11, 13), 3, null));
		Assert.areEqual(d(2026, 11, 25), Util_BusinessDays.add(d(2026, 11, 13), 8, null));
		// Monday + 3 → Thursday; Saturday + 1 → Monday
		Assert.areEqual(d(2026, 11, 19), Util_BusinessDays.add(d(2026, 11, 16), 3, null));
		Assert.areEqual(d(2026, 11, 16), Util_BusinessDays.add(d(2026, 11, 14), 1, null));
		// back: Wednesday 18 Nov - 3 → Friday 13 Nov
		Assert.areEqual(d(2026, 11, 13), Util_BusinessDays.add(d(2026, 11, 18), -3, null));
		Assert.areEqual(d(2026, 11, 13), Util_BusinessDays.add(d(2026, 11, 13), 0, null));
	}

	@IsTest
	static void salesHours_noWeekendDays() {
		Date start = d(2026, 11, 13);
		Date result = Util_BusinessDays.add(start, 8, null);
		Assert.isTrue(result >= d(2026, 11, 25), 'at least the weekdays-only result');
		Integer weekday = Math.mod(Date.newInstance(1900, 1, 1).daysBetween(result), 7);
		Assert.isTrue(weekday < 5, 'never on a weekend');
	}

	@IsTest
	static void invocable_emptyInputs() {
		Util_BusinessDays.Request r = new Util_BusinessDays.Request();
		r.startDate = d(2026, 11, 13);
		r.days = 3;
		Util_BusinessDays.Request empty = new Util_BusinessDays.Request();
		List<Util_BusinessDays.Result> res = Util_BusinessDays.run(new List<Util_BusinessDays.Request>{ r, empty });
		Assert.isNotNull(res[0].resultDate);
		Assert.isNull(res[1].resultDate);
	}
}
