Royalty Allocation Engine
Build an auditable Royalty Allocation Engine used by a music streaming backend to compute per-contributor royalty allocations for a reporting batch. The engine must convert stream events into full stream equivalents, aggregate per-track totals, apply contributor splits with priority semantics and normalization, perform deterministic rounding to integer cents, produce detailed provenance messages explaining every allocation decision, and support tenant-level overrides and idempotent batch processing with persistent results. The solution must be a single TypeScript file solution.ts that exports specific classes and functions described below.

Types

export type StreamEvent = {
  id: string;
  trackId: string;
  timestampISO: string;
  durationSeconds: number;
  streamType: 'partial' | 'full';
};

export type Split = {
  trackId: string;
  contributor: string;
  percentage: number;
  priority?: number;
};

export type Allocation = {
  contributor: string;
  amountCents: number;
  provenance: string[];
};

export type RoyaltyRequest = {
  streams: StreamEvent[];
  splits: Split[];
  centsPerFullStream: number;
  rounding: 'floor' | 'nearest';
  tenantId?: string | undefined;
};

export type RoyaltyResult = {
  allocations: Allocation[];
  warnings: string[];
  timestampISO: string;
};

High-level Responsibilities
Implement a pipeline that:
Validates and normalizes stream events.
Computes per-track Full Stream Equivalents (FSE).
Groups and validates splits by track and enforces exact error rules.
For each track, computes total cents to allocate: totalCents = totalFse * centsPerFullStream. Use floating math for intermediate values; final cents per contributor must be integer.

Apply splits using priority-first semantics:
Higher numeric priority values are served first.
Within a priority bucket, contributors share the bucket proportional to their percentage within that bucket.
If a split set sums to a value not equal to 100, normalize percentages proportionally and emit a warning SPLIT_MALFORMED:<trackId>.
If any split has a negative percentage, throw ERR_INVALID_SPLIT: track <trackId> contributor <contributor> negative percentage.
After priority buckets are allocated, any fractional leftover must be deterministically distributed to lower priorities and then finally rounded to integers with deterministic resolution of rounding remainders.

Produce per-track provenance messages detailing:
FSE calculation per stream.
Total FSE and total cents computed.
Split normalization and per-bucket float allocations.
Rounding decisions and any cents reassigned to satisfy integer total.
Aggregate allocations across all tracks to produce per-contributor totals and concatenate provenance in a deterministic order.

Error Strings and Warnings
The engine must use these exact error strings for tests to pass:
Throw on invalid streams:
ERR_INVALID_STREAM: stream <id> missing trackId or timestamp
Throw on invalid split negative percentage:
ERR_INVALID_SPLIT: track <trackId> contributor <contributor> negative percentage
Emit warnings do not throw as strings in RoyaltyResult.warnings:
SPLIT_MALFORMED:<trackId>
PRIORITY_OVERCLAIM:<trackId>
ERR_PERSIST_FAIL: key=<key>
All occurrences of <...> must be replaced with exact identifiers used.

Rules and Tie-breakers

Contributor ID order for deterministic decisions: lexicographic ascending.
When splitting rounding remainders among contributors, assign an extra cent to contributors in ascending contributor id order until the integer total equals totalCents.
When multiple contributors have equal priority and equal internal proportional share, treat them by lexicographic contributor id order for any deterministic tie-break.
When aggregating final allocations, sort contributions by contributor lexicographically ascending.
Provenance concatenation order for the final Allocation.provenance array:
All track-level provenance entries sorted by trackId ascending.
Within a track, provenance lines appear in this order:
TRACK_FSE:<trackId> TOTAL_FSE:<fse> TOTAL_CENTS:<totalCentsFloat> 
Per-stream lines in the original input order: STREAM:<streamId> FSE:<fse>
SPLIT_NORMALIZED:<trackId> SUM_PERCENT:<sumPct> if normalization occurred
Per-bucket float allocation lines in ascending numeric priority: BUCKET:<priority> CONTRIBUTOR:<contributor> FLOAT_CENTS:<floatCents>
Rounding lines: ROUND:<contributor> FROM:<floatCents> TO:<finalCents> METHOD:<roundingMethod>

