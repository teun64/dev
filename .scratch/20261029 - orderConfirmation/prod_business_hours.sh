#!/bin/bash
# Creates the shipping Business Hours in prod (Mon-Fri 08:30-17:30 local, weekend closed). Run once.
for spec in "Shipping (NL)|Europe/Amsterdam" "Shipping (UK)|Europe/London" "Shipping (GR)|Europe/Athens"; do
  IFS='|' read n tz <<< "$spec"
  V="Name='$n' TimeZoneSidKey=$tz IsActive=true"
  for d in Monday Tuesday Wednesday Thursday Friday; do V="$V ${d}StartTime=08:30:00.000Z ${d}EndTime=17:30:00.000Z"; done
  sf data create record -o prod -s BusinessHours -v "$V"
done
