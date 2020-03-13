pragma solidity =0.5.16;

import './interfaces/IOracleExample.sol';
import './libraries/UQ112x112.sol';
import './interfaces/V2/IUniswapV2Exchange.sol';

contract OracleExample is IOracleExample {
    using UQ112x112 for uint224;

    uint public constant period = 24 hours;
    bool public initialized;

    address public exchange;

    uint   public price0CumulativeLastCached;
    uint   public price1CumulativeLastCached;
    uint32 public blockTimestampLastCached;

    uint224 public price0Average; // prices should probably be accessed through quote, not directly
    uint224 public price1Average; // prices should probably be accessed through quote, not directly

    constructor(address _exchange) public {
        exchange = _exchange;
    }

    function initialize() external {
        require(!initialized, 'OracleExample: FORBIDDEN');
        price0CumulativeLastCached = IUniswapV2Exchange(exchange).price0CumulativeLast();
        price1CumulativeLastCached = IUniswapV2Exchange(exchange).price1CumulativeLast();
        require(price0CumulativeLastCached > 0 && price1CumulativeLastCached > 0, 'OracleExample: NO_PRICE');
        (, , blockTimestampLastCached) = IUniswapV2Exchange(exchange).getReserves();
        initialized = true;
    }

    function mock(uint32 blockTimestamp, uint32 blockTimestampLast, uint112 reserve0, uint112 reserve1)
        private
        view
        returns (uint price0CumulativeLast, uint price1CumulativeLast)
    {
        price0CumulativeLast = IUniswapV2Exchange(exchange).price0CumulativeLast();
        price1CumulativeLast = IUniswapV2Exchange(exchange).price1CumulativeLast();
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        price0CumulativeLast += uint(UQ112x112.encode(reserve1).uqdiv(reserve0)) * timeElapsed;
        price1CumulativeLast += uint(UQ112x112.encode(reserve0).uqdiv(reserve1)) * timeElapsed;
    }

    function update() external {
        require(initialized, 'OracleExample: FORBIDDEN');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        require(blockTimestamp != blockTimestampLastCached, 'OracleExample: ALREADY_UPDATED');
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Exchange(exchange).getReserves();
        require(reserve0 != 0 && reserve1 != 0, 'OracleExample: INSUFFICIENT_LIQUIDITY');
        // get maximally up-to-date values of price0CumulativeLast and price0CumulativeLast
        (uint price0CumulativeLast, uint price1CumulativeLast) = blockTimestamp == blockTimestampLast
            ? (IUniswapV2Exchange(exchange).price0CumulativeLast(), IUniswapV2Exchange(exchange).price1CumulativeLast())
            : mock(blockTimestamp, blockTimestampLast, reserve0, reserve1);
        uint32 timeElapsed = blockTimestamp - blockTimestampLastCached; // overflow is desired
        // - overflow is desired, / never overflows, casting never truncates
        uint224 price0 = uint224((price0CumulativeLast - price0CumulativeLastCached) / timeElapsed);
        uint224 price1 = uint224((price1CumulativeLast - price1CumulativeLastCached) / timeElapsed);
        if ((price0Average == 0 && price1Average == 0) || timeElapsed >= period) {
            price0Average = price0;
            price1Average = price1;
        } else {
            price0Average = uint224((price0Average * (period - timeElapsed) + price0 * timeElapsed) / period);
            price1Average = uint224((price1Average * (period - timeElapsed) + price1 * timeElapsed) / period);
        }
        price0CumulativeLastCached = price0CumulativeLast;
        price1CumulativeLastCached = price1CumulativeLast;
        blockTimestampLastCached = blockTimestamp;
    }

    function quote(address tokenIn, uint amountIn) external view returns (uint amountOut) {
        require(price0Average != 0 && price1Average != 0, 'OracleExample: NO_PRICE');
        if (tokenIn == IUniswapV2Exchange(exchange).token0()) {
            amountOut = UQ112x112.decode(price0Average.uqmul(amountIn));
        } else {
            require(tokenIn == IUniswapV2Exchange(exchange).token1(), 'OracleExample: INVALID_INPUT_TOKEN');
            amountOut = UQ112x112.decode(price1Average.uqmul(amountIn));
        }
    }
}
