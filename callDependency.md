Cross-Contract Call Dependency Resolver
Given a static list of contract calls, compute a safe execution plan that respects read/write dependencies, reports conflicts, and detects cycles. The solver must produce exactly specified outputs for all inputs. The problem stresses modular design: implement parsing, graph construction, cycle detection, conflict reporting, topological sorting, and plan generation. The goal is to build an engine that analyzes on-chain call patterns to determine safe batched execution orders and to identify problematic dependency patterns. Write a function planExecutionOrder that accepts an array of contract calls and returns a plan describing an execution ordering and any conflicts found. The resolver must:
Build a dependency graph where edges represent read-after-write, write-after-read, and write-after-write dependencies on storage keys.
Detect cycles. If the graph contains any cycle involving concrete storage keys, return an error code ERR_CYCLE_DETECTED and include the minimal cycle(s) discovered (list of call ids forming cycles) in the output. The presence of a cycle prevents producing a safe execution order.
Detect unknown dependencies: a call reads or writes a storage key that another call references indirectly via a wildcard or unknown mapping that cannot be resolved. If any read or write references the special wildcard string "*" in any call's reads or writes, treat this as an unknown dependency and return ERR_UNKNOWN_DEPENDENCY unless conservative locking resolves it as described below.
Produce an execution plan under two deterministic strategies: conservative locking and optimistic hints. Conservative locking serializes calls that share any write access to the same storage key. Optimistic hints allow parallelization only when safe by analyzing pairwise non-conflicting accesses and transitive dependencies. The function must expose which strategy produced the plan. The default plan returned by planExecutionOrder must be the conservative locking plan.
Report conflicts where multiple calls write the same key without a strict ordering derived from dependencies.

Types and Signatures
export type ContractCall = {
id: string;
contract: string;
reads: string[];
writes: string[];
};

export type Conflict = {
type: "WRITE_WRITE" | "WRITE_READ" | "UNKNOWN";
key: string;
calls: string[];
};

export type PlanResult = {
order: string[] | null;
strategy: "CONSERVATIVE" | "OPTIMISTIC";
conflicts: Conflict[];
errors: string[];
cycles: string[][];
};

export function planExecutionOrder(calls: ContractCall[],strategy:"CONSERVATIVE" | "OPTIMISTIC" = "CONSERVATIVE"): PlanResult;

order is null if a cycle prevents a valid ordering or an unrecoverable unknown dependency prevents planning.
conflicts is an array of Conflict objects describing key-level conflicts discovered during planning.
errors contains zero or more exact error codes described below.
cycles contains one or more minimal cycles (each cycle is an array of call ids in order). If errors contains ERR_CYCLE_DETECTED, cycles must be non-empty.

Error Codes and Messages
All code must use the exact strings below where appropriate and include them in the errors array of the result. The function must not throw these strings; instead it should include them in the return object.
ERR_CYCLE_DETECTED - placed in errors when any cycle is found.
ERR_UNKNOWN_DEPENDENCY - placed in errors when any call contains the wildcard key "*" in either reads or writes that cannot be safely resolved.

Dependency Semantics
Given two calls A and B:
If A writes key K and B reads key K, then B depends on A and A must come before B.
If A reads key K and B writes key K, then A depends on B and B must come before A.
If A writes key K and B writes key K, then there is a write-write conflict. The graph must contain edges to serialize them if read/write edges or other constraints imply an order; otherwise this is a reported conflict and in conservative strategy the calls must be serialized by ascending call id.
Wildcard "*" means unknown keys: any call containing "*" in reads or writes is treated as touching unknown keys that may conflict with any other call. Conservative strategy serializes any call with "*" next to any other call that reads or writes any key. Optimistic strategy reports ERR_UNKNOWN_DEPENDENCY in errors and sets order to null if any wildcard is present and cannot be resolved to non-conflicting sets by static analysis.

Plan Strategies
CONSERVATIVE strategy:
Build dependency edges for read-after-write and write-after-read as specified.
For write-write pairs without a derived ordering, impose a deterministic ordering by call id ascending and include a WRITE_WRITE Conflict object for that key listing the involved calls in ascending id order.
For any call W containing a wildcard and any other call C, add dependency edges W -> C and C -> W to enforce serialization.

