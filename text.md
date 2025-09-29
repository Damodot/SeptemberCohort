Wallet Transaction Reconciler with Multi-Chain Support
You must implement a reconciler that merges paginated transaction history responses from multiple blockchain explorers into a single deduplicated, time-ordered ledger for a single wallet address. The reconciler must handle differences between chains, missing or approximate timestamps, duplicates across pages and chains, conflicting amounts, and corrupted explorer responses. The same inputs must always produce identical output; when caching conditions are met the same object references must be returned. The function must fail fast on clearly invalid explorer data (see validation rules) and must produce well-typed structured output with conflict details and a compact error taxonomy.

Function signature
export function reconcileLedger(wallet: string, explorerPages: ExplorerPage[], options?: Options): LedgerResult

Input types
type ExplorerPage:
{
  explorerId: string
  chain: "ethereum" | "bitcoin" | "solana"
  pageIndex: number
  pageSize: number
  transactions: RawTx[]
}

type RawTx:
{
  hash: string
  amount: string
  timestamp?: number | null
  blockHeight?: number | null
}

type Options:
{
  sourcePriority?: string[]
}

Detailed input rules and validation
wallet must be a non-empty string. If invalid, throw Error with exact message "InvalidInput: wallet must be non-empty string".
explorerPages must be a non-empty array. If invalid, throw Error with exact message "InvalidInput: explorerPages must be non-empty array".
Each ExplorerPage must have:
a non-empty explorerId string,
a chain that is one of the accepted values ("ethereum" | "bitcoin" | "solana"),
a non-negative integer pageIndex,
a non-negative integer pageSize,
and transactions which must be an array.

Validation errors are fail-fast where specified below and throw exact error messages.
For a given explorerId, pageIndex values must be unique. If a duplicate pageIndex is present for the same explorerId, throw Error with exact message DataCorruption: duplicate pageIndex <pageIndex> for explorer <explorerId> (replace <pageIndex> and <explorerId> exactly as shown in examples/tests).
For a given explorerId, when concatenating its pages in ascending pageIndex order, if two transactions have blockHeight present and a later transaction has a blockHeight lower than an earlier one, treat this as non-monotonic block heights and fail-fast by throwing Error with exact message InvalidExplorerData: non-monotonic block heights for explorer <explorerId> (replace <explorerId> exactly).

Transactions may have missing timestamp and missing blockHeight. Both may be missing. amount is always provided in valid inputs as a string. hash is required and is treated case-insensitively for deduplication.

Explorer responses may include repeated transactions within the same page and across pages. Treat repeated hashes as duplicates and deduplicate.
Add explicit chain validation: if chain is not one of "ethereum", "bitcoin", "solana", throw Error with exact message "InternalError: invalid chain".

Exact InternalError messages required 

Empty or missing explorerId -> throw "InternalError: invalid explorerId"
Invalid pageIndex (non-integer or negative) -> throw "InternalError: invalid pageIndex"
Invalid pageSize (non-integer or negative) -> throw "InternalError: invalid pageSize"
transactions not an array -> throw "InternalError: transactions must be array"
invalid chain value -> throw "InternalError: invalid chain"
invalid transaction hash -> throw "InternalError: invalid transaction hash"
invalid timestamp -> throw "InternalError: invalid timestamp"
invalid blockHeight -> throw "InternalError: invalid blockHeight"

Rules for reconciliation
Deduplication key: case-insensitive transaction hash. Lowercased hash is the canonical id.
If the same hash appears from multiple explorers, treat these as the same transaction and produce a single ledger entry.
Conflict detection: if the same hash appears with differing amount strings from different sources, that transaction is a conflict. The reconciler must not throw for conflicts. It must include conflict details in LedgerResult.conflicts and set the corresponding LedgerEntry.conflict = true. The conflict field is required and must be a boolean for every LedgerEntry; non-conflict entries must have conflict: false explicitly.


Conflict resolution rules
If options.sourcePriority is provided, choose the amount (and the resolved source) from the earliest explorerId in sourcePriority that contributed that hash. The ConflictDetail.resolutionRule for this case must be the exact string:
"priority: <explorerId> first" (replace <explorerId> with the chosen explorer id).
If options.sourcePriority is not provided, resolve using these steps:
If any source provides a timestamp, choose the source with the latest timestamp.
If multiple sources share the same (latest) timestamp, break that tie by choosing the source with the highest numeric blockHeight among those tied.
If timestamps are equal and blockHeights are equal (or if no blockHeights are present to break a tie), choose the source whose explorerId is lexicographically first.
If no timestamps are provided by any source but one or more blockHeights are present, choose the source with the highest numeric blockHeight; if multiple share the same blockHeight, choose the lexicographically first explorerId.

The ConflictDetail.resolutionRule must use one of these exact strings for the non-priority cases:
"latest timestamp"
"highest blockHeight"
"explorerId lexicographic"
The chosen string must reflect the actual rule that decided the resolution

if timestamps tied and you used blockHeight to pick, the rule must be "highest blockHeight".
The ledger entry must record resolvedBy (the explorerId chosen by the resolution rules).
If a transaction appears on multiple chains, the chain for the LedgerEntry must be the chain of the source explorer designated in resolvedBy.
The sources array (in both LedgerEntry and ConflictDetail) must list explorerIds in the same relative order as their corresponding ExplorerPage objects appear in the input explorerPages array (processing order). sources must include every explorer that reported that hash (no duplicates).

