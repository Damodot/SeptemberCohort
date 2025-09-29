Gas-Efficient Multi-Sig Transaction Builder with Offline Signing
You will build an auditable module that assembles Ethereum-style multi-signature transactions from partial offline signatures. The builder accepts a transaction template and a fixed signer list (N signers), receives partial signatures in any order, validates each signature against the corresponding signer's public key, enforces an M-of-N quorum, protects against replay by strict nonce and chainId matching, and serializes to a canonical byte-for-byte representation ready for broadcast.

Goals
Accept a transaction description and signer roster.
Validate and buffer partial signatures arriving out of order.
Enforce quorum: at least M valid, distinct signer signatures required.
Prevent replay: signatures must match the configured chainId and nonce.
Produce canonical serialization: identical inputs yield identical byte-for-byte output.
Fail fast: invalid signatures, duplicates, bad recovery ids, nonce/chainId mismatch, or invalid config must throw exact errors (see error taxonomy).
Provide observable state methods for tests and callers.

Environment and constraints
Offline testing only. Network or nonstandard OS features are not to be accessed.
Fixed randomness/time if needed; but this problem does not require randomness or clocks.

Types and Interfaces
The module must export the following types and one class exactly as described:

TransactionTemplate:
type TransactionTemplate = {
  chainId: number;
  nonce: number;
  to: string;
  value: string;
  data: string;
  gasLimit: number;
  gasPrice: number;
};
to is a checksummed or non-checksummed hex string starting with "0x".
value is a decimal string representing wei.
data is a hex string starting with "0x".
All fields are required.

Signer:
type Signer = {
  id: string;
  publicKeyPem: string;
};

id is an arbitrary unique string that identifies a signer.
publicKeyPem is the PEM-encoded public key string for the signer in the Node crypto standard format (SPKI PEM for ECDSA secp256k1). Tests will generate keys using Node crypto.

MultiSigConfig:
type MultiSigConfig = {
  m: number;
  signers: Signer[];
};
m is the quorum threshold.
signers is an array of Signer with length N. Signer order in this array determines canonical signature placement for final serialization.

PartialSignature:
type PartialSignature = {
  signerId: string;
  signature: string;
  recovery?: number;
};

signature is a DER-encoded ECDSA signature represented as a base64 string of the DER bytes.
recovery is optional and if present must be an integer 0 or 1. If present and not 0 or 1 exactly, it is considered invalid.

SerializedMultiSig:
type SerializedMultiSig = {
  payload: string;
  signatures: { signerId: string; signature: string; recovery?: number }[];
};

payload is a lowercase hex string starting with "0x" that represents the canonical serialized transaction template bytes.
signatures is an array whose order is exactly the same as the signers array from the original config. For signer slots that have no signature, the signature field is the empty string "" and recovery is omitted.

MultiSigBuilder
Constructor:
constructor(template: TransactionTemplate, config: MultiSigConfig);

Methods:

addPartialSignature(ps: PartialSignature): void;
isReady(): boolean;
missingSigners(): string[];
isValidSignature(signerId: string): boolean;
finalize(): SerializedMultiSig;
getCanonicalPayloadBytes(): Uint8Array;

Canonical serialization 
A canonical payload is a byte-for-byte representation of the transaction template. The canonicalization process is strictly defined and must be implemented exactly as follows:

Construct a JSON object with EXACT key ordering:
{
  "chainId": <number>,
  "nonce": <number>,
  "to": "<string>",
  "value": "<string>",
  "data": "<string>",
  "gasLimit": <number>,
  "gasPrice": <number>
}

Convert that JSON object to its UTF-8 bytes using Buffer.from(JSON.stringify(obj), "utf8").
The canonical payload hex string is "0x" + lowercase hex of those bytes.
This exact construction ensures deterministic bytes across environments.
getCanonicalPayloadBytes() returns the raw UTF-8 bytes (Uint8Array) used above.

