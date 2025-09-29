Strictly Typed On-Chain Event Decoder with ABI Versioning

You must implement a solution that decodes raw Ethereum-like logs into strictly typed event objects using a versioned ABI registry. The system models a multiple smart contract versions, event signature matching, indexed and non-indexed parameter handling, error taxonomy, and robust handling of malformed or partial data.The decoder must not rely on external packages. All cryptographic hashes expected by the tests are provided as precomputed topic0 strings in the registry

Definitions and Types
export type ABIInput = {
name: string
type: 'address' | 'uint256' | 'bool' | 'bytes32' | 'string' | 'bytes'
indexed: boolean
}

export type EventABI = {
name: string
inputs: ABIInput[]
topic0: string
}

export type ContractVersion = {
version: string
events: EventABI[]
}

export type ABIRegistry = Record<string, ContractVersion[]>

export type RawLog = {
address: string
topics: string[]
data: string
}

export type DecodedValue = string | bigint | boolean | null

export type DecodedEvent = {
contractAddress: string
contractVersion: string
eventName: string
args: Record<string, DecodedValue>
}

export type DecodeError = {
code: string
message: string
log?: RawLog
}

export function decodeLog(registry: ABIRegistry, log: RawLog): { event?: DecodedEvent; error?: DecodeError }

Registry and Topic Matching Rules
The registry maps lowercase checksummed address strings (the tests will use lowercase addresses) to an array of ContractVersion entries. Each contract version contains a version string and an array of event ABIs.

Each EventABI includes a precomputed topic0 value (a hex string with 0x prefix). The decoder must match log.topics[0] exactly against an event's topic0 for the contract version to be considered a match.

If the contract address is not present in the registry, the decoder must return an error with code: 'ERR_UNKNOWN_CONTRACT' and a human readable message exactly describing that the contract address is unknown.

<address> isn’t a placeholder for something abstract, it must be substituted with the actual value of the log.address field from the offending log.

If log.topics[0] does not match any topic0 in any version for that address, the decoder must return an error with code: 'ERR_INVALID_LOG_SIGNATURE' and a message describing that the signature is unknown.

If multiple versions for the same address contain the same topic0, the decoder must prefer the latest version using lexicographic descending order on version strings and use that ContractVersion for decoding

ABI Decoding Rules

The ABI encoding uses Ethereum standard ABI packing for non-indexed values placed in data as concatenation of 32-byte words. Dynamic types use offsets as in standard ABI.

Supported types are address (right-most 20 bytes of 32), uint256 (unsigned big integer, 32 bytes big-endian), bool (32th word 0 or 1), bytes32 (32 bytes hex), string and bytes (both dynamic using offset+length encoding).

Indexed parameters appear in topics starting at topics[1] in the same order as they are listed in inputs. For an indexed static type (address, uint256, bool, bytes32) decode its value directly from the corresponding topic word. For an indexed dynamic type (string, bytes) do not attempt to reconstruct the original value; instead return null for that argument and include an additional key in args named <paramName>_indexedHash whose value is the hex string of the topic hashed value (topics entry).

Non-indexed parameters are decoded from data. If data is too short to contain the expected words, return an error with code: 'ERR_TRUNCATED_DATA' and a message that explains the truncation.

Parameter names may be empty strings; when empty, generated keys in args must be _0, _1, etc, using positional index among all inputs starting at 0.

If there are duplicate parameter names in the same event ABI, differentiate them by suffixing _dup1, _dup2, etc, to ensure unique keys.

The returned args mapping must preserve the original order of parameters as object insertion order: inputs earlier in ABI appear earlier in the object when iterated.

Error Taxonomy and Codes

All errors must follow the shape DecodeError and use the exact codes and messages listed below. Messages must be human readable and informative. Codes must be exact strings.

ERR_UNKNOWN_CONTRACT message example: "Unknown contract address 0xabc..." where the address is the given log.address.

ERR_INVALID_LOG_SIGNATURE message example: "Unknown event signature 0xdead... for contract 0xabc...".

ERR_TRUNCATED_DATA message example: "Truncated data while decoding event Transfer for contract 0xabc...".

ERR_MALFORMED_HEX message example: "Malformed hex in data or topics for contract 0xabc...".

ERR_DUPLICATE_EVENT_TOPIC message example: "Duplicate event topic 0xabc... in registry for contract 0xabc..." and must only be returned when the same topic0 exists on the same address across multiple versions and lexicographic version resolution is ambiguous (exact same version string present twice).

When returning an error, include the original log in the log field of the DecodeError result.

Inputs and Output Exact Formats

RawLog fields are exact:

address: lowercase hex string starting with 0x and 40 hex chars after that.

topics: array of hex strings starting with 0x and exactly 66 characters for topic words (0x + 64 hex chars). The array length may be 0 for malformed logs.

data: hex string starting with 0x. It may be 0x for empty payload.

The returned DecodedEvent.args values must follow these mappings:

address -> lowercased hex string with 0x + 40 chars.

uint256 -> bigint

bool -> boolean

bytes32 -> 0x-prefixed 64 hex chars string

string/bytes -> UTF-8 decoded string for string and 0x-prefixed hex for bytes.

For indexed dynamic types the arg value is null and an extra key of form <name>_indexedHash maps to the topic hex.

Examples

Registry example minimal form:

Address 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa has two versions: v1 and v2. v2 contains a Transfer event with topic0 0xtopicV2 and inputs [from(address indexed), to(address indexed), value(uint256)]. v1 contains Transfer with different parameter order producing different topic0. The decoder must pick v2 if its version string sorts later.

Log example minimal form:

log.address 0xaaaaaaaa..., topics [0xtopicV2, 0x000...from, 0x000...to], data 0x...valueWord

Expected decoded event: contractVersion 'v2', eventName 'Transfer', args { from: '0x...', to: '0x...', value: 123n }

Edge Cases and Determinism

Zero address "0x0000000000000000000000000000000000000000" is a valid address and must be looked up in the registry normally.

Malformed hex in any topic or data must yield ERR_MALFORMED_HEX with the log attached.

If multiple versions exist and one version string is duplicated exactly and both contain the same topic0, return ERR_DUPLICATE_EVENT_TOPIC.

The solver must not compute any cryptographic hashes. The tests provide all topic0 values.