Nonce Manager & Batch Signer for Multi-Account Wallets
A cooperative network of validators consumes packetized requests that describe potential ledger mutations. Each packet must be translated into a canonical sequence of submissions. The system you implement should prepare this sequence while adhering to strict structural rules, error policies, and re-ordering guarantees.

Input Structure
The program accepts an array of request objects. Each request hereafter TxRequest is expected to conform to a rigid schema:

Required fields:
from: string; hex-style address, must be valid per Ethereum-like constraints
to: string; hex-style address, also validated
value: non-negative integer
gasLimit: non-negative integer
nonce: non-negative integer

Optional fields:
gasPrice: non-negative integer; if omitted, should be excluded from encoding
preferredNonce: non-negative integer; guidance only, validated for type or range

All numbers must be either JavaScript integers or numeric strings parseable as integers. Negative values or non-integer encodings trigger a validation failure.

Error Handling
Any malformed input should cause immediate rejection:
Missing required fields should throw "ERR_INVALID_REQUEST".
Improper address format foir example not 0x-prefixed hex should throw "ERR_INVALID_REQUEST".
Any numeric field that is negative, fractional, or not interpretable as an integer should throw "ERR_INVALID_REQUEST".

Transformation Process
Each valid TxRequest is expanded into a canonical submission object. Submissions must contain all validated fields and an additional raw payload. The payload is a base64 encoding of the JSON string representing the request with key ordering:

Keys appear in this fixed order:
from
to
value
gasLimit
nonce
gasPrice; optional
preferredNonce; optional

Example:
A request with { from: "0xaaa", to: "0xbbb", value: 1, gasLimit: 21000, nonce: 0 }; raw is the base64 of:

{"from":"0xaaa","to":"0xbbb","value":1,"gasLimit":21000,"nonce":0}

Ordering Rules
Before finalizing, all submissions must be sorted globally. Sorting applies the following precedence chain:

Primary key: ascending nonce
Secondary key: ascending from address (lexicographic)
Tertiary key: ascending to address (lexicographic)
Quaternary key: ascending value (numeric)
If ties persist beyond these, stability of the underlying sort is relied upon.

Expected Behavior
When multiple requests from the same account have the same nonce, the secondary/tertiary/quaternary keys decide the outcome.

Optional numeric fields (gasPrice, preferredNonce) are validated if present but do not affect sorting.

The output is the array of canonical submissions, in the globally ordered sequence.

Deliverables
Implement the function:
export function buildLedgerSequence(requests: TxRequest[]): Submission[];


Where:
TxRequest matches the schema above.
Submission is TxRequest & { raw: string }.

Errors are thrown as described in validation.
Notes
Ensure validation fires before any transformation or sorting.
raw encoding must match; superficial toContain checks are insufficient.
The specification requires reproducible behavior for large arrays.
Sorting must respect all four precedence layers, even if tertiary/quaternary rarely come into play.