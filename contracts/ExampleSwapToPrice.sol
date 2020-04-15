pragma solidity =0.5.16;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import './UniswapV2Library.sol';
import './interfaces/IERC20.sol';
import './interfaces/IUniswapV2Router01.sol';
import './libraries/SafeMath.sol';

contract ExampleSwapToPrice is UniswapV2Library {
    using SafeMath for uint256;

    bytes4 private constant SELECTOR_TRANSFER_FROM = bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
    bytes4 private constant SELECTOR_APPROVE = bytes4(keccak256(bytes('approve(address,uint256)')));

    IUniswapV2Router01 public router;

    constructor(IUniswapV2Router01 router_) public {
        router = router_;
    }

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _safeTransferFrom(address token, address from, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR_TRANSFER_FROM, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'ExampleSwapToPrice: TRANSFER_FROM_FAILED');
    }

    function _safeApprove(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR_APPROVE, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'ExampleSwapToPrice: APPROVE_FAILED');
    }

    event SwapToPrice(address tokenIn, uint256 amoutIn, address tokenOut, uint256 amountOut);

    // swaps a given token in an amount to move the price to the profit-maximizing price, given the external true price
    // true price is expressed in the ratio of token in to token out
    function swapToPrice(
        address tokenIn,
        address tokenOut,
        uint128 truePriceTokenIn,
        uint128 truePriceTokenOut,
        address to,
        uint256 deadline
    ) ensure(deadline) public {
        require(truePriceTokenIn != 0 && truePriceTokenOut != 0, "ExampleSwapToPrice: ZERO_PRICE");

        (uint256 reserveIn, uint256 reserveOut) = getReserves(tokenIn, tokenOut);

        uint256 amountIn;
        {
            uint256 invariant = reserveIn.mul(reserveOut);

            uint256 leftSide = sqrt(invariant.mul(truePriceTokenIn).mul(1000) / uint256(truePriceTokenOut).mul(997));
            uint256 rightSide = reserveIn.mul(1000) / 997;

            // compute the amount that must be sent to move the price to the profit-maximizing price
            amountIn = leftSide.sub(rightSide);

            require(amountIn > 0, "ExampleSwapToPrice: ZERO_PROFIT");

            // spend up to the allowance of the token in
            uint256 allowance = IERC20(tokenIn).allowance(msg.sender, address(this));
            if (amountIn > allowance) {
                amountIn = allowance;
            }
        }

        _safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        _safeApprove(tokenIn, address(router), amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint amountOut = getAmountOut(amountIn, reserveIn, reserveOut);

        // emit an event for testing the calculation
        emit SwapToPrice(tokenIn, amountIn, tokenOut, amountOut);

        router.swapExactTokensForTokens(
            amountIn,
            amountOut,
            path,
            to,
            block.timestamp
        );
    }
}
