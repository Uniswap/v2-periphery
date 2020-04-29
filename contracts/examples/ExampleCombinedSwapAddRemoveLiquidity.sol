pragma solidity =0.6.6;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/contracts/libraries/Babylonian.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";

import "../interfaces/IUniswapV2Router01.sol";
import "../interfaces/IWETH.sol";
import "../libraries/SafeMath.sol";
import "../libraries/UniswapV2Library.sol";

// enables adding and removing liquidity with a single token to/from a pair
// adds liquidity via a single token of the pair, by first swapping against the pair and then adding liquidity
// removes liquidity in a single token, by removing liquidity and then immediately swapping
contract ExampleCombinedSwapAddRemoveLiquidity {
    using SafeMath for uint;

    IUniswapV2Factory public immutable factory;
    IUniswapV2Router01 public immutable router;

    constructor(IUniswapV2Factory factory_, IUniswapV2Router01 router_) public {
        factory = factory_;
        router = router_;
    }

    // returns the amount of token that should be swapped in such that ratio of reserves in the pair is equivalent
    // to the swapper's ratio of tokens
    // note this depends only on the number of tokens the caller wishes to swap and the current reserves of that token,
    // and not the current reserves of the other token
    function calculateSwapInAmount(uint reserveIn, uint userIn) public pure returns (uint) {
        return Babylonian.sqrt(reserveIn.mul(userIn.mul(3988000) + reserveIn.mul(3988009))).sub(reserveIn.mul(1997)) / 1994;
    }

    // computes the exact amount of tokens that should be swapped before adding liquidity for a given token
    // does the swap and then adds liquidity
    // minOtherToken should be set to the minimum intermediate amount of token1 that should be received to prevent
    // excessive slippage or front running
    // liquidity provider shares are minted to the 'to' address
    function swapExactTokensAndAddLiquidity(
        address tokenIn,
        address otherToken,
        uint amountIn,
        uint minOtherTokenIn,
        address to,
        uint deadline
    ) external returns (uint amountTokenIn, uint amountTokenOther, uint liquidity) {
        // compute how much we should swap in to match the reserve ratio of tokenIn / otherToken of the pair
        uint swapInAmount;
        {
            (uint reserveIn,) = UniswapV2Library.getReserves(address(factory), tokenIn, otherToken);
            swapInAmount = calculateSwapInAmount(reserveIn, amountIn);
        }

        // first take possession of the full amount from the caller
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        // approve for the swap, and then later the add liquidity. total is amountIn
        TransferHelper.safeApprove(tokenIn, address(router), amountIn);

        {
            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = otherToken;

            amountTokenOther = router.swapExactTokensForTokens(
                swapInAmount,
                minOtherTokenIn,
                path,
                address(this),
                deadline
            )[1];
        }

        // approve the other token for the add liquidity call
        TransferHelper.safeApprove(otherToken, address(router), amountTokenOther);
        amountTokenIn = amountIn.sub(swapInAmount);

        // no need to check that we transferred everything because minimums == total balance of this contract
        (,,liquidity) = router.addLiquidity(
            tokenIn,
            otherToken,
        // desired amountA, amountB
            amountTokenIn,
            amountTokenOther,
        // amountTokenIn and amountTokenOther should match the ratio of reserves of tokenIn to otherToken
        // thus we do not need to constrain the minimums here
            0,
            0,
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
        address to,
        uint deadline
    ) external returns (uint amountDesiredTokenOut) {
        address pair = UniswapV2Library.pairFor(address(factory), undesiredToken, desiredToken);
        // take possession of liquidity and give access to the router
        TransferHelper.safeTransferFrom(pair, msg.sender, address(this), liquidity);
        TransferHelper.safeApprove(pair, address(router), liquidity);

        (uint amountInToSwap, uint amountOutToTransfer) = router.removeLiquidity(
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
        TransferHelper.safeApprove(undesiredToken, address(router), amountInToSwap);

        address[] memory path = new address[](2);
        path[0] = undesiredToken;
        path[1] = desiredToken;

        uint amountOutSwap = router.swapExactTokensForTokens(
            amountInToSwap,
        // we must get at least this much from the swap to meet the minDesiredTokenOut parameter
            minDesiredTokenOut > amountOutToTransfer ? minDesiredTokenOut - amountOutToTransfer : 0,
            path,
            to,
            deadline
        )[1];

        // we do this after the swap to save gas in the case where we do not meet the minimum output
        TransferHelper.safeTransfer(desiredToken, to, amountOutToTransfer);
        amountDesiredTokenOut = amountOutToTransfer + amountOutSwap;
    }
}
