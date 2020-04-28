pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

import './libraries/SafeMath.sol';
import './libraries/UniswapV2Library.sol';

// sliding window oracle that uses arrays of buckets to provide moving price averages in the past `period` with a
// granularity of `period/numBuckets`
// note this is a singleton oracle and only needs to be deployed once per desired period/numBuckets parameters, which
// differs from the simple oracle which must be deployed once per pair.
contract ExampleSlidingWindowOracle {
    using FixedPoint for *;
    using SafeMath for uint;

    struct Bucket {
        uint price0CumulativeLast;
        uint price1CumulativeLast;
        uint32 epochBucket;
        uint32 blockTimestamp;
    }

    address public immutable factory;
    // how long a period lasts
    uint public immutable period;
    // how many buckets there are in a period. higher granularity requires more frequent updates, but provides a more
    // accurate sliding window.
    uint8 public immutable numBuckets;

    // mapping from address to a list of buckets
    mapping(address => Bucket[]) public pairPriceData;

    constructor(address factory_, uint period_, uint8 numBuckets_) public {
        require((period_ / numBuckets_) * numBuckets_ == period_, 'SlidingWindowOracle: PERIOD_EVENLY_DIVISIBLE');
        factory = factory_;
        period = period_;
        numBuckets = numBuckets_;
    }

    // returns the first and last Bucket struct for the current time period as storage pointers
    // the last bucket is the current bucket and the first bucket is one period ago
    function getBuckets(address pair) internal view returns (Bucket storage periodFirst, Bucket storage current, uint32 epochBucket) {
        // e.g. the index of the bucket since epoch. overflow is desired.
        epochBucket = uint32(block.timestamp * numBuckets / period);

        // index in buckets array for the pair.
        uint8 currentBucketIndex = uint8(epochBucket % numBuckets);
        uint8 periodFirstBucketIndex = currentBucketIndex < numBuckets - 1 ? currentBucketIndex + 1 : 0;

        periodFirst = pairPriceData[pair][periodFirstBucketIndex];
        current = pairPriceData[pair][currentBucketIndex];
    }

    // call as many times as desired, at least once per bucket.
    // each call to update sets the cumulative price into the bucket corresponding to the current block timestamp.
    // a call to update is necessary to query the current moving average price as well as to query the moving average
    // price in one period.
    function update(address tokenA, address tokenB) external {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // populate the array with empty buckets (first call only)
        for (uint i = pairPriceData[pair].length; i < numBuckets; i++) {
            pairPriceData[pair].push();
        }

        (,Bucket storage current, uint32 epochBucket) = getBuckets(pair);

        // sync so the cumulative price we pull from the contract is for the current block timestamp
        // this is an alternate and more expensive approach to counterfactually determining the cumulative price,
        // as is done in the simple oracle.
        IUniswapV2Pair(pair).sync();
        current.price0CumulativeLast = IUniswapV2Pair(pair).price0CumulativeLast();
        current.price1CumulativeLast = IUniswapV2Pair(pair).price1CumulativeLast();
        current.epochBucket = epochBucket;
        current.blockTimestamp = uint32(block.timestamp % 2 ** 32);
    }

    // returns the amount out corresponding to the amount in for a given token using the moving average over the time
    // range [now - period, now]
    // update must have been called for the bucket corresponding to `now - period` as well as the bucket corresponding
    // to `now`
    function consult(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut) {
        address pair = UniswapV2Library.pairFor(factory, tokenIn, tokenOut);
        (Bucket storage periodFirst, Bucket storage current, uint epochBucket) = getBuckets(pair);

        require(current.epochBucket == epochBucket, 'SlidingWindowOracle: CURRENT_BUCKET_NOT_UPDATED');
        require(current.epochBucket - periodFirst.epochBucket == (numBuckets - 1), 'SlidingWindowOracle: MISSING_PREVIOUS_BUCKET');

        (address token0,) = UniswapV2Library.sortTokens(tokenIn, tokenOut);

        // overflow is desired.
        uint timeElapsed = current.blockTimestamp - periodFirst.blockTimestamp;

        if (token0 == tokenIn) {
            // overflow is desired.
            uint price0Cumulative = (current.price0CumulativeLast - periodFirst.price0CumulativeLast) / timeElapsed;

            amountOut = FixedPoint.uq112x112(uint224(price0Cumulative)).mul(amountIn).decode144();
        } else {
            // overflow is desired.
            uint price1Cumulative = (current.price1CumulativeLast - periodFirst.price1CumulativeLast) / timeElapsed;

            amountOut = FixedPoint.uq112x112(uint224(price1Cumulative)).mul(amountIn).decode144();
        }
    }
}