After track-level lines, per-track rounding fix-up lines that explain which contributors received remainder cents.

All numeric values in provenance must be formatted as decimal numbers without thousands separators. Floating values may include decimal fraction digits. Exact string formatting must match sample provenance examples below.
Full Stream Equivalent (FSE) rules
For a stream event:
If streamType === 'full' then fse = 1.0.
If streamType === 'partial' then fse = min(1.0, durationSeconds / 30).
If a stream misses trackId or timestampISO or either is an empty string, throw exactly:
ERR_INVALID_STREAM: stream <id> missing trackId or timestamp
The per-track totalFse is the sum of its streams' fse values.
Per-track total cents computation
For a track: totalCentsFloat = totalFse * centsPerFullStream.
totalCentsTarget = round to nearest integer? No. Do not pre-round totalCentsFloat. Use totalCentsFloat to guide per-contributor float allocations. The final sum of integer cents across contributors must equal Math.round(totalCentsFloat) when rounding method is 'nearest', and must equal Math.floor(totalCentsFloat) when rounding method is 'floor'. The rounding parameter in RoyaltyRequest applies to final integer total for the track.

Split validation and normalization
Splits for a track are all Split entries with the matching trackId.
If no splits exist for a track, the track produces zero contributions but still emits provenance lines and causes no exception.
If any Split.percentage < 0, throw ERR_INVALID_SPLIT: track <trackId> contributor <contributor> negative percentage.
Compute sumPct = sum of percentages for the track. If sumPct !== 100, normalize each contributor's percentage as pctNormalized = (pct / sumPct) * 100 and append warning SPLIT_MALFORMED:<trackId>. Normalization must be deterministic and applied before priority bucketing.

Priority semantics:
Contributors with priority present are grouped per numeric priority value.
Higher numeric priority is higher precedence.
Process priority buckets in descending numeric order.
For each bucket, the bucket's target cents is totalCentsFloat * (sumPctOfBucket / 100).
Within the bucket, preliminary float cents for contributor = bucketTarget * (contributorPct / sumPctOfBucket).
If the sum of all bucket targets across priorities is greater than totalCentsFloat due to malformed percentages after normalization, emit PRIORITY_OVERCLAIM:<trackId> and proportionally scale bucketTargets down so their sum equals totalCentsFloat, preserving relative bucket weights, then recompute preliminary contributor floats deterministically.

Rounding and final integer allocation
After computing all preliminary float cents for contributors across all priorities and any remainder distribution:
For each contributor compute rounded integer according to rounding:
'floor': take Math.floor(floatCents).
'nearest': take Math.round(floatCents) (ties to nearest even are acceptable as JavaScript Math.round behavior).
Sum the integers; if the sum does not equal the integer target for the track Math.floor(totalCentsFloat) or Math.round(totalCentsFloat), assign remaining cents one by one to contributors with lexicographically smallest contributor id until sums match. If the sum exceeds the target due to rounding up, remove cents starting with lexicographically largest contributor id until sums match. Record each adjustment as a provenance line ROUND:<contributor> FROM:<floatCents> TO:<finalCents> METHOD:<roundingMethod>.

The final integer allocations for a track must sum exactly to the integer target and must be stable deterministic values given the same inputs.

Aggregation
After processing all tracks, aggregate integers per contributor across tracks by summing cents. For each contributor, build Allocation:
contributor: contributor id
amountCents: sum of integer cents across all tracks
provenance: an array concatenating track provenance lines for that contributor in the deterministic global ordering defined earlier.
The RoyaltyResult.allocations array must be sorted by contributor lexicographically ascending.

Provenance line exact formats
Per-track totals:
TRACK_FSE:<trackId> TOTAL_FSE:<fse> TOTAL_CENTS:<totalCentsFloat>
Per-stream:
STREAM:<streamId> FSE:<fse>
Split normalization:
SPLIT_NORMALIZED:<trackId> SUM_PERCENT:<sumPct>
Bucket float allocations:
BUCKET:<priority> CONTRIBUTOR:<contributor> FLOAT_CENTS:<floatCents>
Rounding:
ROUND:<contributor> FROM:<floatCents> TO:<finalCents> METHOD:<roundingMethod>

