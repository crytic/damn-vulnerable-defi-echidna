pragma solidity ^0.8.0;

import "./NaiveReceiverLenderPool.sol";
import "./FlashLoanReceiver.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract NaiveReceiverEchidna {
    using Address for address payable;

    // We will send ETHER_IN_POOL to the flash loan pool.
    uint256 constant ETHER_IN_POOL = 1000e18;
    // We will send ETHER_IN_RECEIVER to the flash loan receiver.
    uint256 constant ETHER_IN_RECEIVER = 10e18;

    NaiveReceiverLenderPool pool;
    FlashLoanReceiver receiver;

    // Setup echidna test by deploying the flash loan pool and receiver and sending them some ether.
    constructor() payable {
	// complete me
    }

    // We want to test whether the balance of the receiver contract can be decreased.
    function echidna_test() public view returns (bool) {
	// complete me
    }
}