Ordering rules for final ledger
The ledger must be sorted by recency descending.
Transactions are compared using the following priority and numeric ordering:
Presence of time information (highest priority): entries that have any timestamp are considered more recent than entries that only have a blockHeight, regardless of numeric values. In other words: timestamp > blockHeight > neither.

Within the same priority group:
If using timestamp, use the numeric timestamp value (higher = more recent). For tie on timestamp, break by the next applicable rule (see below).
If using blockHeight (only; no timestamps across contributors), use the numeric blockHeight (higher = more recent).
If neither timestamp nor blockHeight is available, order by hash lexicographically ascending.
For exact ties on the chosen numeric key (timestamp or blockHeight), tie-break by hash lexicographic ascending.

To compute each entry's ordering keys:
If any contributing source provided a timestamp, define effectiveTimestamp = maximum timestamp across contributors who provided timestamps. Use effectiveTimestamp as that entry's numeric key.
Else if any contributing source provided a blockHeight, define effectiveBlockHeight = maximum blockHeight across contributors who provided blockHeights. Use that as the entry's numeric key.
Else the entry has no numeric key and is ordered by hash lexicographic ascending.
These rules guarantee deterministic ordering even when timestamps are missing or approximate.

Output types and fields
When building a LedgerEntry for a hash reported by multiple explorers, the chain value in the LedgerEntry must be set to the chain of the explorer identified by resolvedBy.

LedgerResult:
{
  wallet: string
  entries: LedgerEntry[]
  conflicts: ConflictDetail[]
  meta: {
    cached: boolean
    sourcesAnalyzed: number
    errors: string[]
  }
}

meta.sourcesAnalyzed is defined as the total number of ExplorerPage objects processed (i.e., explorerPages.length), not the number of unique explorerIds.

meta.errors collects non-fatal warnings or recoverable parse/merge notes (it is not used for the fail-fast validation errors listed above). Implementations used by hidden tests should return an empty array [] in normal operation; hidden tests expect meta.errors to be []. Use meta.errors only for non-fatal diagnostics if you choose to populate it.
LedgerEntry:
{
  chain: "ethereum" | "bitcoin" | "solana"
  hash: string
  amount: string | null
  timestamp?: number | null
  blockHeight?: number | null
  sources: string[]
  conflict: boolean
  resolvedBy: string
}
chain is the chain of the resolvedBy source.
hash is lowercased canonical id.
amount is the resolved amount string. The type allows null only to cover the theoretical case where no source provided an amount; valid inputs always supply amounts and tests expect a string in practice.
timestamp is the effectiveTimestamp (maximum across contributors) or null.
blockHeight is the effectiveBlockHeight (maximum across contributors) or null.
sources lists contributing explorerIds in input order (processing order).
resolvedBy is the explorerId chosen by the resolution rules.
Implementations must set conflict to true for conflicted entries and false otherwise; tests may assert false explicitly.


ConflictDetail:
{
  hash: string
  differingAmounts: string[]
  chosenAmount: string | null
  sources: string[]
  resolutionRule: string
}

resolutionRule must be one of the exact strings listed earlier ("priority: <explorerId> first", "latest timestamp", "highest blockHeight", "explorerId lexicographic").
Error messages
"InvalidInput: wallet must be non-empty string"
"InvalidInput: explorerPages must be non-empty array"
"DataCorruption: duplicate pageIndex <pageIndex> for explorer <explorerId>" (use exact formatting expected by tests)
"InvalidExplorerData: non-monotonic block heights for explorer <explorerId>"
For internal validation failures, use the exact InternalError strings listed above (e.g., "InternalError: invalid explorerId", "InternalError: invalid chain", etc.).

Caching
Caching and object identity: On a cache hit the function must return the *exact same* LedgerResult object reference (strict === equality) that was previously returned for identical inputs (same wallet, same explorerPages, same options). The first time a result is computed, meta.cached must be false. On subsequent calls with identical inputs implementations may (and tests expect) return the cached object and set its meta.cached to true before returning it. Apart from toggling meta.cached, the cached object must not be mutated: entries, conflicts, wallet, other meta fields, and any nested objects/arrays must remain strictly identical to the original object previously returned. Tests will assert strict object identity and that meta.cached becomes true on a cache hit.

Examples
Example 1: Simple merge and dedupe
Input: wallet "W1", two ExplorerPage objects:

explorerId: "E1", chain: "ethereum", pageIndex: 0, transactions [{ hash: "0xA", amount: "10", timestamp: 1000 }]

explorerId: "E2", chain: "bitcoin", pageIndex: 0, transactions [{ hash: "0xA", amount: "10", blockHeight: 100 }]
Expected: entries.length === 1 with:

hash: "0xa"

amount: "10"

timestamp: 1000

blockHeight: 100

sources: ["E1","E2"] (input order)

resolvedBy: "E1"

chain: "ethereum" (chain of resolvedBy)

meta.cached === false for first call

Example 2: BlockHeight ordering
Input: two bitcoin transactions with blockHeights 200 and 100 and no timestamps.
Expected ordering: blockHeight 200 before 100. If blockHeights are non-monotonic within the same explorer across pages, throw InvalidExplorerData.

Example 3: Priority conflict resolution
Input: hash "X" appears in E1 amount "5", E2 amount "6". options.sourcePriority = ["E2","E1"]
Expected:

chosenAmount === "6"

conflict === true

resolutionRule === "priority: E2 first"