pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

import '../libraries/SafeMath.sol';
import '../libraries/UniswapV2Library.sol';
import '../libraries/UniswapV2OracleLibrary.sol';

// sliding window oracle that uses arrays of buckets to provide moving price averages in the past `period` with a
// granularity of `period/numBuckets`
// note this is a singleton oracle and only needs to be deployed once per desired period/numBuckets parameters, which
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
    // the desired length of time to acerage observations over, in seconds
    uint public immutable windowSize;
    // the number of epochs that windows are divided into, corresponding to the number of observations stored for a pair
    // as granularity increases from 1, more frequent updates are needed, but estimates become more precise
    // averages will be computed over intervals in the range: (windowSize - (windowSize / granularity) * 2, windowSize)
    uint8 public immutable granularity;

    // mapping from address to a list of buckets
    mapping(address => Observation[]) public pairObservations;

    constructor(address factory_, uint windowSize_, uint8 granularity_) public {
        require(granularity_ > 1 && granularity_ <= uint8(-1), 'SlidingWindowOracle: GRANULARITY');
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

    // responsible for storing the first observation once per epoch.
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

    // returns the amount out corresponding to the amount in for a given token using the moving average over the time
    // range [now - period, now]
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

        // this condition may incorrectly trigger for one window duration around the uint32(-1) overflow
        // of blockTimestamp
        uint32 timeElapsed = blockTimestamp - historicalObservation.blockTimestamp;
        require(timeElapsed < windowSize, 'SlidingWindowOracle: MISSING_HISTORICAL_OBSERVATION');

        (address token0,) = UniswapV2Library.sortTokens(tokenIn, tokenOut);
        if (token0 == tokenIn) {
            // overflow is desired.
            FixedPoint.uq112x112 memory price0Average = FixedPoint.uq112x112(
                uint224(price0Cumulative - historicalObservation.price0Cumulative) / timeElapsed
            );
            amountOut = price0Average.mul(amountIn).decode144();
        } else {
            // overflow is desired.
            FixedPoint.uq112x112 memory price1Average = FixedPoint.uq112x112(
                uint224(price1Cumulative - historicalObservation.price1Cumulative) / timeElapsed
            );
            amountOut = price1Average.mul(amountIn).decode144();
        }
    }
}
