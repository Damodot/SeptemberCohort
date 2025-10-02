Live Music Event Conflict Auditor
You need to build an engine that can review a collection of live music events, apply a set of policy rules, and produce a structured audit report. The program must export a function named generateEventAuditReport. The output should always be reproducible: the same inputs must always lead to the same report.

Inputs
eventsInput; an array of live event objects. Every event must have an id (string). Other optional properties include:
artistName, venueName, startTime, endTime, capacity, actualAttendance, genre, city, country, ticketPriceUSD, artistAliases, isFestival, promoter.
contextInput; an object describing the current evaluation context.
currentTime (ISO 8601 string, required).
rules (an array of rule objects).
defaultCapacityThreshold (optional number between 0 and 1, default 0.85).
canonicalArtistMapping (optional mapping of artist names to canonical names).
treatMissingActualAttendanceAsZeroForCapacityShortfall?: boolean, default true. When true a selected event with a capacity but missing actualAttendance is treated as having attendanceRatio = 0.0 for the purpose of capacity-shortfall calculations. When false, capacity shortfall is computed only for events that have both capacity and actualAttendance.


Rules
id (string)
priority (number)
constraints (optional object)
targetItemCount (may also appear under constraints; rule-level value takes precedence)

Constraints can define:
banned genres, required cities, banned countries
minimum and maximum capacities
allowed promoters
required or banned artists (after canonical mapping)
minimum and maximum ticket prices
If a rule specifies targetItemCount both at the top level and inside constraints, the top level takes precedence. If neither exists, default is zero.

Hard filtering
Events that do not satisfy all hard constraints are removed before scoring. Required checks are applied with canonicalized artist names when relevant.

Soft checks
These are not used to filter, but they affect scoring and drift calculations:
minAttendanceRatio (0 to 1)
maxEventDurationHours (default 6 if not provided)
disallowedGenres
preferredCities
venueDiversityWindow (non-negative integer, default 0)

Event calculations
Duration (hours): (Date.parse(end) - Date.parse(start)) / 3_600_000. If start or end is missing or invalid, duration is undefined.
Attendance ratio: actualAttendance / capacity if both exist, otherwise 0.0.
Conflict check: two events overlap if startA < endB and startB < endA. Only valid if both have parseable times.

Scoring and ordering
Each filtered event gets:
conflictPenalty = 1.0 if it conflicts with any other survivor, else 0.0.
attendanceScore = min(1, actualAttendance / capacity) if both exist, else 0.0.
durationScore = max(0, 1 - durationHours / maxEventDurationHours). If duration is not defined, set 0.0.
combinedScore = 0.4*attendanceScore + 0.4*durationScore + 0.2*(1 - conflictPenalty).

Events are sorted by:
combinedScore (descending)
attendanceScore (descending)
durationScore (descending)
startTime (descending; undefined counts as oldest)
id (ascending)

Selection process
Use greedy selection:

Take the best-scored survivor first, then continue until reaching targetItemCount or no eligible survivors remain.

Apply the venue diversity rule: an event is ineligible at position p if its venue matches any of the last D selected events, where D is venueDiversityWindow.

Skipped events are reconsidered at the next step. Already chosen events are never replaced.

Drift score

The drift score for a rule is the sum of:
Attendance shortfall: if minAttendanceRatio is given and selection is nonempty, add max(0, minRatio - averageRatio).
Duration penalty: for each selected event longer than maxEventDurationHours, add the excess hours.
Capacity shortfall: Let defaultCapacityThreshold = context.defaultCapacityThreshold, if null then 0.85. Let flag = context.treatMissingActualAttendanceAsZeroForCapacityShortfall or true. For each selected event where capacity exists:
If flag is equals true: treat missing actualAttendance as attendanceRatio = 0.0; compute and add max(0, defaultCapacityThreshold - attendanceRatio).
If flag is equals false: compute capacity shortfall only when both capacity and actualAttendance exist; otherwise skip this event.
Preferred cities: if a preferred city exists in the initial pool but none of the selected events are from that city, add 1. If a preferred city is completely absent from the pool, report it as unsatisfiable instead of penalizing.
Disallowed genres: add 1 for each selected event whose genre is disallowed.
Conflicts: add conflictPenalty for each selected event.

Constraint violations
Before filtering, check the initial pool and record unsatisfiable constraints in this order:
missing required cities
missing required artists (after canonicalization)
missing allowed promoters
capacity range unsatisfied
missing preferred cities
Use the exact string forms:
Unsatisfiable constraint: requiredCity: X
Unsatisfiable constraint: requiredArtist: Y
Unsatisfiable constraint: allowedPromoter: Z
Unsatisfiable constraint: capacityRange
Unsatisfiable constraint: preferredCity: T

Time conflicts
For each conflicting pair in the filtered set, record TimeConflict: idA,idB where idA < idB. Each pair appears once. Sort the list in the right order.
Use the exact string format "TimeConflict: idA,idB"; note the single space after the colon. Tests must expect that literal formatting.

Output
Return a CurateReport with one CandidateReport per rule. Fields, in order:
ruleId
itemCount
items (array of ids in selection order)
averageAttendanceRatio
averageDurationHours
durationPenalty
driftScore
diversitySatisfied; Set to true if and only if either targetItemCount is equal to 0 or the selection reached selected.length is equal to targetItemCount. In other words, diversitySatisfied is true when the engine filled the requested number of items.
constraintViolations (array of strings)
timeConflicts (array of strings)
Finally, sort the reports by rule priority (descending), then by rule id (ascending).

Validation rules
If eventsInput is not an array, or any event lacks a string id, throw Error("Invalid event data").
If context.currentTime is invalid for Date.parse, throw Error("Invalid context.currentTime").
If rules is missing or empty, return an empty candidates array.