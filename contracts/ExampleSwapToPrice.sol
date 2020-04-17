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
        require(deadline >= block.timestamp, 'ExampleSwapToPrice: EXPIRED');
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

    // swaps either token in an amount to move the price to the profit-maximizing price, given the external true price
    // true price is expressed in the ratio of token A to token B
    // caller must approve this contract to spend whichever token is intended to be swapped
    function swapToPrice(
        address tokenA,
        address tokenB,
        uint256 maxSpendTokenA,
        uint256 maxSpendTokenB,
        uint256 truePriceTokenA,
        uint256 truePriceTokenB,
        address to,
        uint256 deadline
    ) ensure(deadline) public {
        // true price is expressed as a ratio, so both values must be non-zero
        require(truePriceTokenA != 0 && truePriceTokenB != 0, "ExampleSwapToPrice: ZERO_PRICE");
        // caller can specify 0 for either if they wish to swap in only one direction, but not both
        require(maxSpendTokenA != 0 || maxSpendTokenB != 0, "ExampleSwapToPrice: ZERO_SPEND");

        (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB);

        // if the ratio of a/b < true a/b, then b is cheap and we should buy it, otherwise vice versa
        bool aToB = reserveA.mul(truePriceTokenB) / reserveB < truePriceTokenA;

        uint256 amountIn;
        {
            uint256 invariant = reserveA.mul(reserveB);

            uint256 leftSide = sqrt(
                invariant.mul(aToB ? truePriceTokenA : truePriceTokenB).mul(1000) /
                uint256(aToB ? truePriceTokenB : truePriceTokenA).mul(997)
            );
            uint256 rightSide = (aToB ? reserveA.mul(1000) : reserveB.mul(1000)) / 997;

            // compute the amount that must be sent to move the price to the profit-maximizing price
            amountIn = leftSide.sub(rightSide);

            // spend up to the allowance of the token in
            uint256 maxSpend = aToB ? maxSpendTokenA : maxSpendTokenB;
            if (amountIn > maxSpend) {
                amountIn = maxSpend;
            }
        }

        address tokenIn = aToB ? tokenA : tokenB;
        address tokenOut = aToB ? tokenB : tokenA;
        _safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        _safeApprove(tokenIn, address(router), amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        router.swapExactTokensForTokens(
            amountIn,
            0, // amountOutMin: we can skip computing this number because the math is tested
            path,
            to,
            block.timestamp
        );
    }
}
