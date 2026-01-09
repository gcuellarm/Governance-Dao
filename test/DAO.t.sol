// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/DAOGovernanceToken.sol";
import "../src/DAO.sol";
import "../src/DAOTreasury.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title DAOTest
 * @dev Comprehensive test suite for the DAO governance system
 */
contract DAOTest is Test {
    // Test addresses
    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public user3 = address(4);
    address public delegate = address(5);

    // Contracts
    DAOGovernanceToken public governanceToken;
    DAO public dao;
    DAOTreasury public treasury;

    // Test parameters
    uint256 public constant INITIAL_SUPPLY = 1000000 * 10 ** 18; // 1M tokens
    uint256 public constant PROPOSAL_THRESHOLD = 1000 * 10 ** 18; // 1K tokens
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant QUORUM_VOTES = 10000 * 10 ** 18; // 10K tokens

    // Events to test
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string description,
        address recipient,
        uint256 amount,
        address token,
        uint256 startTime,
        uint256 endTime
    );
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 votes);
    event ProposalExecuted(uint256 indexed proposalId);
    event VotingPowerDelegated(address indexed delegator, address indexed delegate, uint256 amount);

    function setUp() public {
        // Deploy governance token
        vm.startPrank(owner);
        governanceToken = new DAOGovernanceToken("DAO Token", "DAO", INITIAL_SUPPLY);

        // Deploy treasury first (without DAO address initially)
        treasury = new DAOTreasury(address(0));

        // Deploy DAO with treasury address
        dao = new DAO(address(governanceToken), address(treasury), PROPOSAL_THRESHOLD, VOTING_PERIOD, QUORUM_VOTES);

        // Set DAO address in treasury
        treasury.setDAO(address(dao));

        // Distribute tokens to test users
        governanceToken.mint(user1, 50000 * 10 ** 18);
        governanceToken.mint(user2, 30000 * 10 ** 18);
        governanceToken.mint(user3, 20000 * 10 ** 18);
        vm.stopPrank();
    }

    // ============ Helper Functions ============

    /**
     * @dev Helper function to create a proposal with default values
     * @param description Description of the proposal
     * @return proposalId The ID of the created proposal
     */
    function createTestProposal(string memory description) internal returns (uint256 proposalId) {
        return dao.createProposal(
            description,
            user1, // recipient
            1 ether, // amount: 1 ETH
            address(0) // token: ETH
        );
    }

    // ============ Governance Token Tests ============

    function testTokenInitialization() public {
        assertEq(governanceToken.name(), "DAO Token");
        assertEq(governanceToken.symbol(), "DAO");
        assertEq(governanceToken.totalSupply(), 1100000 * 10 ** 18); // Initial + minted to users
        assertEq(governanceToken.balanceOf(owner), INITIAL_SUPPLY); // Initial supply
    }

    function testTokenMinting() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.startPrank(owner);
        governanceToken.mint(user1, mintAmount);
        vm.stopPrank();

        assertEq(governanceToken.balanceOf(user1), 51000 * 10 ** 18); // 50000 + 1000
    }

    function testTokenBurning() public {
        uint256 burnAmount = 1000 * 10 ** 18;

        vm.startPrank(user1);
        governanceToken.burn(burnAmount);
        vm.stopPrank();

        assertEq(governanceToken.balanceOf(user1), 49000 * 10 ** 18); // 50000 - 1000
    }

    function testVotingPowerDelegation() public {
        uint256 delegateAmount = 10000 * 10 ** 18;

        vm.startPrank(user1);
        governanceToken.delegateVotingPower(delegate, delegateAmount);
        vm.stopPrank();

        assertEq(governanceToken.getVotingPower(delegate), delegateAmount);
        assertEq(governanceToken.getVotingPower(user1), 40000 * 10 ** 18); // 50000 - 10000
        assertTrue(governanceToken.hasDelegated(user1));
        assertEq(governanceToken.delegates(user1), delegate);
    }

    function testVotingPowerUndelegation() public {
        uint256 delegateAmount = 10000 * 10 ** 18;

        // First delegate
        vm.startPrank(user1);
        governanceToken.delegateVotingPower(delegate, delegateAmount);

        // Then undelegate
        governanceToken.undelegateVotingPower(5000 * 10 ** 18);
        vm.stopPrank();

        assertEq(governanceToken.getVotingPower(delegate), 5000 * 10 ** 18);
        assertEq(governanceToken.getVotingPower(user1), 45000 * 10 ** 18);
    }

    function test_RevertWhen_DelegationToZeroAddress() public {
        vm.startPrank(user1);
        vm.expectRevert("Cannot delegate to zero address");
        governanceToken.delegateVotingPower(address(0), 1000 * 10 ** 18);
        vm.stopPrank();
    }

    function test_RevertWhen_DelegationToSelf() public {
        vm.startPrank(user1);
        vm.expectRevert("Cannot delegate to self");
        governanceToken.delegateVotingPower(user1, 1000 * 10 ** 18);
        vm.stopPrank();
    }

    function test_RevertWhen_DelegationZeroAmount() public {
        vm.startPrank(user1);
        vm.expectRevert("Amount must be greater than 0");
        governanceToken.delegateVotingPower(delegate, 0);
        vm.stopPrank();
    }

    function test_RevertWhen_DelegationInsufficientBalance() public {
        vm.startPrank(user1);
        vm.expectRevert("Insufficient balance");
        governanceToken.delegateVotingPower(delegate, 50001 * 10 ** 18);
        vm.stopPrank();
    }

    function test_RevertWhen_UndelegationWithoutDelegation() public {
        vm.startPrank(user1);
        vm.expectRevert("No delegation found");
        governanceToken.undelegateVotingPower(1);
        vm.stopPrank();
    }

    // ============ DAO Tests ============

    function testProposalCreation() public {
        string memory description = "Test proposal for funding";

        vm.startPrank(user1);
        uint256 proposalId = createTestProposal(description);
        vm.stopPrank();

        assertEq(proposalId, 0);
        assertEq(dao.proposalCount(), 1);

        (address proposer, string memory desc,,, uint256 startTime, uint256 endTime, bool executed, bool canceled,,,) =
            dao.getProposal(0);
        assertEq(proposer, user1);
        assertEq(desc, description);
        assertEq(startTime, block.timestamp);
        assertEq(endTime, block.timestamp + VOTING_PERIOD);
        assertFalse(executed);
        assertFalse(canceled);
    }

    function test_RevertWhen_ProposalCreationInsufficientTokens() public {
        address lowPowerUser = address(100);
        vm.startPrank(lowPowerUser);
        vm.expectRevert("Insufficient voting power to create proposal");
        createTestProposal("Test proposal");
        vm.stopPrank();
    }

    function test_RevertWhen_ProposalCreationEmptyDescription() public {
        vm.startPrank(user1);
        vm.expectRevert("Description cannot be empty");
        dao.createProposal("", user1, 1 ether, address(0));
        vm.stopPrank();
    }

    function test_RevertWhen_ProposalCreationRecipientZero() public {
        vm.startPrank(user1);
        vm.expectRevert("Invalid recipient address");
        dao.createProposal("desc", address(0), 1 ether, address(0));
        vm.stopPrank();
    }

    function test_RevertWhen_ProposalCreationAmountZero() public {
        vm.startPrank(user1);
        vm.expectRevert("Amount must be greater than 0");
        dao.createProposal("desc", user1, 0, address(0));
        vm.stopPrank();
    }

    function testVoting() public {
        // Create proposal

        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        // Vote for the proposal

        vm.startPrank(user2);
        dao.vote(proposalId, true);
        vm.stopPrank();

        // Vote against the proposal

        vm.startPrank(user3);
        dao.vote(proposalId, false);
        vm.stopPrank();

        (,, uint256 forVotes, uint256 againstVotes,,, bool executed, bool canceled,,,) = dao.getProposal(proposalId);
        assertEq(forVotes, 30000 * 10 ** 18); // user2's voting power
        assertEq(againstVotes, 20000 * 10 ** 18); // user3's voting power
        assertFalse(executed);
        assertFalse(canceled);
    }

    function test_RevertWhen_VoteProposalDoesNotExist() public {
        vm.startPrank(user2);
        vm.expectRevert("Proposal does not exist");
        dao.vote(999, true);
        vm.stopPrank();
    }

    function test_RevertWhen_VoteAfterVotingEnded() public {
        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        vm.warp(block.timestamp + VOTING_PERIOD);

        vm.startPrank(user2);
        vm.expectRevert("Voting ended");
        dao.vote(proposalId, true);
        vm.stopPrank();
    }

    function test_RevertWhen_VoteWithNoVotingPower() public {
        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        address noPowerUser = address(101);
        vm.startPrank(noPowerUser);
        vm.expectRevert("No voting power");
        dao.vote(proposalId, true);
        vm.stopPrank();
    }

    function test_RevertWhen_VoteOnCanceledProposal() public {
        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        dao.cancelProposal(proposalId);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert("Proposal is canceled");
        dao.vote(proposalId, true);
        vm.stopPrank();
    }

    function test_RevertWhen_ProposalExecutionBeforeVotingEnds() public {
        // Create proposal

        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        // Try to execute before voting ends

        vm.expectRevert("Voting not ended");
        dao.executeProposal(proposalId);
    }

    function test_RevertWhen_ProposalExecutionInsufficientQuorum() public {
        vm.startPrank(owner);
        dao.updateConfiguration(PROPOSAL_THRESHOLD, VOTING_PERIOD, 60000 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        vm.startPrank(user3);
        dao.vote(proposalId, true);
        vm.stopPrank();

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        vm.startPrank(user1);
        vm.expectRevert("Quorum not reached");
        dao.executeProposal(proposalId);
        vm.stopPrank();
    }

    function test_RevertWhen_ProposalExecutionNotPassed() public {
        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        vm.startPrank(user2);
        dao.vote(proposalId, false);
        vm.stopPrank();

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        vm.startPrank(user1);
        vm.expectRevert("Proposal not passed");
        dao.executeProposal(proposalId);
        vm.stopPrank();
    }

    function test_RevertWhen_ProposalExecutionTreasuryInsufficientEth() public {
        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        vm.startPrank(user2);
        dao.vote(proposalId, true);
        vm.stopPrank();

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        vm.startPrank(user1);
        vm.expectRevert("Insufficient ETH balance");
        dao.executeProposal(proposalId);
        vm.stopPrank();
    }

    function testProposalCancellation() public {
        // Create proposal

        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        dao.cancelProposal(proposalId);
        vm.stopPrank();

        (,,,,,,, bool canceled,,,) = dao.getProposal(proposalId);
        assertTrue(canceled);
    }

    function test_RevertWhen_ProposalCancellationTwice() public {
        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        dao.cancelProposal(proposalId);
        vm.expectRevert("Proposal already canceled");
        dao.cancelProposal(proposalId);
        vm.stopPrank();
    }

    function test_RevertWhen_ProposalCancellationAfterExecuted() public {
        uint256 fundingAmount = 10 ether;
        vm.deal(user1, fundingAmount);
        vm.startPrank(user1);
        treasury.fundTreasury{value: fundingAmount}();
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        vm.startPrank(user2);
        dao.vote(proposalId, true);
        vm.stopPrank();

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        vm.startPrank(user1);
        dao.executeProposal(proposalId);
        vm.expectRevert("Proposal already executed");
        dao.cancelProposal(proposalId);
        vm.stopPrank();
    }

    function test_RevertWhen_ProposalCancellationByUnauthorized() public {
        // Create proposal

        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        // Try to cancel by unauthorized user

        vm.startPrank(user2);
        vm.expectRevert("Not authorized to cancel");
        dao.cancelProposal(proposalId);
        vm.stopPrank();
    }

    // ============ Treasury Tests ============

    function testTreasuryFunding() public {
        uint256 fundingAmount = 10 ether;

        vm.deal(user1, fundingAmount);
        vm.startPrank(user1);
        treasury.fundTreasury{value: fundingAmount}();
        vm.stopPrank();

        assertEq(treasury.getBalance(address(0)), fundingAmount);
    }

    function test_RevertWhen_TreasuryFundingZeroValue() public {
        vm.startPrank(user1);
        vm.expectRevert("Must send ETH");
        treasury.fundTreasury{value: 0}();
        vm.stopPrank();
    }

    function testTreasuryTokenFunding() public {
        uint256 fundingAmount = 1000 * 10 ** 18;

        vm.startPrank(user1);
        governanceToken.approve(address(treasury), fundingAmount);
        treasury.fundTreasuryWithToken(address(governanceToken), fundingAmount);
        vm.stopPrank();

        assertEq(treasury.getBalance(address(governanceToken)), fundingAmount);
    }

    function testProposalApproval() public {
        vm.startPrank(address(dao));
        treasury.approveProposal(1);
        vm.stopPrank();

        assertTrue(treasury.isProposalApproved(1));
    }

    function test_RevertWhen_ProposalApprovalTwice() public {
        vm.startPrank(address(dao));
        treasury.approveProposal(1);
        vm.expectRevert("Proposal already approved");
        treasury.approveProposal(1);
        vm.stopPrank();
    }

    function test_RevertWhen_ProposalApprovalByUnauthorized() public {
        vm.startPrank(user1);
        vm.expectRevert("Only DAO can approve proposals");
        treasury.approveProposal(1);
        vm.stopPrank();
    }

    function testFundSpending() public {
        uint256 fundingAmount = 10 ether;
        uint256 spendingAmount = 5 ether;

        // Fund treasury
        vm.deal(user1, fundingAmount);
        vm.startPrank(user1);
        treasury.fundTreasury{value: fundingAmount}();
        vm.stopPrank();

        // Approve proposal
        vm.startPrank(address(dao));
        treasury.approveProposal(1);

        // Spend funds
        treasury.spendFunds(1, user2, spendingAmount, address(0));
        vm.stopPrank();

        assertEq(treasury.getBalance(address(0)), fundingAmount - spendingAmount);
        assertEq(user2.balance, spendingAmount);
        assertTrue(treasury.isProposalExecuted(1));
    }

    function test_RevertWhen_FundSpendingWithoutApproval() public {
        vm.startPrank(address(dao));
        vm.expectRevert("Proposal not approved");
        treasury.spendFunds(1, user2, 1 ether, address(0));
        vm.stopPrank();
    }

    function test_RevertWhen_FundSpendingByUnauthorized() public {
        vm.startPrank(user1);
        vm.expectRevert("Only DAO can spend funds");
        treasury.spendFunds(1, user2, 1 ether, address(0));
        vm.stopPrank();
    }

    function test_RevertWhen_FundSpendingTwice() public {
        uint256 fundingAmount = 10 ether;
        uint256 spendingAmount = 5 ether;

        // Fund treasury
        vm.deal(user1, fundingAmount);
        vm.startPrank(user1);
        treasury.fundTreasury{value: fundingAmount}();
        vm.stopPrank();

        vm.startPrank(address(dao));
        treasury.approveProposal(1);
        treasury.spendFunds(1, user2, spendingAmount, address(0));
        vm.expectRevert("Proposal already executed");
        treasury.spendFunds(1, user2, spendingAmount, address(0));
        vm.stopPrank();
    }

    function testEmergencyWithdraw() public {
        uint256 fundingAmount = 10 ether;

        // Fund treasury
        vm.deal(user1, fundingAmount);
        vm.startPrank(user1);
        treasury.fundTreasury{value: fundingAmount}();
        vm.stopPrank();

        // Emergency withdraw
        vm.startPrank(owner);
        treasury.emergencyWithdraw(address(0), fundingAmount, user2);
        vm.stopPrank();

        assertEq(treasury.getBalance(address(0)), 0);
        assertEq(user2.balance, fundingAmount);
    }

    // ============ Integration Tests ============

    function testCompleteDAOWorkflow() public {
        // Fund treasury with ETH first
        uint256 fundingAmount = 10 ether;
        vm.deal(user1, fundingAmount);
        vm.startPrank(user1);
        treasury.fundTreasury{value: fundingAmount}();
        vm.stopPrank();

        // 1. Delegate voting power
        vm.startPrank(user1);
        governanceToken.delegateVotingPower(delegate, 20000 * 10 ** 18);
        vm.stopPrank();

        // 2. Create proposal
        vm.startPrank(delegate);
        uint256 proposalId = dao.createProposal(
            "Fund project development",
            user1, // recipient
            1 ether, // amount: 1 ETH
            address(0) // token: ETH
        );
        vm.stopPrank();

        // 3. Vote on proposal
        vm.startPrank(user2);
        dao.vote(proposalId, true);
        vm.stopPrank();

        vm.startPrank(user3);
        dao.vote(proposalId, false);
        vm.stopPrank();

        // 4. Fast forward and execute
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        vm.startPrank(delegate);
        dao.executeProposal(proposalId);
        vm.stopPrank();

        // 5. Verify execution
        (,,,,,, bool executed,,,,) = dao.getProposal(proposalId);
        assertTrue(executed);
    }

    function testConfigurationUpdate() public {
        uint256 newThreshold = 2000 * 10 ** 18;
        uint256 newVotingPeriod = 14 days;
        uint256 newQuorum = 20000 * 10 ** 18;

        vm.startPrank(owner);
        dao.updateConfiguration(newThreshold, newVotingPeriod, newQuorum);
        vm.stopPrank();

        assertEq(dao.proposalThreshold(), newThreshold);
        assertEq(dao.votingPeriod(), newVotingPeriod);
        assertEq(dao.quorumVotes(), newQuorum);
    }
}
