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

    address public /*immutable*/ factory;
    // how long a period lasts
    uint public /*immutable*/ period = 24 hours;
    // how many buckets there are in a period. higher granularity requires more frequent updates, and provides a more
    // accurate sliding window.
    uint8 public /*immutable*/ numBuckets = 24;

    // mapping from address to a list of buckets
    mapping(address => Bucket[]) public pairPriceData;

    constructor(address factory_, uint period_, uint8 numBuckets_) public {
        factory = factory_;
        period = period_;
        numBuckets = numBuckets_;
    }

    // returns the first and last Bucket struct for the current time period as storage pointers
    function getBuckets(address pair) internal view returns (Bucket storage first, Bucket storage last, uint32 epochBucket) {
        // e.g. the index of the bucket since epoch. overflow is desired.
        epochBucket = uint32(block.timestamp * numBuckets / period);

        // index in buckets array for the pair.
        uint8 lastBucketIndex = uint8(epochBucket % numBuckets);
        uint8 firstBucketIndex = uint8((epochBucket + 1) % numBuckets);

        first = pairPriceData[pair][firstBucketIndex];
        last = pairPriceData[pair][lastBucketIndex];
    }

    // call as many times as desired. each update updates the cumulative price into the corresponding bucket.
    function update(address tokenA, address tokenB) external {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        require(pair != address(0), 'SlidingWindowOracle: PAIR_NOT_EXISTS');
        // sync so the cumulative price we pull from the contract is for the current block timestamp
        IUniswapV2Pair(pair).sync();

        for (uint i = pairPriceData[pair].length; i < numBuckets; i++) {
            pairPriceData[pair].push();
        }

        (,Bucket storage last, uint32 epochBucket) = getBuckets(pair);
        last.price0CumulativeLast = IUniswapV2Pair(pair).price0CumulativeLast();
        last.price1CumulativeLast = IUniswapV2Pair(pair).price1CumulativeLast();
        last.epochBucket = epochBucket;
        last.blockTimestamp = uint32(block.timestamp % 2 ** 32);
    }

    function consult(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut) {
        address pair = UniswapV2Library.pairFor(factory, tokenIn, tokenOut);
        require(pair != address(0), 'SlidingWindowOracle: PAIR_NOT_EXISTS');
        (Bucket storage first, Bucket storage last, uint epochBucket) = getBuckets(pair);

        require(last.epochBucket == epochBucket, 'SlidingWindowOracle: BUCKET_NOT_UPDATED');
        require(last.epochBucket - first.epochBucket == numBuckets, 'SlidingWindowOracle: MISSING_PREVIOUS_BUCKET');

        (address token0,) = UniswapV2Library.sortTokens(tokenIn, tokenOut);

        // overflow is desired.
        uint timeElapsed = (last.blockTimestamp - first.blockTimestamp);

        if (token0 == tokenIn) {
            // overflow is desired.
            uint price0Cumulative = (last.price0CumulativeLast - first.price0CumulativeLast) / timeElapsed;

            amountOut = FixedPoint.uq112x112(uint224(price0Cumulative)).mul(amountIn).decode144();
        } else {
            // overflow is desired.
            uint price1Cumulative = (last.price1CumulativeLast - first.price1CumulativeLast) / timeElapsed;

            amountOut = FixedPoint.uq112x112(uint224(price1Cumulative)).mul(amountIn).decode144();
        }
    }
}