Numeric formatting in provenance must match the numeric values used in computation, with decimals printed in standard JavaScript decimal notation.

Required Exported Classes and Functions
Implement all the following classes in solution.ts with the exact public method signatures and semantics described. Tests will import these names directly.

StreamNormalizer
normalize(stream: StreamEvent): StreamEvent
normalizeBatch(streams: StreamEvent[]): StreamEvent[]
Enforces ERR_INVALID_STREAM: stream <id> missing trackId or timestamp when necessary.

SplitValidator
validate(splits: Split[]): void 
groupByTrack(splits: Split[]): Record<string, Split[]>

FseCalculator
computeFseTotals(streams: StreamEvent[]): { totals: Record<string, number>; details: Record<string, { streamId: string; fse: number }[]> }

Maintains stream input order for details.
PriorityBucketizer
bucketize(splits: Split[]): Map<number, Split[]> // return map with priorities as keys, contributors in each bucket sorted lexicographically

BucketAllocator
allocateBucket(bucketFloatTarget: number, bucketSplits: Split[]): { prelim: { contributor: string; floatCents: number }[]; provenance: string[] }

RemainderDistributor
distribute(leftoverFloat: number, remainingBuckets: Map<number, Split[]>, roundingMethod: 'floor'|'nearest'): { contributor: string; cents: number; provenance: string[] }[]

TrackAllocator
allocateTrack(trackId: string, totalCentsFloat: number, splits: Split[], roundingMethod: 'floor'|'nearest', streamDetails: { streamId: string; fse: number }[]): { perContributor: { contributor: string; floatCents: number; finalCents: number; provenance: string[] }[]; trackWarnings: string[] }

Must produce contributor-level floats, final integer cents, and provenance lines as specified. Must emit PRIORITY_OVERCLAIM:<trackId> or SPLIT_MALFORMED:<trackId> as needed.

RoundingAdjuster
finalizeRound(prelim: { contributor: string; floatCents: number }[], totalCentsTarget: number, roundingMethod: 'floor'|'nearest'): { contributor: string; cents: number; provenance: string[] }[]
Applies rounding and deterministic remainder fix-up.

Aggregator
aggregate(trackAllocations: { trackId: string; contributor: string; cents: number; provenance: string[] }[]): Allocation[]

Returns allocations sorted by contributor ascending.
TenantConfigManager
putOverrides(tenantId: string, overrides: Split[]): number // returns version number
getOverrides(tenantId: string): { version: number; overrides: Split[] }
invalidateTenantCache(tenantId: string): void

SplitResolver
resolveSplits(trackId: string, tenantId?: string): { splits: Split[]; provenance: string[] }
Behavior: if tenant override exists for trackId, it replaces global splits for that track. The resolver must include OVERRIDE_APPLIED:tenant=<tenantId> version=<v> or NO_OVERRIDE.

DeterministicCache<K, V>
get(key: K): V | undefined
put(key: K, value: V): void
delete(key: K): void
clear(): void

BatchIngestor
ingestBatch(streams: StreamEvent[], splits: Split[], metadata?: Record<string, unknown>): string
Produces canonical deterministic batchId string for semantically identical inputs.

CheckpointManager
isProcessed(batchId: string): boolean
markProcessed(batchId: string): void
clearAll(): void
listProcessed(): string[]

ResultCompressor
compress(result: RoyaltyResult): { key: string; payload: string } 

Persistor
persist(key: string, payload: string): void
fetch(key: string): string | undefined

BatchOrchestrator
processBatch(batchId: string, streams: StreamEvent[], splits: Split[], opts?: { rounding?: 'floor'|'nearest'; centsPerFullStream?: number; tenantId?: string }): RoyaltyResult
Implements idempotency: if a batch is marked processed and the persisted payload exists, return the persisted result. If persisted payload is missing, recompute and persist again. If persistor fails during persist, do not mark processed and throw ERR_PERSIST_FAIL: key=<key>.

Idempotency and Persistence Semantics

