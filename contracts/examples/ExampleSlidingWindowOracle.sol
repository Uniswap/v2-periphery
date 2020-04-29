pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

import '../libraries/SafeMath.sol';
import '../libraries/UniswapV2Library.sol';
import '../libraries/UniswapV2OracleLibrary.sol';

// sliding window oracle that uses observations collected over a window to provide moving price averages in the past
// `windowSize` with a precision of `windowSize / granularity`
// note this is a singleton oracle and only needs to be deployed once per desired parameters, which
// differs from the simple oracle which must be deployed once per pair.
contract ExampleSlidingWindowOracle {
    using FixedPoint for *;
    using SafeMath for uint;

    struct Observation {
        uint32 blockTimestamp;
        uint price0Cumulative;
        uint price1Cumulative;
    }

    address public immutable factory;
    // the desired amount of time over which the moving average should be computed
    // may not be exceed max uint32, as block timestamps cannot be compared for larger windows
    uint32 public immutable windowSize;
    // the number of observations stored for each pair.
    // as granularity increases from 1, more frequent updates are needed, but moving averages become more precise
    // averages are computed over intervals with sizes in the range:
    //   [windowSize - (windowSize / granularity) * 2, windowSize]
    // e.g. if the window size is 24 hours, and the granularity is 24, the oracle will return the average price for
    //   the period:
    //   [now - [22 hours, 24 hours], now]
    uint8 public immutable granularity;

    // mapping from pair address to a list of price observations of that pair
    mapping(address => Observation[]) public pairObservations;

    constructor(address factory_, uint32 windowSize_, uint8 granularity_) public {
        require(granularity_ > 1, 'SlidingWindowOracle: GRANULARITY');
        require((windowSize_ / granularity_) * granularity_ == windowSize_, 'SlidingWindowOracle: UNEVEN_EPOCHS');
        factory = factory_;
        windowSize = windowSize_;
        granularity = granularity_;
    }

    // returns the observation from the oldest epoch (at the beginning of the window) relative to the current time
    function getHistoricalObservation(address pair) private view returns (Observation storage historicalObservation) {
        uint8 observationIndex = uint8((block.timestamp % windowSize) / (windowSize / granularity));
        uint8 historicalObservationIndex = (observationIndex + 1) % granularity;
        historicalObservation = pairObservations[pair][historicalObservationIndex];
    }

    // update the cumulative price for the observation at the current timestamp. each observation is updated at most
    // once per epoch window.
    function update(address tokenA, address tokenB) external {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);

        // populate the array with empty observations (first call only)
        for (uint i = pairObservations[pair].length; i < granularity; i++) {
            pairObservations[pair].push();
        }

        // get the observation for the correct epoch
        uint8 observationIndex = uint8((block.timestamp % windowSize) / (windowSize / granularity));
        Observation storage observation = pairObservations[pair][observationIndex];

        (
            uint32 blockTimestamp,
            uint price0Cumulative,
            uint price1Cumulative
        ) = UniswapV2OracleLibrary.currentCumulativePrices(pair);

        // we only want to update each epoch once per window duration
        // this condition may not trigger for one window duration if the pair is being initialized around the
        // uint32(-1) overflow of blockTimestamp
        uint32 timeElapsed = blockTimestamp - observation.blockTimestamp;
        if (timeElapsed > windowSize / granularity) {
            observation.blockTimestamp = blockTimestamp;
            observation.price0Cumulative = price0Cumulative;
            observation.price1Cumulative = price1Cumulative;
        }
    }

    // given the cumulative prices of the start and end of a period, and the length of the period, compute the average
    // price in terms of how much amount out is received for the amount in
    function computeAmountOut(
        uint priceCumulativeStart, uint priceCumulativeEnd,
        uint32 timeElapsed, uint amountIn
    ) private pure returns (uint amountOut) {
        // overflow is desired.
        FixedPoint.uq112x112 memory priceAverage = FixedPoint.uq112x112(
            uint224((priceCumulativeEnd - priceCumulativeStart) / timeElapsed)
        );
        amountOut = priceAverage.mul(amountIn).decode144();
    }

    // returns the amount out corresponding to the amount in for a given token using the moving average over the time
    // range [now - windowSize, now]
    // update must have been called for the bucket corresponding to `now - period` as well as the bucket corresponding
    // to `now`
    function consult(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut) {
        address pair = UniswapV2Library.pairFor(factory, tokenIn, tokenOut);
        Observation storage historicalObservation = getHistoricalObservation(pair);
        (
            uint32 blockTimestamp,
            uint price0Cumulative,
            uint price1Cumulative
        ) = UniswapV2OracleLibrary.currentCumulativePrices(pair);

        // this condition may incorrectly trigger for one period around the uint32(-1) overflow of blockTimestamp
        uint32 timeElapsed = blockTimestamp - historicalObservation.blockTimestamp;
        require(timeElapsed <= windowSize, 'SlidingWindowOracle: MISSING_HISTORICAL_OBSERVATION');

        (address token0,) = UniswapV2Library.sortTokens(tokenIn, tokenOut);
        if (token0 == tokenIn) {
            return computeAmountOut(historicalObservation.price0Cumulative, price0Cumulative, timeElapsed, amountIn);
        } else {
            return computeAmountOut(historicalObservation.price1Cumulative, price1Cumulative, timeElapsed, amountIn);
        }
    }
}
