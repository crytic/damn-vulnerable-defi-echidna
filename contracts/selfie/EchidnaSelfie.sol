// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./SelfiePool.sol";
import "./SimpleGovernance.sol";
import "../DamnValuableTokenSnapshot.sol";

/**
 * @notice to run echidna use following command:
 * npx hardhat clean && npx hardhat compile --force && echidna-test . --contract EchidnaSelfie --config ./selfie.yaml
 */

// the SelfieDeployment contract is used to set fuzzing environment (to deploy all necessary contracts)
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
        // return all necessary contracts
        return (pool, governance, token);
    }
}

contract EchidnaSelfie {
    uint256 private ACTION_DELAY_IN_SECONDS = 2 days;
    uint256 private TOKENS_IN_POOL = 1_500_000 ether;

    uint256 actionId; // to tract id of queued actions
    uint256 timestampOfActionQueued; // to track timestamp of queued actions

    uint256[] public actionsToBeCalled; // actions to be called in callback function

    enum Actions {
        drainAllFunds,
        transferFrom,
        queueAction,
        executeAction
    }
    uint256 actionsLength = 4; // must correspond with the length of Actions

    SelfiePool pool;
    SimpleGovernance governance;
    DamnValuableTokenSnapshot token;

    event ActionCalledInCallback(string action); // to track which actions has been called in callback
    event AssertionFailed(string reason);

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

    /**
     * @notice a callback to be called by pool once flashloan is taken
     * @param _amount amount of tokens to borrow
     */
    function receiveTokens(address, uint256 _amount) external {
        require(
            msg.sender == address(pool),
            "Only SelfiePool can call this function."
        );
        // logic
        callbackActions();
        // repay the loan
        require(token.transfer(address(pool), _amount), "Flash loan failed");
    }

    /**
     * @notice Echidna populates actionsToBeCalled by a numbers representing functions
     * to be called during callback in receiveTokens()
     * @param num a number represing a function to be called
     */
    function pushActionToCallback(uint256 num) external {
        num = num % actionsLength;
        actionsToBeCalled.push(num);
    }

    /**
     * @notice an action to be called
     * @param _num a number representing the action to be called
     */
    function callAction(uint256 _num) internal {
        require(0 <= _num && _num < actionsLength, "Out of range");
        // drain all funds
        if (_num == uint256(Actions.drainAllFunds)) {
            drainAllFunds();
        }
        // transfer
        if (_num == uint256(Actions.transferFrom)) {
            transferFrom();
        }
        // queue an action
        if (_num == uint256(Actions.queueAction)) {
            try this.queueAction() {} catch {
                revert("queueAction unsuccessful");
            }
        }
        // execute an action
        if (_num == uint256(Actions.executeAction)) {
            try this.executeAction() {} catch {
                revert("queueAction unsuccessful");
            }
        }
    }

    /**
     * @notice actions to be called once receiveTokens() is called
     */
    function callbackActions() internal {
        uint256 genArrLength = actionsToBeCalled.length;
        if (genArrLength != 0) {
            for (uint256 i; i < genArrLength - 1; i++) {
                callAction(actionsToBeCalled[i]);
            }
        } else {
            revert("actionsToBeCalled is empty, no action called");
        }
    }

    function queueAction() public {
        // create payload
        bytes memory payload = abi.encodeWithSignature(
            "drainAllFunds(address)",
            address(this)
        );
        // take a snaphost first as it is needed in queueAction()
        token.snapshot();
        // queue the action
        actionId = governance.queueAction(address(pool), payload, 0);
        // set timestamp when action was queued (needed to pass the requirement in the executeAction)
        timestampOfActionQueued = block.timestamp;
    }

    function executeAction() public {
        // it does not make sense to call executeAction if the requirment is not met
        require(
            block.timestamp >= timestampOfActionQueued + ACTION_DELAY_IN_SECONDS,
            "Time for action execution has not passed yet"
        );
        governance.executeAction(actionId);
    }

    /**
     * @notice this function should always revert as we should not be able
     * to drain all funds from pool
     */
    function drainAllFunds() public {
        uint256 _poolBalance = token.balanceOf(address(pool));
        pool.drainAllFunds(address(this));
        uint256 _poolBalanceAfter = token.balanceOf(address(pool));
        require(
            _poolBalanceAfter > _poolBalance,
            "Draining all funds has been unsuccessful"
        );
    }

    /**
     * @notice this function should always revert as we should not be able
     * to transfer token from pool
     */
    function transferFrom() public {
        uint256 _poolBalance = token.balanceOf(address(pool));
        token.transferFrom(address(pool), address(this), _poolBalance);
        uint256 _poolBalanceAfter = token.balanceOf(address(pool));
        require(_poolBalanceAfter > _poolBalance, "Transfer unsuccessful");
    }

    /////////////
    // HELPERS //
    /////////////

    /**
     * @notice check if a balance of DVT in pool has changed;
     */
    function _checkPoolBalance() external view returns (bool) {
        if (token.balanceOf(address(pool)) == TOKENS_IN_POOL) {
            return true;
        } else {
            revert("Invariant broken");
        }
    }

    /**
     * @notice emit event of an action executed in callback, i.e. once receiveTokens() is called
     * @param _actionNumber a number of action executed
     */
    function emitActionExecuted(uint256 _actionNumber) internal {
        if (_actionNumber == uint256(Actions.queueAction)) {
            emit ActionCalledInCallback("queueAction()");
        }
        if (_actionNumber == uint256(Actions.executeAction)) {
            emit ActionCalledInCallback("executeAction()");
        }
        if (_actionNumber == uint256(Actions.drainAllFunds)) {
            emit ActionCalledInCallback("drainAllFunds()");
        }
        if (_actionNumber == uint256(Actions.transferFrom)) {
            emit ActionCalledInCallback("transferFrom()");
        }
    }

    ////////////////
    // INVARIANTS //
    ////////////////

    // GENERAL: Can we drain SelfiePool?

    function checkPoolBalance() external {
        try this._checkPoolBalance() {
            // pool balance has not changed
        } catch {
            // log actions called via events to be able to track them
            for (uint256 i; i < actionsToBeCalled.length; i++) {
                emitActionExecuted(actionsToBeCalled[i]);
            }
            emit AssertionFailed("Invariant broken");
        }
    }
}