Signature validation rules
Each PartialSignature must reference a known signerId that exists in config.signers. If signerId is unknown, throw Error with message ERR_UNKNOWN_SIGNER.
Duplicate attempts to add a signature for the same signer must throw Error ERR_DUPLICATE_SIGNER.
If ps.recovery is present and its value is not exactly 0 or 1, throw Error ERR_INVALID_RECOVERY_ID.
Signatures are DER ECDSA bytes encoded as base64. To validate a signature:
Compute the message to sign as the SHA256 digest of the canonical payload bytes.
Use Node crypto verify with algorithm "sha256" and the signer's publicKeyPem to verify the DER signature against the message digest.
If the signature does not validate, throw Error ERR_INVALID_SIGNATURE.
The builder must perform validation at addPartialSignature time and must fail fast with the error codes above.
isValidSignature(signerId) returns true only if a valid signature for that signer has already been added and validated; otherwise false.

Quorum and replay protection
When constructing MultiSigBuilder, validate:
signers.length must be > 0; otherwise throw Error ERR_EMPTY_SIGNERS.
m must be an integer satisfying 1 <= m <= signers.length; otherwise throw Error ERR_M_GT_N.
There is no additional external state; replay protection is strict equality checks:
Each signature is validated against the canonical payload bytes derived from the constructor template. If an attempted signature was produced over a template with a different chainId or nonce, the signature verification will fail and yield ERR_INVALID_SIGNATURE at add time. There is no separate nonce mismatch code beyond signature rejection.

finalize():
Must throw Error ERR_INSUFFICIENT_SIGNATURES if the count of valid distinct signatures is less than m.
On success, returns SerializedMultiSig object described above.
The payload must be the canonical payload hex string.
signatures array must have length equal to signers.length and maintain signer order from config.signers. For each signer:
If a valid signature exists for that signer, include { signerId, signature: <base64 DER>, recovery?: <number if provided> }.
If none, include { signerId, signature: "" }.
The finalized output must be purely deterministic given the same inputs.

Observable state
isReady() returns true when at least m distinct valid signatures have been added.
missingSigners() returns an array of signerId for signers that do not currently have a valid signature, preserving the same order as config.signers.
isValidSignature(signerId) as specified above.

Error taxonomy
All thrown errors must be Error objects with these exact message strings (case sensitive):
ERR_EMPTY_SIGNERS
ERR_M_GT_N
ERR_UNKNOWN_SIGNER
ERR_DUPLICATE_SIGNER
ERR_INVALID_RECOVERY_ID
ERR_INVALID_SIGNATURE
ERR_INSUFFICIENT_SIGNATURES
No other error messages are acceptable in tests.
Edge cases and negative inputs must be handled

Duplicate signatures: attempts to add for the same signer should be rejected with ERR_DUPLICATE_SIGNER.
Invalid DER signature format: should be rejected with ERR_INVALID_SIGNATURE.
Invalid recovery field (e.g., 2, -1, 3): should be rejected with ERR_INVALID_RECOVERY_ID.
Wrong chainId or nonce used to sign (signature will not verify): should be rejected with ERR_INVALID_SIGNATURE.
m > N or m <= 0 or empty signer list: rejected at construction time with ERR_M_GT_N or ERR_EMPTY_SIGNERS.
Signatures arriving out of order must be accepted and stored; finalize() must place them in signer order.
Large N (e.g., 50) should work logically; implementation should be efficient.
Duplicate signer ids in config are not permitted. If duplicates exist, constructor must throw ERR_M_GT_N (reuse this code path to denote invalid config). Tests will not rely on a special error for duplicate signer ids beyond this.

Examples
Example 1: valid flow
Construct template T with chainId 1 and nonce 42.
Provide config with m = 2 and signers [A, B, C] with valid public keys.
Create builder with T and config.
Signer B signs payload->signature_B offline, signer A signs payload->signature_A offline.
Call addPartialSignature with B (works), then A (works).
isReady() returns true.
finalize() returns payload canonical hex bytes and signatures array with A and B in their signer slots and C as empty string.

Example 2:
addPartialSignature with recovery = 2 must immediately throw ERR_INVALID_RECOVERY_ID.

Example 3:
m = 3, only 2 valid signatures added, calling finalize() must throw ERR_INSUFFICIENT_SIGNATURES.

Testability
Tests will generate ECDSA secp256k1 key pairs using Node standard library and compute signatures over the canonical payload bytes using the private keys.
Tests will check every error message string exactly, observable state methods, ordering of signatures in the serialized result, and canonical payload hex correctness.
No network access, no external randomness.