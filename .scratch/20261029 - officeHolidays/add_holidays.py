#!/usr/bin/env python3
"""Adds NL + UK (England & Wales) public holidays 2026-2035 to a retrieved BusinessHours.settings-meta.xml and
links them to Office (NL) / Office (UK). Naming as the existing ones: recurring fixed dates without a year
("Christmas Day"), moving dates "YYYY - Name". Holidays are matched by name: existing ones only get the link.
Usage: python3 add_holidays.py <settings file in> <settings file out>"""
import re, sys, datetime as dt
from xml.sax.saxutils import escape
src, out = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8').read()
YEARS = range(2026, 2036)
NL, UK = 'Office (NL)', 'Office (UK)'

def easter(y):
    a=y%19;b=y//100;c=y%100;d=b//4;e=b%4;f=(b+8)//25;g=(b-f+1)//3;h=(19*a+b-d-g+15)%30;i=c//4;k=c%4
    l=(32+2*e+2*i-h-k)%7;m=(a+11*h+22*l)//451;mo=(h+l-7*m+114)//31;da=((h+l-7*m+114)%31)+1
    return dt.date(y,mo,da)
def first_monday(y,m):
    d=dt.date(y,m,1); return d+dt.timedelta((0-d.weekday())%7)
def last_monday(y,m):
    d=dt.date(y,m+1,1)-dt.timedelta(1); return d-dt.timedelta(d.weekday())

wanted = {}   # name -> (date or None for recurring, set of business hours)
def add(name, date, bh): wanted.setdefault(name, [date, set()])[1].add(bh)
for rec in ("New Year's Day", "Christmas Day", "Boxing Day"): add(rec, None, NL); add(rec, None, UK)
add("King's Birthday", None, NL)
for y in YEARS:
    e = easter(y)
    add(f'{y} - Easter Day', e, NL); add(f'{y} - Easter Monday', e+dt.timedelta(1), NL)
    add(f'{y} - Ascension Day', e+dt.timedelta(39), NL)
    add(f'{y} - Whit Sunday', e+dt.timedelta(49), NL); add(f'{y} - Whit Monday', e+dt.timedelta(50), NL)
    if y % 5 == 0: add(f'{y} - Liberation Day', dt.date(y,5,5), NL)
    add(f'{y} - Good Friday', e-dt.timedelta(2), UK); add(f'{y} - Easter Monday', e+dt.timedelta(1), UK)
    add(f'{y} - Early May Bank Holiday', first_monday(y,5), UK)
    add(f'{y} - Spring Bank Holiday', last_monday(y,5), UK)
    add(f'{y} - Summer Bank Holiday', last_monday(y,8), UK)
    ny = dt.date(y,1,1)
    if ny.weekday() >= 5: add(f"{y} - New Year's Day (substitute)", ny+dt.timedelta(7-ny.weekday()), UK)
    xmas, boxing = dt.date(y,12,25), dt.date(y,12,26)
    if xmas.weekday() == 5:   add(f'{y} - Christmas Day (substitute)', dt.date(y,12,27), UK); add(f'{y} - Boxing Day (substitute)', dt.date(y,12,28), UK)
    elif xmas.weekday() == 6: add(f'{y} - Christmas Day (substitute)', dt.date(y,12,27), UK)
    elif boxing.weekday() == 5: add(f'{y} - Boxing Day (substitute)', dt.date(y,12,28), UK)

blocks = re.findall(r'    <holidays>\n.*?    </holidays>\n', s, re.S)
existing = {}
for b in blocks:
    existing.setdefault(re.search(r'<name>(.*?)</name>', b).group(1).replace('&apos;', "'"), []).append(b)
added, linked = 0, 0
for name, (date, bhs) in wanted.items():
    if name in existing:
        for b in existing[name]:
            if date is not None and f'<activityDate>{date}</activityDate>' not in b: continue
            have = set(re.findall(r'<businessHours>(.*?)</businessHours>', b))
            missing = sorted(bhs - have)
            if not missing: continue
            nb = b
            for bh in missing:
                ins = f'        <businessHours>{escape(bh)}</businessHours>\n'
                nb = re.sub(r'(    <holidays>\n(?:        <activityDate>.*?</activityDate>\n)?)', lambda m: m.group(1)+ins, nb, count=1)
            s = s.replace(b, nb); linked += 1
        continue
    links = ''.join(f'        <businessHours>{escape(bh)}</businessHours>\n' for bh in sorted(bhs))
    block = f'    <holidays>\n        <activityDate>{date}</activityDate>\n{links}        <isRecurring>false</isRecurring>\n        <name>{escape(name)}</name>\n    </holidays>\n'
    i = s.rfind('    </holidays>\n') + len('    </holidays>\n')
    s = s[:i] + block + s[i:]; added += 1
open(out, 'w', encoding='utf-8').write(s)
print(f'added {added} holidays, linked {linked} existing; wanted {len(wanted)}')
