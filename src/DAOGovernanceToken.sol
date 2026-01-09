// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DAOGovernanceToken
 * @dev ERC20 token used for DAO governance voting
 * This token represents voting power in the DAO
 */
contract DAOGovernanceToken is ERC20, Ownable {
    // Mapping to track if an address has been delegated voting power
    mapping(address => bool) public hasDelegated;

    // Mapping to track delegation of voting power
    mapping(address => address) public delegates;

    // Mapping to track delegated voting power
    mapping(address => uint256) public delegatedVotes;

    // Events
    event VotingPowerDelegated(address indexed delegator, address indexed delegate, uint256 amount);
    event VotingPowerUndelegated(address indexed delegator, address indexed delegate, uint256 amount);

    /**
     * @dev Constructor that gives msg.sender all of initial tokens
     * @param name Token name
     * @param symbol Token symbol
     * @param initialSupply Initial token supply
     */
    constructor(string memory name, string memory symbol, uint256 initialSupply)
        ERC20(name, symbol)
        Ownable(msg.sender)
    {
        _mint(msg.sender, initialSupply);
    }

    /**
     * @dev Delegate voting power to another address
     * @param delegate Address to delegate voting power to
     * @param amount Amount of tokens to delegate
     */
    function delegateVotingPower(address delegate, uint256 amount) external {
        require(delegate != address(0), "Cannot delegate to zero address");
        require(delegate != msg.sender, "Cannot delegate to self");
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        // Transfer tokens to delegate
        _transfer(msg.sender, delegate, amount);

        // Update delegation tracking
        delegates[msg.sender] = delegate;
        delegatedVotes[delegate] += amount;
        hasDelegated[msg.sender] = true;

        emit VotingPowerDelegated(msg.sender, delegate, amount);
    }

    /**
     * @dev Undelegate voting power from delegate
     * @param amount Amount of tokens to undelegate
     */
    function undelegateVotingPower(uint256 amount) external {
        require(hasDelegated[msg.sender], "No delegation found");
        require(amount > 0, "Amount must be greater than 0");
        require(delegatedVotes[delegates[msg.sender]] >= amount, "Insufficient delegated amount");

        address delegate = delegates[msg.sender];

        // Transfer tokens back from delegate
        _transfer(delegate, msg.sender, amount);

        // Update delegation tracking
        delegatedVotes[delegate] -= amount;

        // If all tokens are undelegated, remove delegation
        if (delegatedVotes[delegate] == 0) {
            hasDelegated[msg.sender] = false;
            delete delegates[msg.sender];
        }

        emit VotingPowerUndelegated(msg.sender, delegate, amount);
    }

    /**
     * @dev Get the voting power of an address (including delegated votes)
     * @param account Address to check voting power for
     * @return Total voting power
     */
    function getVotingPower(address account) external view returns (uint256) {
        return balanceOf(account);
    }

    /**
     * @dev Mint new tokens (only owner)
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Burn tokens from caller
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
