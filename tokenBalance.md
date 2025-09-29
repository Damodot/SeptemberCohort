Token Balance Aggregator 
You are building an offline token balance aggregator for a single wallet address. The aggregator receives a list of contract "reads" simulated offline call results. Each contract may implement ERC20, ERC721, ERC1155, or multiple standards. The aggregator must:

Auto-detect the token standard for each contract using the provided contract metadata and cross-check that the provided read results match the detected standard.
Fail fast with precise, deterministic error messages for invalid inputs or interface mismatches.
Aggregate balances across multiple reads for the same contract while deduplicating tokenIds so the same tokenId is not counted twice.
Normalize addresses and tokenIds to canonical formats.
Provide stable ordering in the final output: tokens ordered by contract address, it must belowercase hex, lexical; then by tokenId numeric order when applicable.
Exclude tokens that have a final zero balance, unless the user explicitly included zero balances in the input read, in which case include them only if every read for that token produced zero.
Support proxy / multi-interface contracts by preferring the most specific standard detected in this order: ERC1155 > ERC721 > ERC20 when multiple valid interfaces are present.


API
Implement the following exported function:

export function aggregateBalances(walletAddress: string, reads: ContractRead[]): AggregatedToken[]
Types:

type Standard = 'ERC20' | 'ERC721' | 'ERC1155'

type ContractRead = {
contract: string
bytecode?: string
interfaces?: string[]
standardHint?: Standard
erc20?: { balance: string | number | bigint; decimals?: number }
erc721?: { tokenIds: (string | number)[] }
erc1155?: { balances: Record<string, string | number | bigint> }
}

type ERC20Output = {
contract: string
standard: 'ERC20'
decimals: number
balance: string
}

type ERC721Output = {
contract: string
standard: 'ERC721'
tokenIds: string[]
}

type ERC1155Output = {
contract: string
standard: 'ERC1155'
tokenBalances: { tokenId: string; amount: string }[]
}

type AggregatedToken = ERC20Output | ERC721Output | ERC1155Output

Formatting rules

Contract addresses: must be validated as 0x + 40 hex chars (case-insensitive), normalized to lowercase. If invalid, throw error 'ERR_INVALID_CONTRACT'.
walletAddress must be validated as 0x + 40 hex chars normalized to lowercase. If invalid, throw 'ERR_INVALID_ADDRESS'.
tokenIds are decimal strings in the output with no leading zeros except for "0".
amount/balance in outputs are decimal strings, representing integers (no scientific notation), amounts always as whole integers.
decimals for ERC20 in output must be an integer between 0 and 36 inclusive; if missing from inputs, default to 18.
Input tokenId values must be integers that are not negative, fractional and must be numeric
Input balance and amount values must represent whole integers, they can be negative to support debit-like operations and must not be fractional

Standard detection rules

If interfaces array is present:
If 'ERC1155' present => detected standard = ERC1155
Else if 'ERC721' present => detected standard = ERC721
Else if 'ERC20' present => detected standard = ERC20
Else if bytecode string is present:
If substring '1155' occurs anywhere => ERC1155
Else if substring '721' => ERC721
Else if substring '20' => ERC20
Else if standardHint present => that standard
Else throw 'ERR_UNDETECTABLE_STANDARD'

Data validity cross-checks
After detecting the standard, verify the read data matches expectation:
If the data field corresponding to the detected standard is missing, not an object, or lacks required properties, throw ERR_INTERFACE_MISMATCH.
If the data field is present but its values are malformed (e.g., a non-numeric balance string, a fractional tokenId), throw ERR_INVALID_INPUT
ERC20 requires erc20 field to be present with a numeric balance. If missing or invalid, throw 'ERR_INTERFACE_MISMATCH'.
ERC721 requires erc721 with an array of tokenIds. If missing or invalid, throw 'ERR_INTERFACE_MISMATCH'.
ERC1155 requires erc1155 with balances map. If missing or invalid, throw 'ERR_INTERFACE_MISMATCH'.
For ERC1155, all keys must be strings. 

Deduplication & aggregation rules
Within a single contract, multiple reads may appear. For ERC20: sum all erc20.balance values using bigint arithmetic. For ERC721: union the tokenId set across reads for that contract. For ERC1155: sum amounts per tokenId across reads, deduplicating tokenId keys.
If two reads for the same contract contain identical tokenId entries, they count only once (for ERC721) or their numeric amounts sum (for ERC1155).
For ERC20, if decimals vary across reads, treat discrepancy as an error and throw 'ERR_DECIMALS_MISMATCH'.
After summation, drop any token (ERC20 token with balance 0, ERC721 with no tokenIds, or ERC1155 tokenIds with amount 0) unless every read for that contract/token explicitly reported a zero.

Ordering rules
Output array sorted by contract address string ascending (lowercase lexical).
For ERC721.tokenIds and ERC1155.tokenBalances sort tokenIds numerically ascending (treat tokenId as arbitrary big integers). Represent tokenId as decimal string.
For ERC1155.tokenBalances, produce array of objects sorted by tokenId numeric order.

Error taxonomy
ERR_INVALID_ADDRESS
ERR_INVALID_CONTRACT
ERR_UNDETECTABLE_STANDARD
ERR_INTERFACE_MISMATCH
ERR_DECIMALS_MISMATCH
ERR_INVALID_INPUT

Examples

Example 1 simple ERC20
Input
walletAddress = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
reads = [
{ contract: '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', interfaces: ['ERC20'], erc20: { balance: '1000', decimals: 6 } },
{ contract: '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', interfaces: ['ERC20'], erc20: { balance: 2000, decimals: 6 } }
]
Output
[
{ contract: '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', standard: 'ERC20', decimals: 6, balance: '3000' }
]

Example 2 ERC721 dedupe and ordering
Input
reads with two contracts and overlapping tokenIds for first contract
Output
contracts sorted by address; tokenIds unique and sorted numerically

Example 3 ERC1155 merging
Input
reads include tokenId '1' with amount '2' and tokenId '1' amount 3 from another read
Output
single contract entry with tokenBalances [{tokenId:'1', amount:'5'}]

Error examples
If contract address malformed => throw Error('ERR_INVALID_CONTRACT')
If detected ERC20 but erc20 missing => throw Error('ERR_INTERFACE_MISMATCH')
If no interface or hint and bytecode missing => throw Error('ERR_UNDETECTABLE_STANDARD')