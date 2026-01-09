// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./DAO.sol";

/**
 * @title DAOTreasury
 * @dev Treasury contract for managing DAO funds
 * Allows spending based on approved proposals
 */
contract DAOTreasury is Ownable {
    // DAO contract reference
    DAO public dao;

    // Mapping to track approved spending proposals
    mapping(uint256 => bool) public approvedProposals;

    // Mapping to track executed spending proposals
    mapping(uint256 => bool) public executedProposals;

    // Events
    event ProposalApproved(uint256 indexed proposalId);
    event FundsSpent(uint256 indexed proposalId, address indexed recipient, uint256 amount, address token);
    event TreasuryFunded(address indexed sender, uint256 amount);
    event DAOSet(address indexed dao);

    /**
     * @dev Constructor
     * @param _dao Address of the DAO contract
     */
    constructor(address _dao) Ownable(msg.sender) {
        dao = DAO(_dao);
    }

    /**
     * @dev Set the DAO contract address (only owner)
     * @param _dao New DAO contract address
     */
    function setDAO(address _dao) external onlyOwner {
        require(_dao != address(0), "Invalid DAO address");
        dao = DAO(_dao);
        emit DAOSet(_dao);
    }

    /**
     * @dev Approve a proposal for spending (only DAO)
     * @param proposalId ID of the proposal to approve
     */
    function approveProposal(uint256 proposalId) external {
        require(msg.sender == address(dao), "Only DAO can approve proposals");
        require(!approvedProposals[proposalId], "Proposal already approved");

        approvedProposals[proposalId] = true;
        emit ProposalApproved(proposalId);
    }

    /**
     * @dev Spend funds based on an approved proposal
     * @param proposalId ID of the approved proposal
     * @param recipient Address to send funds to
     * @param amount Amount to send
     * @param token Token address (address(0) for ETH)
     */
    function spendFunds(uint256 proposalId, address recipient, uint256 amount, address token) external {
        require(msg.sender == address(dao), "Only DAO can spend funds");
        require(approvedProposals[proposalId], "Proposal not approved");
        require(!executedProposals[proposalId], "Proposal already executed");
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be greater than 0");

        executedProposals[proposalId] = true;

        if (token == address(0)) {
            // Send ETH
            require(address(this).balance >= amount, "Insufficient ETH balance");
            (bool success,) = recipient.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // Send ERC20 token
            IERC20 tokenContract = IERC20(token);
            require(tokenContract.balanceOf(address(this)) >= amount, "Insufficient token balance");
            require(tokenContract.transfer(recipient, amount), "Token transfer failed");
        }

        emit FundsSpent(proposalId, recipient, amount, token);
    }

    /**
     * @dev Fund the treasury with ETH
     */
    function fundTreasury() external payable {
        require(msg.value > 0, "Must send ETH");
        emit TreasuryFunded(msg.sender, msg.value);
    }

    /**
     * @dev Fund the treasury with ERC20 tokens
     * @param token Token address
     * @param amount Amount to fund
     */
    function fundTreasuryWithToken(address token, uint256 amount) external {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than 0");

        IERC20 tokenContract = IERC20(token);
        require(tokenContract.transferFrom(msg.sender, address(this), amount), "Token transfer failed");

        emit TreasuryFunded(msg.sender, amount);
    }

    /**
     * @dev Get treasury balance for a specific token
     * @param token Token address (address(0) for ETH)
     * @return balance Current balance
     */
    function getBalance(address token) external view returns (uint256 balance) {
        if (token == address(0)) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    /**
     * @dev Check if a proposal is approved
     * @param proposalId ID of the proposal
     * @return approved Whether the proposal is approved
     */
    function isProposalApproved(uint256 proposalId) external view returns (bool approved) {
        return approvedProposals[proposalId];
    }

    /**
     * @dev Check if a proposal has been executed
     * @param proposalId ID of the proposal
     * @return executed Whether the proposal has been executed
     */
    function isProposalExecuted(uint256 proposalId) external view returns (bool executed) {
        return executedProposals[proposalId];
    }

    /**
     * @dev Emergency withdrawal (only owner)
     * @param token Token address (address(0) for ETH)
     * @param amount Amount to withdraw
     * @param recipient Address to send funds to
     */
    function emergencyWithdraw(address token, uint256 amount, address recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be greater than 0");

        if (token == address(0)) {
            require(address(this).balance >= amount, "Insufficient ETH balance");
            (bool success,) = recipient.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20 tokenContract = IERC20(token);
            require(tokenContract.balanceOf(address(this)) >= amount, "Insufficient token balance");
            require(tokenContract.transfer(recipient, amount), "Token transfer failed");
        }
    }

    // Allow the contract to receive ETH
    receive() external payable {
        emit TreasuryFunded(msg.sender, msg.value);
    }
}
