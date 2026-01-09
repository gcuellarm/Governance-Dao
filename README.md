# [==>] Governance DAO (Foundry)
 
 ## [*] Overview (Goal + How It Works)
 
 This repository contains a simple **on-chain Governance DAO** written in Solidity and tested with **Foundry**.
 
 The goal of the project is to demonstrate a complete governance flow:
 - **Token-based voting power** (ERC20).
 - **Proposal creation** gated by a minimum voting power threshold.
 - **Voting window** (start/end time).
 - **Quorum** requirement (minimum total votes).
 - **Execution** of successful proposals through a **Treasury** contract.
 
 At a high level:
 1. Users hold `DAOGovernanceToken` tokens.
 2. A user with enough voting power creates a proposal in `DAO`.
 3. Token holders vote `for` / `against` during the voting period.
 4. After the period ends, if quorum is reached and `forVotes > againstVotes`, the proposal can be executed.
 5. Execution triggers the `DAOTreasury` to approve and then spend funds (ETH or ERC20) according to the proposal.
 
 ## [:-)] Project Structure
 
 ```text
 src/
   DAOGovernanceToken.sol
   DAO.sol
   DAOTreasury.sol
 test/
   DAO.t.sol
 ```
 
 ## [>>] Quick Start
 
 ### Requirements
 - Foundry (Forge)
 
 Docs: https://book.getfoundry.sh/
 
 ### Build
 
 ```bash
 forge build
 ```
 
 ### Test
 
 ```bash
 forge test -vv
 ```
 
 ### Format
 
 ```bash
 forge fmt
 ```
 
 ## [TOKEN] DAOGovernanceToken.sol
 
 `DAOGovernanceToken` is a basic ERC20 token used as the governance voting unit.
 
 ### Key Features
 - **ERC20** token (OpenZeppelin).
 - **Owner-controlled minting** via `mint(address to, uint256 amount)`.
 - **Self-burning** via `burn(uint256 amount)`.
 - A custom “delegation” mechanism via `delegateVotingPower` / `undelegateVotingPower`.
 
 ### Important Note About “Delegation”
 In this implementation, `delegateVotingPower(delegate, amount)` is implemented as an **ERC20 transfer** of tokens
 from the delegator to the delegate. This means:
 - The delegate receives the tokens and therefore holds the voting power.
 - This is **not** the same as OpenZeppelin’s `ERC20Votes` / Governor-style signature-based delegation.
 
 ### Public State
 - `hasDelegated[address]`: tracks if an address has an active delegation.
 - `delegates[address]`: the delegate address chosen by a delegator.
 - `delegatedVotes[address]`: an aggregate counter of delegated votes per delegate.
 
 ### Main Functions
 - `delegateVotingPower(address delegate, uint256 amount)`
   - Reverts if:
     - `delegate == address(0)`
     - `delegate == msg.sender`
     - `amount == 0`
     - `balanceOf(msg.sender) < amount`
   - Transfers tokens to `delegate` and updates tracking mappings.
 
 - `undelegateVotingPower(uint256 amount)`
   - Reverts if:
     - no delegation exists
     - `amount == 0`
     - delegated amount is insufficient
   - Transfers tokens back from the stored delegate to the caller and updates tracking.
 
 - `getVotingPower(address account)`
   - Returns `balanceOf(account)`.
 
 ## [TREASURY] DAOTreasury.sol
 
 `DAOTreasury` is responsible for holding and spending DAO funds.
 It only allows spending when instructed by the DAO contract.
 
 ### Key Features
 - Holds **ETH** (via `fundTreasury()` or `receive()` fallback).
 - Holds **ERC20 tokens** via `fundTreasuryWithToken(address token, uint256 amount)`.
 - Tracks proposal lifecycle:
   - `approvedProposals[proposalId]`
   - `executedProposals[proposalId]`
 
 ### Roles and Permissions
 - `owner` (Ownable): can set the DAO address with `setDAO(address)` and can call `emergencyWithdraw(...)`.
 - `dao` address: the only address that can call:
   - `approveProposal(uint256)`
   - `spendFunds(uint256, address, uint256, address)`
 
 ### Main Functions
 - `fundTreasury()` (payable)
   - Reverts if `msg.value == 0`.
 
 - `fundTreasuryWithToken(address token, uint256 amount)`
   - Requires prior `approve(treasury, amount)` on the token.
   - Reverts if `token == address(0)` or `amount == 0`.
 
 - `approveProposal(uint256 proposalId)`
   - DAO-only.
   - Reverts if already approved.
 
 - `spendFunds(uint256 proposalId, address recipient, uint256 amount, address token)`
   - DAO-only.
   - Requires approved proposal and not already executed.
   - If `token == address(0)`, sends ETH; otherwise sends ERC20.
 
 - `emergencyWithdraw(address token, uint256 amount, address recipient)`
   - Owner-only emergency escape hatch.
 
 ## [DAO] DAO.sol
 
 `DAO` is the core governance contract:
 it stores proposals, handles voting, and triggers execution through the Treasury.
 
 ### Configuration Parameters
 - `proposalThreshold`: minimum voting power required to create a proposal.
 - `votingPeriod`: duration (in seconds) for voting.
 - `quorumVotes`: minimum total votes (`forVotes + againstVotes`) for a proposal to be executable.
 
 These values can be changed by the contract `owner` via `updateConfiguration(...)`.
 
 ### Proposal Model
 Each proposal stores:
 - proposer, description
 - voting window: `startTime`, `endTime`
 - tallies: `forVotes`, `againstVotes`
 - state flags: `executed`, `canceled`
 - execution payload: `recipient`, `amount`, `token` (ETH if token is `address(0)`)
 - per-voter tracking: `hasVoted[voter]` and `votedFor[voter]`
 
 ### Core Flow
 - `createProposal(description, recipient, amount, token)`
   - Requires:
     - sufficient voting power
     - non-empty description
     - valid recipient
     - amount > 0
 
 - `vote(proposalId, support)`
   - Requires:
     - proposal exists
     - voting is active
     - caller has not already voted
     - proposal is not canceled/executed
     - caller has voting power > 0
 
 - `executeProposal(proposalId)`
   - Requires:
     - voting ended
     - not executed and not canceled
     - quorum reached
     - `forVotes > againstVotes`
   - Then calls:
     - `treasury.approveProposal(proposalId)`
     - `treasury.spendFunds(proposalId, recipient, amount, token)`
   - Finally marks the proposal as executed.
 
 - `cancelProposal(proposalId)`
   - Only proposer or owner.
 
 - `proposalPassed(proposalId)`
   - Read-only helper that checks whether a proposal is currently considered “passed” after the voting period.
 
 ## [TESTS] Test Suite (DAO.t.sol)
 
 The test file `test/DAO.t.sol` provides unit and integration coverage across:
 
 ### Token tests
 - Initialization (name/symbol/supply).
 - Minting/burning.
 - Delegation / undelegation and revert scenarios.
 
 ### DAO tests
 - Proposal creation and proposal storage.
 - Voting flow (for/against tallies).
 - Negative tests (reverts) for:
   - insufficient voting power for proposals
   - invalid proposal inputs
   - voting after the voting period
   - voting with no voting power
   - voting on canceled proposals
   - executing without quorum / without passing / without treasury funds
   - cancellation edge cases
 
 ### Treasury tests
 - Funding with ETH.
 - Funding with ERC20 tokens.
 - Approval and spending permissions.
 - Reverts for unauthorized access and double execution.
 
 ### Integration workflow test
 A full end-to-end scenario that exercises:
 - treasury funding
 - delegation (token transfer based)
 - proposal creation
 - voting
 - time warp beyond the voting period
 - proposal execution