BatchIngestor.ingestBatch must canonicalize arrays and produce identical batchId for inputs that differ only by ordering or id casing.

BatchOrchestrator.processBatch must check CheckpointManager.isProcessed(batchId) and Persistor.fetch(key) to decide whether to re-run or return cached results.

The sequence on first processing must be: compute RoyaltyResult, compress, persist, then markProcessed. Tests will simulate persist failure; in that case do not call markProcessed and throw ERR_PERSIST_FAIL: key=<key>.

CheckpointManager.listProcessed() must return processed batch ids in deterministic ascending order.

Examples 

Below are three example scenarios with expected behaviors described in English. Tests will include concrete numeric expectations and provenance strings that reflect these behaviors.
Example 1: Single full stream, single split, nearest rounding
Streams: one full stream for track T1.
Splits: single contributor A 100% priority default 0.
centsPerFullStream = 100.
rounding = 'nearest'.
Expected:
totalFse = 1.0, totalCentsFloat = 100.
Contributor A receives 100 cents.
Provenance contains TRACK_FSE:T1 TOTAL_FSE:1 TOTAL_CENTS:100 and STREAM:<streamId> FSE:1 and BUCKET:0 CONTRIBUTOR:A FLOAT_CENTS:100 and ROUND:A FROM:100 TO:100 METHOD:nearest.

Example 2: Partial streams capped and normalization
Streams: two partial streams for T2 with durations 10 and 40 seconds. FSEs are 10/30 = 0.333333... and 1.0 (capped).

Splits: contributors A 60, B 30 (sum 90). This triggers SPLIT_MALFORMED:T2 and normalization to 66.666... and 33.333...
centsPerFullStream = 50, rounding = 'floor'.
Expected:
totalFse = 1.333333..., totalCentsFloat = 66.6666....
totalCentsTarget = Math.floor(66.666...) = 66.
Prelim floats and final integers computed accordingly; rounding remainder assigned deterministically to lexicographically smallest contributor if needed.

Example 3: Priority buckets and remainder distribution

Splits for T3: contributor P1 priority 2 percent 70, contributors P2 and P3 priority 1 percent 20 and 10.

If totalCentsFloat is 101.5 and rounding method is nearest resulting integer target 102, allocate to P1 first its bucket share, then lower priorities, and ensure integer sum equals 102 with deterministic tie-breakers for remainders.

Tests provided by grader will assert exact numeric cent values and exact provenance arrays matching the formatting rules above.

Constraints and Prohibitions

Single-file solution: solution.ts only.

Standard library only; no network, no file system persistence beyond in-memory Persistor interface provided to tests.

No randomness and no reliance on current system time.

Deterministic behavior given identical inputs.

All thrown error messages and warning strings must match exactly.

Testability and Grader Hooks

The grader will call exported classes and methods. To support testing the internal pipeline, tests will directly call FseCalculator.computeFseTotals, SplitValidator.groupByTrack, TrackAllocator.allocateTrack, RoundingAdjuster.finalizeRound, TenantConfigManager.putOverrides, SplitResolver.resolveSplits, BatchIngestor.ingestBatch, BatchOrchestrator.processBatch, CheckpointManager, Persistor, and ResultCompressor.compress. Ensure these APIs are implemented exactly.

Submission checklist for problem creator

Before publishing the problem, ensure:

The problem description is complete and unambiguous.

All exact error strings and provenance formats are present and spelled exactly as above.

The exported class and method signatures in solution.ts match the names and signatures described.

Tests do not rely on network or real time.

The Base Code (to be provided alongside this description) includes minimal stub implementations for the persistence and cache components with clear behavior the solver can use or replace.

Example behaviors are consistent with deterministic tie-breakers and rounding semantics.You will build an auditable, deterministic Royalty Allocation Engine used by a music streaming backend. The engine processes a reporting batch of stream events and contributor splits and produces per-contributor royalty allocations (integer cents) with detailed provenance explaining every allocation decision. The engine must also support tenant-level split overrides, deterministic batch idempotency, and persistent result storage semantics exposed via provided interfaces. Everything must be deterministic: no randomness, no wall-clock dependence, and no external network calls.

Types (use these shapes exactly)