After adding these deterministic edges, run a topological sort. If a cycle exists after these edges, return errors including ERR_CYCLE_DETECTED and include cycles. Otherwise, return the ordering and conflicts and strategy: "CONSERVATIVE".

OPTIMISTIC strategy:
Build only edges that are strictly implied by concrete read/write pairs. Do not add serialization edges for write-write pairs unless a read/write edge implies one.
If any wildcard "*" is present in any call, set errors to include ERR_UNKNOWN_DEPENDENCY and set order to null and strategy to "OPTIMISTIC".
If no wildcard and graph is acyclic, perform a topological sort. When multiple nodes have no incoming edges, prefer nodes with smaller call id first.
Collect conflicts: write-write sets that are not ordered by the graph are reported as WRITE_WRITE conflicts but are not automatically serialized. If cycles are detected, include ERR_CYCLE_DETECTED and set order to null.

Output
For all arrays (order, conflicts, errors, cycles) the ordering must be deterministic. When multiple valid orderings exist, pick the one that is lexicographically smallest by comparing the sequence of call ids.
When reporting calls inside a Conflict.calls array, sort call ids ascending.
When listing cycles, each cycle must start with the smallest call id in the cycle and list the cycle in call-order following edges; for multiple cycles sort by the first element.
The conflicts array must be sorted lexicographically by the key property of each conflict.

Helpers / Modules

Design but do not export these exact helper behaviors in separate files; the solution must be a single file but it should conceptually include the following modules. Tests will not import these but rely on the final planExecutionOrder function behavior.
CallParser: validates input shapes and normalizes keys.
DependencyGraph: constructs a directed multigraph capturing dependencies.
CycleDetector: finds all minimal cycles.
TopologicalSorter: returns deterministic topological ordering or indicates cycles.
ConflictReporter: finds write-write and wildcard conflicts and reports them as Conflict objects.
PlanGenerator: produces PlanResult for each strategy.


Examples and Edge Cases 

Empty input array: return order: [], strategy: "CONSERVATIVE", conflicts: [], errors: [], cycles: [].

Use this example in the as the canonical indirect-cycle example (it actually forms A -> B -> C -> A):
A writes k1.
B reads k1 and writes k2.
C reads k2 and writes k1.
Under the dependency semantics:
A -> B because A writes k1 and B reads k1.
B -> C because B writes k2 and C reads k2.
C -> A because C writes k1 and A reads/writes k1 (or specifically because C writes k1 and A writes k1—there is a write-write relationship which the conservative strategy will serialize). Together these edges create the cycle A -> B -> C -> A. The resolver must detect and report ERR_CYCLE_DETECTED with the cycle ['A','B','C'] in deterministic order

Wildcard * means unknown keys: any call containing * in reads or writes is treated as touching unknown keys that may conflict with any other call.
Conservative strategy serializes wildcard calls with concrete-accessing calls using deterministic edges as follows (this is the single authoritative rule — remove any earlier, contradictory wording):
If a call C_w reads from wildcard (*) and another call C_c writes a concrete key, then add a dependency edge C_w -> C_c. This guarantees the wildcard read happens before the concrete write.
If a call C_w writes wildcard (*) and another call C_c reads or writes a concrete key, then add a dependency edge C_w -> C_c. This guarantees the wildcard write happens before the concrete access.
In words: under CONSERVATIVE, any wildcard call is serialized before concrete calls it might interact with by adding wildcard -> concrete edges, thereby conservatively ordering the wildcard to execute earlier than any concrete-accessing call that could be conflicted.

Optimistic strategy: any presence of * is treated as an unknown dependency. The OPTIMISTIC result must include ERR_UNKNOWN_DEPENDENCY and order should be null (the optimistic planner cannot safely order with unresolved wildcards).
ERR_UNKNOWN_DEPENDENCY and order: null.
Indirect cycles: A writes k1, B reads k1 and writes k2, C reads k2 and writes k1: this forms a cycle A -> B -> C -> A and the resolver must detect and report it as ERR_CYCLE_DETECTED with the cycle [A,B,C] in deterministic order.
Duplicate keys: multiple calls referencing same keys more than twice must be reported correctly in conflicts and in edges.
Large inputs: solution must handle up to 1000 calls efficiently in a single-threaded environment.

