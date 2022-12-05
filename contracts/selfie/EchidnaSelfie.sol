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

    uint256[] private actionIds; // to track id of queued actions
    uint256 private actionIdCounter; // to load proper actionId in executeAction()

    uint256[] private callbackActionsToBeCalled; // actions to be called in callback function

    // all possible actions for callback
    enum CallbackActions {
        drainAllFunds,
        transferFrom,
        queueAction,
        executeAction
    }
    uint256 private callbackActionsLength = 4; // must correspond with the length of Actions

    // queueAction payload types to be created by Echidna
    enum PayloadTypesInQueueAction {
        noPayloadSet, // only for logging purposes
        drainAllFunds,
        transferFrom
    }
    uint256 private payloadsLength = 3; // must correspond with the length of Payloads

    struct Payload {
        uint256 payloadIdentifier; // setPayload -> logging purposes
        bytes payload; // setPayload
        address receiver; // setPayload
        uint256 weiAmount; // push
        uint256 transferAmount; // setPayload -> used only if payloadIdentifier == uint256(PayloadTypesInQueueAction.transferFrom)
    }
    // internal counter to payload created
    mapping(uint256 => Payload) payloads;

    uint256 private payloadsPushedCounter; // counter of payloads created
    uint256 private payloadsQueuedCounter; // counter of payloads queued
    uint256 private payloadsExecutedCounter; // counter of payloads executed via callbacks
    uint256 private payloadsEventsCounter; // logging purposes

    uint256[] private _transferAmountInCallback; // amount for transferFrom called in callback function
    uint256 private _transferAmountInCallbackCounter; // counter of the
    uint256 private _transferAmountInCallbackTrackerCounter; // used only for logging purposes

    SelfiePool pool;
    SimpleGovernance governance;
    DamnValuableTokenSnapshot token;

    // EVENTS
    event ActionCalledInCallback(string action); // to track which actions has been called in callback
    event AssertionFailed(string reason);
    event QueueActionPayloadSetTo(string payload);
    event QueueActionVariable(string name, uint256 variable);
    event CallbackVariable(string name, uint256 variable);

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
        uint256 genArrLength = callbackActionsToBeCalled.length;
        if (genArrLength != 0) {
            for (uint256 i; i < genArrLength; i++) {
                callAction(callbackActionsToBeCalled[i]);
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
            callbackQueueAction();
        }
        // execute an action
        if (_num == uint256(CallbackActions.executeAction)) {
            try this.executeAction() {} catch {
                revert("queueAction unsuccessful");
            }
        }
    }

    /////////////
    // ACTIONS //
    /////////////

    ////////////////////////
    // 1: drainAllFunds() //
    function drainAllFunds() public {
        pool.drainAllFunds(address(this));
    }

    function pushDrainAllFundsToCallback() external {
        callbackActionsToBeCalled.push(uint256(CallbackActions.drainAllFunds));
    }

    ///////////////////////
    // 2: transferFrom() //
    function transferFrom(uint256 _amount) public {
        require(_amount > 0, "Cannot transfer zero tokens");
        token.transferFrom(address(pool), address(this), _amount);
    }

    function callbackTransferFrom() internal {
        // get the amount of tokens to be transfered
        uint256 _amount = _transferAmountInCallback[
            _transferAmountInCallbackCounter
        ];
        // increase the counter
        ++_transferAmountInCallbackCounter;
        // call the transfer function
        transferFrom(_amount);
    }

    function pushTransferFromToCallback(uint256 _amount) external {
        require(_amount > 0, "Cannot transfer zero tokens");
        _transferAmountInCallback.push(_amount);
        callbackActionsToBeCalled.push(uint256(CallbackActions.transferFrom));
    }

    //////////////////////
    // 3: queueAction() //

    function callbackQueueAction() internal {
        try this.callQueueAction() {} catch {}
        // no matter the output of the action queued, increase the counter to be able
        // to iterate over all payloads created for queueActions() in callback
        ++payloadsQueuedCounter;
    }

    /**
     * @dev this function is filtered out for direct calls by Echidna (see ./config.yaml)
     */
    function callQueueAction() public {
        require(
            msg.sender == address(this),
            "Only this contract can call queueAction"
        );
        // cache the counter
        uint256 counter = payloadsQueuedCounter;
        // get queueAction parameters based on counter choosen
        uint256 _weiAmount = payloads[counter].weiAmount;
        require(
            address(this).balance >= _weiAmount,
            "Not sufficient account balance to queue an action"
        );
        address _receiver = payloads[counter].receiver;
        bytes memory _payload = payloads[counter].payload;
        // call queueAction
        queueAction(_receiver, _payload, _weiAmount);
    }

    function queueAction(
        address _receiver,
        bytes memory _payload,
        uint256 _weiAmount
    ) internal {
        // take a snaphost first as it is needed in queueAction()
        token.snapshot();
        // queue the action
        uint256 actionId = governance.queueAction(
            _receiver,
            _payload,
            _weiAmount
        );
        // store actionIds
        actionIds.push(actionId);
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
        if (_payloadNum == uint256(PayloadTypesInQueueAction.transferFrom)) {
            require(_amountToTransfer > 0, "Cannot transfer 0 tokens");
        }
        // Add the action into callback array
        callbackActionsToBeCalled.push(uint256(CallbackActions.queueAction));
        // update payloads mapping
        payloads[payloadsPushedCounter].weiAmount = _weiAmount;
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
        // cache counter
        uint256 _counter = payloadsPushedCounter;
        // store payload identifier
        payloads[_counter].payloadIdentifier = _payloadNum;
        // create payload of drainAllFunds
        bytes memory _payload;
        address _receiver;
        if (_payloadNum == uint256(PayloadTypesInQueueAction.drainAllFunds)) {
            _payload = abi.encodeWithSignature(
                "drainAllFunds(address)",
                address(this)
            );
            _receiver = address(pool);
        }
        // create payload of transfer
        if (_payloadNum == uint256(PayloadTypesInQueueAction.transferFrom)) {
            // _transferAmountInPayload.push(_amountToTransfer);
            _payload = abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                address(pool),
                address(this),
                _amountToTransfer
            );
            _receiver = address(token);
            // store amount to transfer
            payloads[_counter].transferAmount = _amountToTransfer;
        }
        // fill payload mapping
        payloads[_counter].payload = _payload;
        payloads[_counter].receiver = _receiver;
        // increase payload counter
        ++payloadsPushedCounter;
    }

    ////////////////////////
    // 4: executeAction() //
    function executeAction() public {
        // get the first unexecuted actionId
        uint256 actionId = actionIds[actionIdCounter];
        // increase action Id counter
        actionIdCounter = actionIdCounter + 1;
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
        // increase counter of payloads executed
        ++payloadsExecutedCounter;
    }

    function pushExecuteActionToCallback() external {
        callbackActionsToBeCalled.push(uint256(CallbackActions.executeAction));
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
            uint256 _counter = payloadsEventsCounter;
            if (_counter < payloadsExecutedCounter + 1) {
                //
                emitQueueActionDetails(_counter);
            }
            ++payloadsEventsCounter;
        }
        if (_actionNumber == uint256(CallbackActions.executeAction)) {
            emit ActionCalledInCallback("executeAction()");
        }
        if (_actionNumber == uint256(CallbackActions.drainAllFunds)) {
            emit ActionCalledInCallback("drainAllFunds()");
        }
        if (_actionNumber == uint256(CallbackActions.transferFrom)) {
            emit ActionCalledInCallback("transferFrom()");
            uint256 _transferedAmout = _transferAmountInCallback[
                _transferAmountInCallbackTrackerCounter
            ];
            ++_transferAmountInCallbackTrackerCounter;
            emit CallbackVariable("_transferedAmout: ", _transferedAmout);
        }
    }

    /**
     * @notice emit event of a payload created in queueAction()
     */
    function emitQueueActionDetails(uint256 _payloadNumber) internal {
        // cache data
        Payload memory _payload = payloads[_payloadNumber];
        uint256 _weiAmount = _payload.weiAmount;
        uint256 _payloadId = _payload.payloadIdentifier;
        uint256 _transferAmount = _payload.transferAmount;
        // emit events
        if (_payloadId == uint256(PayloadTypesInQueueAction.drainAllFunds)) {
            emit QueueActionPayloadSetTo("drainAllFunds(address)");
            emit QueueActionVariable(
                "PARAMETER `_transferAmount` NOT USED",
                _transferAmount
            );
        }
        if (_payloadId == uint256(PayloadTypesInQueueAction.transferFrom)) {
            emit QueueActionPayloadSetTo(
                "transferFrom(address,address,uint256)"
            );
            emit QueueActionVariable(
                "_transferAmount",
                _payload.transferAmount
            );
        }
        emit QueueActionVariable("_weiAmount", _weiAmount);
    }

    ////////////////
    // INVARIANTS //
    ////////////////

    // GENERAL: Can we drain SelfiePool?

    function checkPoolBalance() external {
        try this._checkPoolBalance() {
            // pool balance has not changed
        } catch {
            uint256 actionsArrLength = callbackActionsToBeCalled.length;
            for (uint256 i; i < actionsArrLength; i++) {
                emitActionExecuted(callbackActionsToBeCalled[i]);
            }
            // emit assertion violation
            emit AssertionFailed("Invariant broken");
        }
    }
}
