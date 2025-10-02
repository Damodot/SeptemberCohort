Music Library Organizing and Curation Engine
Build a compiler that exercises curation and organization rules against a large music library dataset. This is an engineering-in-the-large problem: build an in-process solution that checks inputs, does canonical identity mapping, exercises an expressive rules language against item metadata, produces ranked playlist candidates, and emits a fully typed report that can be consumed by research or production pipelines. The implementation must be offline testable. 

Each rule expression is one declarative expression that filters items. The DSL supports the following operators and functions. The parser and evaluator must strictly conform to these semantics.

Supported fields
title (string)

artists (array of strings - references artist ids or their alternate IDs)

albumId (string)
durationSeconds (number)

bpm (number)

key (string)

releaseDate (ISO date or timestamp)
tags (array of strings)

metadata['someKey'] (string)

Field references are case-sensitive.

Primitive operators

Equality: == (strict string or numeric equality)

Inequality: !=

Numeric comparisons: <, <=, >, >=

Array and comma-separated list containment: IN and NOT IN (usage: key IN ('G','Am') or tags IN ('mellow','instrumental'))
IN semantics: when the left-hand field is a scalar, test whether its value equals any element of the right-hand list. When the left-hand field is an array, IN evaluates true if any element of the field array equals any element of the right-hand list. NOT IN is the logical negation of IN.

Regex-match for strings: matching is unanchored unless the pattern contains anchor characters (`^`, `$`): "Regex-match for strings: MATCHES /pattern/ (JavaScript RegExp semantics; unanchored unless pattern contains anchors)

Range for releaseDate: releaseDate BETWEEN '2020-01-01' AND '2021-01-01' (inclusive on both ends. If both boundaries are date-only strings (YYYY-MM-DD), they must be interpreted with day precision: the start is YYYY-MM-DDT00:00:00.000Z, the end is YYYY-MM-DDT23:59:59.999Z.)

Logical connectives: AND, OR, NOT (case is not required for capitalization; evaluator should be case-insensitive for these operators)

Parentheses for grouping:

Error Handling for Parser

The parser must throw error messages of the form:

"Syntax error: <reason>" for tokenization or unexpected symbol issues.
"Error parsing rule expression: <reason>" for invalid constructs that are syntactically valid but semantically invalid.

These messages must match exactly (including capitalization). Throwing generic Error objects with
different text is not acceptable. Evaluation must not proceed if parsing fails.


Type coercion and semantics

Comparisons of numbers need the field to exist and be parseable as a finite number. In case the field does not exist or is NaN, the comparison is false.

Validate inputs in the following order:  items, context and context.currentTime, context.rules, context.canonicalIdMapping

String equality compares strings.

IN and NOT IN test field value membership (if field scalar) or membership of any element (if field is array). Strings matched exactly.

For `IN` and `NOT IN`, if the field on the left-hand side is missing, `IN` evaluates to `false` and `NOT IN` evaluates to `true`.

MATCHES accepts string field; if missing field, result false.

BETWEEN for releaseDate: parse both sides to epoch milliseconds. If missing item releaseDate, test returns false.

Example expressions

bpm >= 120 AND bpm <= 130 AND key IN ('G','Gmaj')

tags IN ('violin','solo') OR title MATCHES /violin solo/i

releaseDate BETWEEN '2015-01-01' AND '2018-12-31'

NOT (durationSeconds < 30) AND tags NOT IN ('interlude')



Parsing rules
Grammar and AST Requirements

The DSL syntax must be parsed according to the following formal grammar (EBNF-like):

Expression   ::= OrExpr
OrExpr       ::= AndExpr { OR AndExpr }
AndExpr      ::= NotExpr { AND NotExpr }
NotExpr      ::= [NOT] CompareExpr
CompareExpr  ::= Primary ( ( "==" | "!=" | "<" | "<=" | ">" | ">=" ) Primary 
| "IN" List | "NOT" "IN" List | "MATCHES" Regex | "BETWEEN" LiteralDate "AND" LiteralDate )?
Primary      ::= FieldRef | Literal | "(" Expression ")"
FieldRef     ::= identifier | "metadata['" identifier "']"
List         ::= "(" Literal { "," Literal } ")"
Literal      ::= string | number
Regex        ::= "/" pattern "/" [flags]
LiteralDate  ::= string (ISO date or timestamp)

