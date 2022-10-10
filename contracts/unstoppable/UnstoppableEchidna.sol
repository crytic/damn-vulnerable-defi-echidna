pragma solidity ^0.8.0;

import "../DamnValuableToken.sol";
import "./UnstoppableLender.sol";
import "./ReceiverUnstoppable.sol";

/// @dev To run this contract: $ npx hardhat clean && npx hardhat compile --force && echidna-test . --contract UnstoppableEchidna --config contracts/unstoppable/config.yaml
contract UnstoppableEchidna {
    // We will send ETHER_IN_POOL to the flash loan pool.
    uint256 constant ETHER_IN_POOL = 1000000e18;
    // We will send INITIAL_ATTACKER_BALANCE to the attacker (which is the deployer) of this contract.
    uint256 constant INITIAL_ATTACKER_BALANCE = 100e18;

    DamnValuableToken token;
    UnstoppableLender pool;

    // Setup echidna test by deploying the flash loan pool, approving it for token transfers, sending it tokens, and sending the attacker some tokens.
    constructor() public payable {
	// Complete me
    }

    // There is a callback mechanism that is missing from this contract

    // This is the Echidna property entrypoint.
    // We want to test whether flash loans can always be made.
    function echidna_testFlashLoan() public returns (bool) {
	// Complete me
    }
}