Include these types in your implementation or mirror them exactly:

export type StreamEvent = {
  id: string;
  trackId: string;
  timestampISO: string;
  durationSeconds: number;
  streamType: 'partial' | 'full';
};

export type Split = {
  trackId: string;
  contributor: string;
  percentage: number;
  priority?: number;
};

export type Allocation = {
  contributor: string;
  amountCents: number;
  provenance: string[];
};

export type RoyaltyRequest = {
  streams: StreamEvent[];
  splits: Split[];
  centsPerFullStream: number;
  rounding: 'floor' | 'nearest';
  tenantId?: string | undefined;
};

export type RoyaltyResult = {
  allocations: Allocation[];
  warnings: string[];
  timestampISO: string;
};

Overall pipeline responsibilities (step-by-step)

Implement a deterministic pipeline that, for a given batch, does the following in order:

Validate and normalize stream events.

Compute per-track Full Stream Equivalents (FSE) for each stream and aggregate per-track totals.

Group splits by track and validate them.

For each track compute totalCentsFloat = totalFse * centsPerFullStream.

Apply contributor splits using priority-first semantics and proportional bucket sharing.

If split percentages do not sum to exactly 100, normalize them and emit a warning.

Detect and handle priority bucket overclaiming by proportionally scaling bucket targets and emitting a warning.

Compute preliminary float allocations per contributor, then deterministically round to integer cents so that the final sum equals the required track integer target (depending on rounding mode).

Produce detailed provenance lines for every track and contributor, using exact formatting specified below.

Aggregate integer cents per contributor across all tracks and return RoyaltyResult with sorted allocations and any warnings collected.

Support tenant split overrides and idempotent batch processing with persistent storage semantics described later.

Tests will validate both low-level helpers (e.g., FSE and split grouping) and the end-to-end orchestrator.

Exact error strings and warnings (must match tests)

These exact strings are required by the tests. Replace <...> with the actual identifiers.

Throw on invalid streams:

ERR_INVALID_STREAM: stream <id> missing trackId or timestamp

Throw on invalid negative split percentage:

ERR_INVALID_SPLIT: track <trackId> contributor <contributor> negative percentage

Emit these warnings (do not throw): include them in RoyaltyResult.warnings

SPLIT_MALFORMED:<trackId>

PRIORITY_OVERCLAIM:<trackId>

ERR_PERSIST_FAIL: key=<key>

Determinism and tie-breakers (unambiguous rules)

Follow these deterministic rules in every decision point:

Contributor ordering for deterministic choices: lexicographic ascending (Unicode codepoint order).

When assigning remaining cents after rounding, give extra cents one by one to contributors in ascending contributor id order until sums match.

When removing excess cents, remove starting with the lexicographically largest contributor id.

Within a priority bucket, contributors split the bucket proportionally by their (possibly normalized) percentages.

Final RoyaltyResult.allocations must be sorted by contributor lexicographically ascending.

Provenance concatenation follows the exact ordering rules in the Provenance section below.

Full Stream Equivalent (FSE) rules (exact math)

For a stream:

When streamType === 'full', fse = 1.0.

When streamType === 'partial', fse = min(1.0, durationSeconds / 30).

If a stream has missing trackId or missing timestampISO or either is an empty string, throw exactly:

ERR_INVALID_STREAM: stream <id> missing trackId or timestamp

Per-track totalFse is the sum of the stream fse values for that track. Preserve stream input order for any per-stream provenance.

Per-track total cents semantics (how final integer target is determined)

Compute totalCentsFloat = totalFse * centsPerFullStream.

Do not pre-round totalCentsFloat when computing preliminary float allocations.

The integer target for the track equals:

Math.round(totalCentsFloat) when rounding === 'nearest'.

Math.floor(totalCentsFloat) when rounding === 'floor'.

The final integer allocations across contributors for that track must sum exactly to that integer target.

Split validation and normalization (exact behavior)

A track's splits are all Split entries where trackId matches.

When a track has no splits, it produces zero contributions but still emits provenance lines.

If any Split.percentage < 0 for a track, throw exactly:

ERR_INVALID_SPLIT: track <trackId> contributor <contributor> negative percentage

