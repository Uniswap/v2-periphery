pragma solidity =0.6.6;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/contracts/libraries/Babylonian.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";

import "./interfaces/IUniswapV2Router01.sol";
import "./libraries/SafeMath.sol";
import "./libraries/UniswapV2Library.sol";

// enables adding and removing liquidity with a single token to/from a pair
// adds liquidity via a single token of the pair, by first swapping against the pair and then adding liquidity
// removes liquidity in a single token, by removing liquidity and then immediately swapping
contract ExampleCombinedSwapAddRemoveLiquidity {
    using SafeMath for uint;

    IUniswapV2Factory public /*immutable*/ factory;
    IUniswapV2Router01 public /*immutable*/ router;

    constructor(IUniswapV2Factory factory_, IUniswapV2Router01 router_) public {
        factory = factory_;
        router = router_;
    }

    // returns the amount of token that should be swapped in such that the ratio of reserve and reserveOther is equivalent
    // to the user's x/y after the swap
    function calculateSwapInAmount(uint reserve, uint userIn) internal pure returns (uint) {
        return Babylonian.sqrt(reserve.mul(userIn.mul(3988000) + reserve.mul(3988009))).sub(reserve.mul(1997)) / 1994;
    }

    // computes the exact amount of tokens that should be swapped before adding liquidity for a given token
    // does the swap and then adds liquidity
    // minOtherToken should be set to the minimum intermediate amount of token1 that should be received to prevent
    // slippage and front running
    // liquidity provider tokens are sent to the to address
    function swapExactTokensAndAddLiquidity(
        address tokenIn, uint amountIn,
        address otherToken, uint minOtherToken,
        address to, uint deadline
    ) external returns (uint amountTokenIn, uint amountTokenOther, uint liquidity) {
        // compute how much we should swap in to match the ratio of tokenIn / otherToken
        uint swapAmount;
        {
            (uint reserveIn,) = UniswapV2Library.getReserves(address(factory), tokenIn, otherToken);
            swapAmount = calculateSwapInAmount(reserveIn, amountIn);
        }

        // take the full amount from the caller
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        // approve the full amount for the router as well, since we will be either swapping with it or adding liquidity.
        TransferHelper.safeApprove(tokenIn, address(router), amountIn);

        uint amountOtherAdd;
        {
            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = otherToken;

            amountOtherAdd = router.swapExactTokensForTokens(
                swapAmount,
                minOtherToken,
                path,
                address(this),
                deadline
            )[1];
        }

        // approve the other token for the add liquidity call
        TransferHelper.safeApprove(otherToken, address(router), amountOtherAdd);
        uint amountTokenInAdd = amountIn - swapAmount;

        // no need to check that we transferred everything because minimums == total balance of this contract
        return router.addLiquidity(
            tokenIn,
            otherToken,
        // desired amountA, amountB
            amountTokenInAdd,
            amountOtherAdd,
        // they are also the minimums
            amountTokenInAdd,
            amountOtherAdd,
            to,
            deadline
        );
    }

    // burn the liquidity and then swap one of the two tokens to the other
    // enforces that at least minDesiredTokenOut tokens are received from the combination of burn and swap
    function removeLiquidityAndSwapToToken(
        address undesiredToken,
        address desiredToken,
        uint liquidity,
        uint minDesiredTokenOut,
        address to, uint deadline
    ) external returns (uint amountTokenOut) {
        (uint amountInSwap, uint amountOutRemove) = router.removeLiquidity(
            undesiredToken,
            desiredToken,
            liquidity,
        // amount minimums are applied in the swap
            0,
            0,
        // contract must receive both tokens because we want to swap the undesired token
            address(this),
            deadline
        );

        // send the amount in that we received in the burn
        TransferHelper.safeTransfer(desiredToken, to, amountOutRemove);
        TransferHelper.safeApprove(undesiredToken, address(router), amountInSwap);

        address[] memory path = new address[](2);
        path[0] = undesiredToken;
        path[1] = desiredToken;

        uint amountOutSwap = router.swapExactTokensForTokens(
            amountInSwap,
        // we must get at least this much from the swap to meet the minAmountOut parameter
            minDesiredTokenOut > amountOutRemove ? minDesiredTokenOut - amountOutRemove : 0,
            path,
            to,
            deadline
        )[1];

        amountTokenOut = amountOutRemove + amountOutSwap;
    }
}
