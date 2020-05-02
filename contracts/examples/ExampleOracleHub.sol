pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import './ExampleSlidingWindowOracle.sol';

// hub contract that deploys several oracles and manages updating them all when necessary as well as reimbursing callers
contract ExampleOracleHub {
    // mapping from pair address to a uint encoding 4 different uint64s, each representing
    // the last update epoch period of different oracles.
    mapping(address => uint) private lastUpdated;

    ExampleSlidingWindowOracle public hourlyOracle;
    ExampleSlidingWindowOracle public dailyOracle;
    ExampleSlidingWindowOracle public weeklyOracle;
    ExampleSlidingWindowOracle public monthlyOracle;

    constructor(address factory) public {
        // updates every 10 minutes
        hourlyOracle = new ExampleSlidingWindowOracle(factory, 3600, 6);
        // updates every hour
        dailyOracle = new ExampleSlidingWindowOracle(factory, 86400, 24);
        // updates twice a day
        weeklyOracle = new ExampleSlidingWindowOracle(factory, 604800, 14);
        // updates every month
        monthlyOracle = new ExampleSlidingWindowOracle(factory, 2592000, 30);
    }

    // last update periods are stored in 64 bits each
    function getLastPairUpdated(address pair) private view returns (
        uint64 lastHourlyPeriod,
        uint64 lastDailyPeriod,
        uint64 lastWeeklyPeriod,
        uint64 lastMonthlyPeriod
    ){
        uint pairLastUpdated = lastUpdated[pair];
        // use truncation and bit shifting to get the 4 uint64s out of the uint256
        lastHourlyPeriod = uint64(pairLastUpdated);
        lastDailyPeriod = uint64(pairLastUpdated >> 64);
        lastWeeklyPeriod = uint64(pairLastUpdated >> 128);
        lastMonthlyPeriod = uint64(pairLastUpdated >> 192);
    }

    function epochPeriod(uint periodSize) private view returns (uint64 period) {
        period = uint64(block.timestamp / periodSize % uint64(- 1));
    }

    function currentEpochPeriods() private view returns (
        uint64 hourlyPeriod,
        uint64 dailyPeriod,
        uint64 weeklyPeriod,
        uint64 monthlyPeriod
    ) {
        return (epochPeriod(600), epochPeriod(3600), epochPeriod(43200), epochPeriod(86400));
    }

    function saveLastPairUpdated(address pair, uint64 hp, uint64 dp, uint64 wp, uint64 mp) private {
        // current monthly epoch period
        uint toSave = mp << 64;
        // current weekly epoch period
        toSave = (toSave + wp) << 64;
        // current daily epoch period
        toSave = (toSave + dp) << 64;
        // current hourly epoch period
        lastUpdated[pair] = toSave + hp;
    }

    // updates oracles, and returns true if oracles were updated. can be called by the public if this contract runs out
    // of funds.
    function updateOracles(address pair) public returns (bool) {
        (uint64 lastHourlyPeriod, uint64 lastDailyPeriod, uint64 lastWeeklyPeriod, uint64 lastMonthlyPeriod) = getLastPairUpdated(pair);
        (uint64 hp, uint64 dp, uint64 wp, uint64 mp) = currentEpochPeriods();
        if (lastHourlyPeriod != hp) {
            address token0 = IUniswapV2Pair(pair).token0();
            address token1 = IUniswapV2Pair(pair).token1();
            hourlyOracle.update(token0, token1);
            if (dp != lastDailyPeriod) {
                dailyOracle.update(token0, token1);
                if (wp != lastWeeklyPeriod) {
                    weeklyOracle.update(token0, token1);
                    if (mp != lastMonthlyPeriod) {
                        monthlyOracle.update(token0, token1);
                    }
                }
            }
            saveLastPairUpdated(pair, hp, dp, wp, mp);
            return true;
        }
        return false;
    }

    // updates the oracles iff at least one period has passed for a given pair *and* it has enough funds to at least
    // partially refund the caller.
    function maybeUpdateOracles(address pair, address refundTo) external {
        if (address(this).balance == 0) {
            // this method only does anything if it has enough funds to at least partially refund the caller
            return;
        }
        uint gasBefore = gasleft();
        if (updateOracles(pair)) {
            uint owed = (gasBefore - gasleft()) * tx.gasprice;
            TransferHelper.safeTransferETH(refundTo, owed > address(this).balance ? address(this).balance : owed);
        }
    }

    // returns the most accurate available estimate of the price for a given token pair
    // from one of the oracles updated by this hub.
    function consult(address tokenIn, uint amountIn, address tokenOut, uint desiredWindowSize, uint minWindowSize) external view returns (
        uint amountOut, uint periodStartTimestamp
    ) {
        if (desiredWindowSize <= 3600) {
            return hourlyOracle.consult(tokenIn, amountIn, tokenOut, desiredWindowSize, minWindowSize);
        } else if (desiredWindowSize <= 86400) {
            return dailyOracle.consult(tokenIn, amountIn, tokenOut, desiredWindowSize, minWindowSize);
        } else if (desiredWindowSize <= 604800) {
            return weeklyOracle.consult(tokenIn, amountIn, tokenOut, desiredWindowSize, minWindowSize);
        } else if (desiredWindowSize <= 2592000) {
            return monthlyOracle.consult(tokenIn, amountIn, tokenOut, desiredWindowSize, minWindowSize);
        } else {
            revert('OracleHub: WINDOW_SIZE_NOT_SUPPORTED');
        }
    }
}
