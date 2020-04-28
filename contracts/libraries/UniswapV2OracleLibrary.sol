pragma solidity >=0.5.0;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

// library with helper methods for oracles that are concerned with computing average prices
library UniswapV2OracleLibrary {
    using FixedPoint for *;

    // helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**32 - 1]
    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2 ** 32);
    }

    // helper function that returns the time that has elapsed since the given block timestamp in uint32
    function timeElapsedSince(uint32 blockTimestampLast) internal view returns (uint32) {
        // overflow desired
        return currentBlockTimestamp() - blockTimestampLast;
    }

    // produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    function currentCumulativePrices(
        IUniswapV2Pair pair
    ) internal view returns (uint32 blockTimestamp, uint price0Cumulative, uint price1Cumulative) {
        price0Cumulative = pair.price0CumulativeLast();
        price1Cumulative = pair.price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLastFromPair) = pair.getReserves();
        blockTimestamp = currentBlockTimestamp();
        if (blockTimestampLastFromPair != blockTimestamp) {
            uint timeElapsedPartial = blockTimestamp - blockTimestampLastFromPair;
            // overflow is desired
            // counterfactual
            price0Cumulative += uint(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsedPartial;
            // counterfactual
            price1Cumulative += uint(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsedPartial;
        }
    }
}