Compute sumPct as the exact arithmetic sum of percentages for the track. When sumPct !== 100 (exact inequality), normalize each contributor's percentage:

pctNormalized = (pct / sumPct) * 100

Append SPLIT_MALFORMED:<trackId> to RoyaltyResult.warnings

Normalization must happen before priority bucketing and must be deterministic.

Priority semantics and bucket allocation (precise)

Group contributors by numeric priority value. Missing priority is treated the same as priority 0.

Higher numeric priority means higher precedence. Process buckets in descending numeric order.

Let sumPctOfBucket be the sum of (normalized) percentages of contributors in that bucket.

The bucket's target float cents = totalCentsFloat * (sumPctOfBucket / 100).

Within the bucket, each contributor's preliminary float cents = bucketTarget * (contributorPct / sumPctOfBucket).

If the sum of all bucket targets exceeds totalCentsFloat (this can happen after normalization), append PRIORITY_OVERCLAIM:<trackId> to warnings and proportionally scale bucket targets down so their sum equals totalCentsFloat. Preserve bucket relative weights and recompute contributor floats deterministically.

Rounding to integers and remainder fix-up (deterministic)

After all preliminary floats are computed for every contributor in the track:

For 'floor' use Math.floor(floatCents) per contributor as the initial integer.

For 'nearest' use Math.round(floatCents) per contributor as the initial integer.

Sum the integers. Compare to the track integer target (see Per-track total cents).

If the sum is less than the target, give one extra cent at a time to contributors with lexicographically smallest contributor id until sums match.

If the sum is greater than the target, remove cents starting with the lexicographically largest contributor id until sums match.

For every contributor whose integer changed relative to their direct rounding, append a provenance line:

ROUND:<contributor> FROM:<floatCents> TO:<finalCents> METHOD:<roundingMethod>

The final per-track integer allocations must be stable and deterministic.

Provenance: exact line formats and ordering

Provenance lines are strings in a strict format. Numeric values must use standard JavaScript decimal notation (no thousands separators). Within each contributor's Allocation.provenance the provenance lines must be concatenated in the global deterministic order described below.

Per-track provenance lines and their exact formats:

Track totals:

TRACK_FSE:<trackId> TOTAL_FSE:<fse> TOTAL_CENTS:<totalCentsFloat>

Per-stream (preserve input stream order):

STREAM:<streamId> FSE:<fse>

Split normalization (present only if normalization occurred):

SPLIT_NORMALIZED:<trackId> SUM_PERCENT:<sumPct>

Per-bucket float allocations in ascending numeric priority (for each contributor in the bucket):

BUCKET:<priority> CONTRIBUTOR:<contributor> FLOAT_CENTS:<floatCents>

Rounding adjustments:

ROUND:<contributor> FROM:<floatCents> TO:<finalCents> METHOD:<roundingMethod>

Global concatenation order for a contributor's Allocation.provenance:

All track-level provenance entries sorted by trackId ascending.

Within a single track, lines must appear in this order:

TRACK_FSE line,

all STREAM lines (original input order),

optional SPLIT_NORMALIZED line,

bucket BUCKET lines in ascending priority,

ROUND lines,

any per-track rounding fix-up lines.

When assembling a contributor's provenance across tracks, follow trackId ascending.

Tests will compare provenance arrays exactly, so adhere to these rules precisely.

Required exported classes and method signatures (implement these exactly)

Your solution.ts must export the following classes and methods with the exact signatures and semantics described earlier. Tests will import these names directly.

StreamNormalizer

normalize(stream: StreamEvent): StreamEvent

normalizeBatch(streams: StreamEvent[]): StreamEvent[]

SplitValidator

validate(splits: Split[]): void

groupByTrack(splits: Split[]): Record<string, Split[]>

FseCalculator

computeFseTotals(streams: StreamEvent[]): { totals: Record<string, number>; details: Record<string, { streamId: string; fse: number }[]> }

PriorityBucketizer

bucketize(splits: Split[]): Map<number, Split[]>

BucketAllocator

