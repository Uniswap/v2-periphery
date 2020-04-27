pragma solidity >=0.5.0;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

// computes prices for pairs given a previous checkpoint in a gas efficient manner
library PriceComputer {
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

    // computes prices over an arbitrary period by reading the current state from the pair and comparing it to the
    // given previous state. the resulting prices are the averages over the period between blockTimestampLast and
    // the current block timestamp, even if the pair has not been synced in the current block.
    // the returned values should be used for computing the average prices of the following period.
    function compute(
        IUniswapV2Pair pair,
        uint32 blockTimestampLast, uint price0CumulativeLast, uint price1CumulativeLast
    ) internal view returns (
        FixedPoint.uq112x112 memory price0Average, FixedPoint.uq112x112 memory price1Average,
        uint32 blockTimestamp, uint price0Cumulative, uint price1Cumulative
    ) {
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

        // overflow is desired
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
        price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));
    }
}
