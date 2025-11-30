# Blockchain Tender System — Cardano_Hack

Overview
--------
This repository contains the codebase for a blockchain-based government tender system aimed at preventing corruption by making bidding, mapping, and finalization transparent and verifiable. The system implements two dashboards:

- Government dashboard: create tenders (projects) split into parts, set thresholds and ranges, filter bidders by time/cost ratio, and finalize an award after an offline verification step.
- Bidder dashboard: submit bids against tender parts, provide time/cost ratios and documents, and view bid status.

Repository structure (high level)
---------------------------------
The repository contains three main top-level directories:

- client/        — Front-end application(s) and dashboards (government + bidders).
- server/        — Backend services (indexing, API, off-chain helpers).
- tender-contract/ — Smart contract(s) for the tender workflow.

(This README describes the intended design, how to run the typical local dev stack, and recommended improvements & operational notes. Inspect tender-contract/ to confirm whether contracts target EVM (Solidity) or Cardano (Plutus/Haskell) and follow the corresponding instructions below.)

Project concept and workflow
----------------------------
Key concepts:
- Tender: a project issued by the government. Large projects can be split into multiple “parts” (for example, a road split into four segments).
- Part thresholds: for each part the government sets a price threshold (e.g., 5 CR). A bidder may bid up to that threshold and down to a defined lower limit (e.g., 80%=4 CR).
- Bids and time/cost ratio: bidders provide a bid (price) and an expected time. The application computes a time/cost ratio for each bidder-part (e.g., time / cost). The combined tender ratio can be computed as an average of part ratios.
- Filtering: after bidding closes, the system ranks bidders by their time/cost ratio and selects the top 20 (lowest ratios) and maps them to bidder identities (wallet address + stored metadata).
- Offline verification/selection: the government officer receives the shortlisted 20 bidders' identity and supporting documentation (off-chain) to perform due diligence and select one. The final selection is then recorded on-chain.
- Payments: the final payment transaction(s) are recorded on-chain to provide an immutable trail of disbursement. All mappings (who bid what, who selected who) are recorded on-chain so front-end can fetch histories confidently.

Smart contract design (recommended)
-----------------------------------
The repo already includes a sample smart-contract-style pattern (a certificate verification example). For the tender system you should have a contract that captures the tender lifecycle. Suggested contract entities and functions:

- Structs:
  - Tender { id, issuer, title, description, parts[] , status, createdAt }
  - Part { id, description, thresholdPrice, minAllowedPricePercent, timeWeight (optional) }
  - Bid { tenderId, partId, bidder, amount, timeEstimate, ratio, timestamp, documentsIpfsHash (optional) }
  - Shortlist { tenderId, bidderAddresses[] } // or dynamic list via events

- Core functions:
  - createTender(Tender metadata, Part[] parts) — government creates tender split into parts.
  - updateTender(...) — minor edits while tender open (restricted).
  - placeBid(tenderId, partId, amount, timeEstimate, ipfsHash) — bidders submit bids.
  - closeBidding(tenderId) — close bidding window and optionally compute ratios.
  - computeAndStoreRatios(tenderId) — either compute on-chain or compute off-chain and call a setter (on-chain computation is costlier).
  - shortlistTopBidders(tenderId, topN) — store or emit top N bidders (lowest ratios) so front-end can fetch.
  - finalizeWinner(tenderId, winnerAddress) — government records final winner (after offline verification).
  - recordPayment(tenderId, winnerAddress, amount, txRef) — record money transfer on-chain.
  - getters: getBidsByTender(), getBidsByBidder(), getTender(), getShortlist(), events for BidPlaced, ShortlistGenerated, WinnerSelected, PaymentRecorded.

- Events:
  - BidPlaced(tenderId, partId, bidder, amount, timeEstimate, ipfsHash)
  - ShortlistGenerated(tenderId, bidderAddresses[])
  - WinnerSelected(tenderId, winner)
  - PaymentRecorded(tenderId, to, amount, txRef)

Notes on on-chain vs off-chain computation:
- Calculating average time/cost ratio can be done off-chain to save gas; the contract should accept computed results and store/verifiable inputs (or rely on event logs).
- For fully on-chain ranking you must implement sorting/selection on-chain (expensive). A hybrid approach is recommended: emit all bids as events, compute ranking off-chain (server/indexer), then call the contract to record the shortlist and/or final winner (signed by the government account).

How bidder mapping and data retrieval should work
-------------------------------------------------
- Each bidder is primarily identified by their blockchain address.
- Sensitive personal data (address, PAN, ID docs, contact info) should NOT be stored on-chain. Instead:
  - Store metadata and pointers on-chain (IPFS/CID or hashed document references).
  - Maintain an off-chain server that maps blockchain addresses -> full identity info (used by government officers for offline verification).
- Ensure the contract emits events for every critical action so the server and front-end can index and display data without needing to query deep historical transaction logs.
- Provide indexed API endpoints (server/) to return:
  - Tender details
  - Bids per tender (and per part)
  - Computed ratios and shortlists
  - Final winner and payment history

Run & Development instructions (generic)
----------------------------------------
Below are two sets: EVM (Solidity) oriented and Cardano (Plutus) oriented. Inspect tender-contract/ to confirm your implementation.