allocateBucket(bucketFloatTarget: number, bucketSplits: Split[]): { prelim: { contributor: string; floatCents: number }[]; provenance: string[] }

RemainderDistributor

distribute(leftoverFloat: number, remainingBuckets: Map<number, Split[]>, roundingMethod: 'floor'|'nearest'): { contributor: string; cents: number; provenance: string[] }[]

TrackAllocator

allocateTrack(trackId: string, totalCentsFloat: number, splits: Split[], roundingMethod: 'floor'|'nearest', streamDetails: { streamId: string; fse: number }[]): { perContributor: { contributor: string; floatCents: number; finalCents: number; provenance: string[] }[]; trackWarnings: string[] }

RoundingAdjuster

finalizeRound(prelim: { contributor: string; floatCents: number }[], totalCentsTarget: number, roundingMethod: 'floor'|'nearest'): { contributor: string; cents: number; provenance: string[] }[]

Aggregator

aggregate(trackAllocations: { trackId: string; contributor: string; cents: number; provenance: string[] }[]): Allocation[]

TenantConfigManager

putOverrides(tenantId: string, overrides: Split[]): number

getOverrides(tenantId: string): { version: number; overrides: Split[] }

invalidateTenantCache(tenantId: string): void

SplitResolver

resolveSplits(trackId: string, tenantId?: string): { splits: Split[]; provenance: string[] }

DeterministicCache<K, V>

get(key: K): V | undefined

put(key: K, value: V): void

delete(key: K): void

clear(): void

BatchIngestor

ingestBatch(streams: StreamEvent[], splits: Split[], metadata?: Record<string, unknown>): string

CheckpointManager

isProcessed(batchId: string): boolean

markProcessed(batchId: string): void

clearAll(): void

listProcessed(): string[]

ResultCompressor

compress(result: RoyaltyResult): { key: string; payload: string }

Persistor

persist(key: string, payload: string): void

fetch(key: string): string | undefined

BatchOrchestrator

processBatch(batchId: string, streams: StreamEvent[], splits: Split[], opts?: { rounding?: 'floor'|'nearest'; centsPerFullStream?: number; tenantId?: string }): RoyaltyResult

Make sure method names and argument lists match exactly.

Idempotency and persistence semantics (exact transaction order)

BatchIngestor.ingestBatch must canonicalize inputs (arrays and casing) and return the same batch id for semantically identical inputs in different orders or with different id casing.

BatchOrchestrator.processBatch must:

Check CheckpointManager.isProcessed(batchId) and Persistor.fetch(key). If already processed and persisted payload exists, return the persisted result.

Otherwise compute RoyaltyResult, call ResultCompressor.compress, then Persistor.persist, then CheckpointManager.markProcessed.

When Persistor.persist throws, do not call markProcessed and throw exactly ERR_PERSIST_FAIL: key=<key>.

CheckpointManager.listProcessed() must return processed batch ids in deterministic ascending order.

Examples (human-readable expectations)

Example 1: One full stream for T1, one contributor A at 100%, centsPerFullStream = 100, rounding 'nearest'. Expect A gets 100 cents and provenance includes:

TRACK_FSE:T1 TOTAL_FSE:1 TOTAL_CENTS:100

STREAM:<streamId> FSE:1

BUCKET:0 CONTRIBUTOR:A FLOAT_CENTS:100

ROUND:A FROM:100 TO:100 METHOD:nearest

Example 2: Two partial streams for T2 with durations 10 and 40 seconds -> FSEs 0.333333... and 1.0 summed to 1.333333.... Splits A:60, B:30 (sum 90) triggers SPLIT_MALFORMED:T2. With centsPerFullStream = 50 and rounding = 'floor' expect total cents target Math.floor(1.3333... * 50) = 66. Prelim floats and integer rounding follow normalization and deterministic remainder assignment.

Example 3: Priority buckets on T3: P1 priority 2 pct 70, P2 priority 1 pct 20, P3 priority 1 pct 10. With totalCentsFloat 101.5 and rounding 'nearest' integer target 102, allocate P1 bucket first then lower buckets, and ensure integer sum 102 with deterministic tie-breakers.

Tests will assert exact numbers and exact provenance strings.