The parser must build a well-typed Abstract Syntax Tree (AST) where each node is explicitly tagged
with its operator type (e.g., "Comparison", "InList", "Between", "RegexMatch", "LogicalAnd", etc.).
Evaluation must always be performed over this AST; directly evaluating the raw string is not allowed.

The implementation must accept either a raw DSL expression string (to be parsed into AST) or a
pre-supplied AST object that already conforms to this schema. Both code paths must behave identically.


Left-to-right parsing of expressions according to precedence and parentheses: NOT first, comparison operators, then AND, then OR.

Logical operator keywords are case-insensitive.

DSL uses single quotes for string literals. Double quotes may be accepted for backward compatibility but single quotes are preferred.

For IN lists use parentheses and comma-separated quoted strings.

Behavior and Steps

Validation

When items is not an array: throw new Error("Invalid items input").

When context missing or not an object or context.currentTime missing or unparsable by Date.parse: throw new Error("Invalid context").

When context.rules is not an array or if any rule lacks id/priority/expression/label (or they are the wrong types): throw new Error("Invalid rule definition").

If context.canonicalIdMapping: if present but not plain object: throw new Error("Invalid context mapping").
Do all validation at once and rethrow the first relevant error.

Canonical ID mapping

Construct canonical item ids thus: for each ItemRecord.id, if there is a mapping entry in canonicalIdMapping[item.id] use that canonical id, else default to item.id. Use canonical ids everywhere in downstream arrays and objects.

Expression evaluation

Compare every rule expression with every item to produce a boolean. Evaluation of rules must adhere to DSL semantics to the letter.

When comparing artists, when evaluating artists IN ('A1','A2'), consider other artist ids by canonicalIdMapping each id in item.artists, if mapping exists, before checking membership. Similarly for albumId take mapping on albumId if mapping keys exist.

Rule ordering and selection

Sort context.rules in descending order of priority. In case of equal priority use rule id lexicographic sort in ascending order.

For each rule create one CandidatePlaylist in this order by grouping items that match the rule expression. Items may match multiple rules; they must still belong to each of the matching candidates.

Item ordering in a CandidatePlaylist

Within a candidate, sort matching items by:

releaseDate in descending order (newest first); missing releaseDate treated as epoch 0.

then by bpm in descending order (missing bpm treated as -Infinity).

then by canonical id lexicographic order.

Candidate stats

itemCount is number of items after filtering and mapping.
totalDurationSeconds is integer sum of durationSeconds over items.

averageBpm is arithmetic mean of bpm over items that have numeric bpm; omit field if no items have bpm. Use IEEE double arithmetic, do not round.

keysDistribution is a map of key-counting items; use the key value exactly as supplied. Missing keys are included in the empty string "".

IncludeZeroCandidates

If context.includeZeroCandidates === false, don't include any candidate whose itemCount === 0. By default include them (set to true).

Max candidates

If context.maxCandidates exists and is an integer > 0, return at most that many candidates sorted by rule priority and id. If maxCandidates is not a valid number (not an integer or <= 0), treat as absent.

Final report

Return CurateReport object populated as specified. generatedAt is set to context.currentTime. The order of the candidates array needs to be preserved.

Error Messages

Implementations must throw the literal messages below for the corresponding validation failures:

Items not an array: "Invalid items input"

Context missing or currentTime invalid: "Invalid context"

Rule array or rule missing required fields or wrong types: "Invalid rule definition"

canonicalIdMapping present but not a plain object: "Invalid context mapping"
Fail fast on the first validation error reached.

Determinism and Performance

Take only operations. No randomness or environment time calls except Date.parse(context.currentTime).

Implementation needs to enable the handling of a maximum of 200k items and 200 rules within reasonable memory and time constraints. Single-pass evaluation per rule whenever possible is preferable. But correctness and determinism are first. 