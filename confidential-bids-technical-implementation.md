# Technical Implementation: Confidential Bids Architecture

Confidential Bids are implemented through a hybrid on-chain/off-chain architecture that leverages the C721Stash contract framework. The system maintains an off-chain order book where bids are stored with a confidential flag, ensuring that bid details—including price, target punks, and bidder identity—remain private from the public market.

## Authentication and Access Control

Access control is enforced through a cryptographic authentication mechanism: users authenticate by signing a message with their wallet (EIP-191 signature), which is verified on-chain to recover their address. Upon successful verification, the backend generates a JWT token that encodes the user's wallet address. This token serves as proof of wallet ownership and is required to access confidential bid data through protected API endpoints.

The authentication flow follows a standard Web3 signature pattern:
1. User requests an authentication message from the backend
2. User signs the message with their wallet using EIP-191 personal sign
3. Backend verifies the signature by recovering the signer's address
4. Upon successful verification, a JWT token is issued with the wallet address as the payload
5. The JWT token is included in subsequent API requests via the Authorization header

## Ownership Verification and Bid Filtering

When querying the order book, the system performs on-chain verification of punk ownership by checking the Ethereum blockchain state. The backend queries the CryptoPunks contract to determine which punks are owned by the authenticated user's address. This ownership verification occurs in real-time, ensuring that only legitimate owners can view relevant confidential bids.

The filtering mechanism works as follows:
- For each confidential bid in the order book, the system checks if the authenticated user owns at least one punk matching the bid's target criteria
- Collection bids (targeting all punks) are visible to any user who owns at least one punk
- Trait bids are visible to users who own punks with the specified traits
- Custom punk bids are visible only to owners of the specific punk IDs targeted
- Owner-specific bids are visible only to the wallet address specified in the bid
- The bidder who created a confidential bid can always view their own bids, regardless of ownership

This ensures that confidential bids remain private while still being discoverable by the parties who can potentially accept them.

## On-Chain Settlement

When a confidential bid is accepted, settlement occurs on-chain through the C721Stash contract's `processBid` function. This function validates the bid using EIP-712 typed data signatures, ensuring cryptographic proof of bid authenticity and preventing replay attacks through nonce management.

The settlement process includes:
1. **Signature Verification**: The bid signature is verified using EIP-712 structured data hashing, which includes the order details (numberOfUnits, pricePerUnit, auction address), account nonce, bid nonce, expiration timestamp, and merkle root
2. **Nonce Validation**: The contract checks that the account nonce matches the stash owner's current nonce, and that the bid nonce hasn't been used before
3. **Expiration Check**: If the bid has an expiration timestamp, the contract verifies it hasn't expired
4. **Merkle Proof Verification**: For targeted bids (non-collection bids), a merkle proof is provided to prove the punk ID is included in the bid's merkle tree
5. **Liquidity Check**: The contract verifies sufficient ETH or WETH is available in the stash to fulfill the bid
6. **Token Transfer**: The punk is transferred from the seller to the stash owner, handling both wrapped and unwrapped punks appropriately
7. **Payment**: The bid amount is transferred to the seller (msg.sender)

The use of EIP-712 signatures provides several security benefits:
- **Readable Signatures**: Users can see exactly what they're signing in their wallet interface
- **Replay Protection**: The domain separator includes the chain ID and contract address, preventing cross-chain and cross-contract replay attacks
- **Nonce Management**: Account and bid nonces prevent signature reuse and allow for bid cancellation

## Architecture Benefits

This architecture enables private price discovery while maintaining the security guarantees of on-chain verification, creating a new trading paradigm that combines the discretion of off-chain negotiation with the trustlessness of blockchain settlement. The hybrid approach allows for:

- **Privacy**: Bid details remain confidential until acceptance, preventing market manipulation and front-running
- **Security**: On-chain verification ensures only legitimate owners can view relevant bids
- **Trustlessness**: Settlement occurs entirely on-chain with cryptographic proof of bid authenticity
- **Flexibility**: The off-chain order book enables complex bid types (traits, owners, custom selections) without on-chain storage costs
- **Efficiency**: Bidders don't need to lock capital on-chain until a bid is accepted, improving capital efficiency