A) If tender-contract/ uses Solidity / EVM (Hardhat or Truffle)
1. Prerequisites
   - Node.js 16+ and npm or yarn
   - Hardhat or Truffle installed globally or as dev dependency
   - A local node (Hardhat node or Ganache) or an RPC endpoint (Goerli, Sepolia, a local Dockerized node)
   - An ETH-compatible wallet private key for deployer (use .env and never commit secrets)

2. Typical local flow (Hardhat example)
   - cd tender-contract
   - npm install
   - npx hardhat node          # run local node
   - npx hardhat run scripts/deploy.js --network localhost
   - Note deployed contract address and ABI

3. Frontend / Server setup
   - cd server
   - cp .env.example .env      # fill in RPC_URL, CONTRACT_ADDRESS, PRIVATE_KEY, INFURA_KEY, etc.
   - npm install
   - npm run start             # start API & indexer
   - cd ../client
   - cp .env.example .env      # fill FRONTEND_CONTRACT_ADDRESS, RPC_URL, etc.
   - npm install
   - npm run dev               # start frontend (usually port 3000/5173)

4. Testing
   - cd tender-contract
   - npx hardhat test

B) If tender-contract/ targets Cardano / Plutus
1. Prerequisites
   - Install Cardano node and cardano-cli (or use a sandbox/testnet)
   - Haskell toolchain, cabal/stack if using Plutus contracts
   - IPFS setup if storing docs off-chain
2. Typical flow
   - Build Plutus contracts (refer to tender-contract/ README or scripts)
   - Deploy to a testnet (follow Cardano docs for script addresses and datum construction)
   - Start the server to index chain events and handle bids
   - Run client pointing to the server for contract addresses and info

Environment variables (.env.example)
-----------------------------------
The repo should include a .env.example. Suggested vars:

- NETWORK_RPC_URL=https://localhost:8545
- CONTRACT_ADDRESS=0x...
- DEPLOYER_PRIVATE_KEY=0x...
- IPFS_API_URL=https://ipfs.infura.io:5001
- SERVER_PORT=4000
- DB_URL=postgresql://user:pass@localhost:5432/tenders

Front-end usage
---------------
- Government Dashboard:
  - Create tender, specify parts and threshold prices
  - Set bidding window (start/end)
  - After bidding closes, trigger shortlist generation (this can call server-side ranking)
  - Export the top 20 bidders (server provides bidder identities/contacts for offline checking)
  - After offline checks, select winner and record finalization on-chain

- Bidder Dashboard:
  - Connect wallet (Metamask or Cardano wallet depending on chain)
  - View open tenders and parts
  - Submit bids (amount, time estimate, and upload supporting docs—store docs off-chain as IPFS and send CID)
  - Track bid status, shortlist inclusion, and final result

Indexing & server responsibilities
---------------------------------
The server (server/) should:
- Listen to contract events (via web3/ethers or Cardano indexer) and store bid data in a database.
- Compute time/cost ratios and produce a sortable list for each tender (or accept on-chain results).
- Provide REST/GraphQL API used by the client to display tenders, bids, shortlists and payment receipts.
- Securely store bidder personal info (only accessible to government admins, with audit logs).

Security & privacy considerations
--------------------------------
- Do not store personally identifiable information (PII) directly on-chain. Use IPFS with encryption and/or store only hashes/CIDs.
- Use role-based access control on APIs. Government-only actions (create tender, finalize winner) should require government account signatures and server-side checks.
- Validate that bids respect threshold ranges on the client and server. Also validate on-chain where possible.
- Use events for all on-chain state changes to make front-end sync straightforward.
- Store an audit trail (tx hashes, timestamps, signer addresses) for every important event.

Suggested next steps & improvements
----------------------------------
- Add tests covering bid placement, shortlisting, and finalization.
- Add automated scripts to compute and submit the shortlist to the contract (or a signed government message).
- Integrate The Graph (or custom indexing) to speed queries for lists and leaderboards.
- Add end-to-end example: deploy locally, run a sample tender, submit several bids, produce shortlist, finalize winner, and record payment.
- If you intend to use Cardano/Plutus, include a clear tender-contract README describing build and deployment steps for Plutus scripts.

Files you should add (if missing)
---------------------------------
- tender-contract/README.md — build & deploy instructions specific to the contract language.
- .env.example — environment variables for client and server.
- scripts/deploy.* — one-click deploy script for development networks.
- server/seed-data or sample-data — sample tenders & bids for local testing.
- client/docs — instructions and screenshots for both dashboards.

License
-------
MIT — see LICENSE file (please add if missing).

Contact
-------
For questions about this repository, open an issue in the repo and include:
- clear description of the problem or feature request
- logs or screenshots (if applicable)
- steps to reproduce

Closing notes
-------------
This README documents the intended behaviour and provides a practical local dev checklist. Inspect the actual code in each top-level folder (client/, server/, tender-contract/) and adapt build/deploy instructions to the concrete stack found in the repository (Solidity/Hardhat vs Plutus tools). If you’d like, I can create:
- a concrete tender smart contract example (Solidity),
- a deployment script for Hardhat,
- or a step-by-step, tested set of commands tailored to the actual files inside tender-contract/ once you confirm which language/tooling is used there.