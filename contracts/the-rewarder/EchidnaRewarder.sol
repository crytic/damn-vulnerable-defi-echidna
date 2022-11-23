// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./FlashLoanerPool.sol";
import "./RewardToken.sol";
import "./AccountingToken.sol";
import "./TheRewarderPool.sol";
import "../DamnValuableToken.sol";

/**
 * @notice to run echidna use following command:
 * npx hardhat clean && npx hardhat compile --force && echidna-test . --contract EchidnaRewarder --config ./the-rewarder.yaml
 */

// this contract is used to set fuzzing environment (to deploy all necessary contracts)
contract RewarderTaskDeployer {
    uint256 private TOKENS_IN_LENDER_POOL = 1_000_000 ether;
    uint256 private TOKENS_PER_USER = 100 ether;

    function deployPoolsAndToken()
        public
        payable
        returns (
            DamnValuableToken,
            FlashLoanerPool,
            TheRewarderPool
        )
    {
        // deploy DamnValuableToken
        DamnValuableToken token;
        token = new DamnValuableToken();
        // deploy FlashLoanerPool
        FlashLoanerPool pool;
        pool = new FlashLoanerPool(address(token));
        // add liquidity to FlashLoanerPool deployed
        token.transfer(address(pool), TOKENS_IN_LENDER_POOL);
        // deploy TheRewarderPool
        TheRewarderPool rewarder;
        rewarder = new TheRewarderPool(address(token));
        // deposit tokens to the rewarder pool (simulate a deposit of 4 users)
        token.approve(address(rewarder), TOKENS_PER_USER * 4);
        rewarder.deposit(TOKENS_PER_USER * 4);
        // return
        return (token, pool, rewarder);
    }
}

contract EchidnaRewarder {
    uint256 REWARDS_ROUND_MIN_DURATION = 5 days;
    uint256 flashLoanAmount;
    uint256 reward;

    FlashLoanerPool pool;
    TheRewarderPool rewarder;
    RewardToken rewardToken;
    DamnValuableToken damnValuableToken;

    bool private depositEnabled;
    bool private withdrawalEnabled;
    bool private rewardsDistributionEnabled;

    // set Echidna fuzzing env
    constructor() payable {
        RewarderTaskDeployer deployer = new RewarderTaskDeployer();
        (damnValuableToken, pool, rewarder) = deployer.deployPoolsAndToken();
        rewardToken = rewarder.rewardToken();
    }

    function receiveFlashLoan(uint256 amount) external {
        require(
            msg.sender == address(pool),
            "Only pool can call this function."
        );
        // call selected functions
        selectFunctionsToCallInCallback();
        // get max reward amount for checking the INVARIANT
        reward = rewardToken.balanceOf(address(this));
        // repay the loan
        damnValuableToken.transfer(address(pool), amount);
    }

    /**
     * @notice functions to be called in callback
     * @dev order must be defined by a user
     */
    function selectFunctionsToCallInCallback() internal {
        // deposit to the pool with prior approval
        if (depositEnabled) {
            damnValuableToken.approve(address(rewarder), flashLoanAmount);
            rewarder.deposit(flashLoanAmount);
        }
        // withdraw from the pool
        if (withdrawalEnabled) {
            rewarder.withdraw(flashLoanAmount);
        }
        // distribute rewards
        if (rewardsDistributionEnabled) {
            rewarder.distributeRewards();
        }
    }

    function setEnableDeposit(bool _enabled) external {
        depositEnabled = _enabled;
    }

    function setEnableWithdrawal(bool _enabled) external {
        withdrawalEnabled = _enabled;
    }

    function setRewardsDistributionEnabled(bool _enabled) external {
        rewardsDistributionEnabled = _enabled;
    }

    function flashLoan(uint256 _amount) public {
        uint256 lastRewardsTimestamp = rewarder.lastRecordedSnapshotTimestamp();
        require(
            block.timestamp >=
                lastRewardsTimestamp + REWARDS_ROUND_MIN_DURATION,
            "It is useless to call flashloan if no rewards can be taken as ETH is precious."
        );
        require(
            _amount <= damnValuableToken.balanceOf(address(pool)),
            "Cannot borrow more than it is in the pool."
        );
        // set _amount into storage to have the value available in selectFunctionsToCallInCallback()
        flashLoanAmount = _amount;
        // call flashloan
        pool.flashLoan(flashLoanAmount);
    }

    /**
     * @notice INVARIANT: one user cannot get almost all of rewards
     * (max reward is 100 per turnus)
     */
    function testRewards() public view {
        assert(reward < 99 ether);
    }
}
