pragma solidity =0.6.6;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/contracts/libraries/Babylonian.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";

import "../interfaces/IUniswapV2Router01.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IERC20.sol";
import "../libraries/SafeMath.sol";
import "../libraries/UniswapV2Library.sol";

// enables adding and removing liquidity with a single token to/from a pair
// adds liquidity via a single token of the pair, by first swapping against the pair and then adding liquidity
// removes liquidity in a single token, by removing liquidity and then immediately swapping
contract ExampleCombinedSwapAddRemoveLiquidity {
    using SafeMath for uint;

    IUniswapV2Factory public immutable factory;
    IUniswapV2Router01 public immutable router;
    IWETH public immutable weth;

    constructor(IUniswapV2Factory factory_, IUniswapV2Router01 router_, IWETH weth_) public {
        factory = factory_;
        router = router_;
        weth = weth_;
    }

    // grants unlimited approval for a token to the router unless the existing allowance is high enough
    function approveRouter(address _token, uint256 _amount) internal {
        uint256 allowance = IERC20(_token).allowance(address(this), address(router));
        if (allowance < _amount) {
            if (allowance > 0) {
                // clear the existing allowance
                TransferHelper.safeApprove(_token, address(router), 0);
            }
            TransferHelper.safeApprove(_token, address(router), uint256(-1));
        }
    }

    // returns the amount of token that should be swapped in such that ratio of reserves in the pair is equivalent
    // to the swapper's ratio of tokens
    // note this depends only on the number of tokens the caller wishes to swap and the current reserves of that token,
    // and not the current reserves of the other token
    function calculateSwapInAmount(uint reserveIn, uint userIn) public pure returns (uint) {
        return Babylonian.sqrt(reserveIn.mul(userIn.mul(3988000) + reserveIn.mul(3988009))).sub(reserveIn.mul(1997)) / 1994;
    }

    // internal function shared by the ETH/non-ETH versions
    function _swapExactTokensAndAddLiquidity(
        address from,
        address tokenIn,
        address otherToken,
        uint amountIn,
        uint minOtherTokenIn,
        address to,
        uint deadline
    ) internal returns (uint amountTokenIn, uint amountTokenOther, uint liquidity) {
        // compute how much we should swap in to match the reserve ratio of tokenIn / otherToken of the pair
        uint swapInAmount;
        {
            (uint reserveIn,) = UniswapV2Library.getReserves(address(factory), tokenIn, otherToken);
            swapInAmount = calculateSwapInAmount(reserveIn, amountIn);
        }

        // first take possession of the full amount from the caller, unless caller is this contract
        if (from != address(this)) {
            TransferHelper.safeTransferFrom(tokenIn, from, address(this), amountIn);
        }
        // approve for the swap, and then later the add liquidity. total is amountIn
        approveRouter(tokenIn, amountIn);

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
        approveRouter(otherToken, amountTokenOther);
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
        return _swapExactTokensAndAddLiquidity(
            msg.sender, tokenIn, otherToken, amountIn, minOtherTokenIn, to, deadline
        );
    }

    // similar to the above method but handles converting ETH to WETH
    function swapExactETHAndAddLiquidity(
        address token,
        uint minTokenIn,
        address to,
        uint deadline
    ) external payable returns (uint amountETHIn, uint amountTokenIn, uint liquidity) {
        weth.deposit{value: msg.value}();
        return _swapExactTokensAndAddLiquidity(
            address(this), address(weth), token, msg.value, minTokenIn, to, deadline
        );
    }

    // internal function shared by the ETH/non-ETH versions
    function _removeLiquidityAndSwap(
        address from,
        address undesiredToken,
        address desiredToken,
        uint liquidity,
        uint minDesiredTokenOut,
        address to,
        uint deadline
    ) internal returns (uint amountDesiredTokenOut) {
        address pair = UniswapV2Library.pairFor(address(factory), undesiredToken, desiredToken);
        // take possession of liquidity and give access to the router
        TransferHelper.safeTransferFrom(pair, from, address(this), liquidity);
        approveRouter(pair, liquidity);

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
        approveRouter(undesiredToken, amountInToSwap);

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
        if (to != address(this)) {
            TransferHelper.safeTransfer(desiredToken, to, amountOutToTransfer);
        }
        amountDesiredTokenOut = amountOutToTransfer + amountOutSwap;
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
        return _removeLiquidityAndSwap(
            msg.sender, undesiredToken, desiredToken, liquidity, minDesiredTokenOut, to, deadline
        );
    }

    // only WETH can send to this contract without a function call.
    receive() payable external {
        require(msg.sender == address(weth), 'CombinedSwapAddRemoveLiquidity: RECEIVE_NOT_FROM_WETH');
    }

    // similar to the above method but for when the desired token is WETH, handles unwrapping
    function removeLiquidityAndSwapToETH(
        address token,
        uint liquidity,
        uint minDesiredETH,
        address to,
        uint deadline
    ) external returns (uint amountETHOut) {
        // do the swap remove and swap to this address
        amountETHOut = _removeLiquidityAndSwap(
            msg.sender, token, address(weth), liquidity, minDesiredETH, address(this), deadline
        );

        // now withdraw to ETH and forward to the recipient
        weth.withdraw(amountETHOut);
        TransferHelper.safeTransferETH(to, amountETHOut);
    }
}
