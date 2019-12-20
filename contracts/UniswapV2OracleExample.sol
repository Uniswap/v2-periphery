pragma solidity 0.5.15;

import "./interfaces/IUniswapV2OracleExample.sol";
import "./libraries/UQ112x112.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2.sol";

contract UniswapV2OracleExample is IUniswapV2OracleExample {
    using UQ112x112 for uint224;

    address public exchange;
    address public token0;
    address public token1;

    uint constant public period = 24 hours;
    bool public initialized;

    uint    private price0CumulativeLast;
    uint    private price1CumulativeLast;
    uint32  private blockNumberLast;
    uint224 private blockTimestampLast;
    uint224 public price0Average;
    uint224 public price1Average;

    constructor(address factory, address tokenA, address tokenB) public {
        exchange = IUniswapV2Factory(factory).getExchange(tokenA, tokenB);
        token0 = IUniswapV2(exchange).token0();
        token1 = IUniswapV2(exchange).token1();
    }

    function quote(address tokenIn, uint amountIn) external view returns (uint amountOut) {
        if (tokenIn == token0) {
            amountOut = UQ112x112.decode(price1Average.qmul(amountIn));
        } else {
            require(tokenIn == token1, "UniswapV2OracleExample: INVALID_INPUT_TOKEN");
            amountOut = UQ112x112.decode(price0Average.qmul(amountIn));
        }
    }

    function initialize() public {
        require(!initialized, "UniswapV2OracleExample: FORBIDDEN");
        price0CumulativeLast = IUniswapV2(exchange).price0CumulativeLast();
        price1CumulativeLast = IUniswapV2(exchange).price1CumulativeLast();
        blockNumberLast = IUniswapV2(exchange).blockNumberLast();
        // intentionally not setting blockTimestampLast so the first update() sets the price without time discounting
        initialized = true;
    }

    function update() public {
        require(initialized, "UniswapV2OracleExample: FORBIDDEN");
        uint32 blockNumber = uint32(block.number % 2**32);
        require(blockNumber != blockNumberLast, "UniswapV2OracleExample: ALREADY_UPDATED");
        if (blockNumber != IUniswapV2(exchange).blockNumberLast()) IUniswapV2(exchange).sync();

        uint price0Cumulative = IUniswapV2(exchange).price0CumulativeLast();
        uint price1Cumulative = IUniswapV2(exchange).price1CumulativeLast();
        uint32 blocksElapsed = blockNumber - blockNumberLast; // overflow is desired
        // - overflow is desired, / never overflows
        uint224 price0 = uint224((price0Cumulative - price0CumulativeLast) / blocksElapsed);
        uint224 price1 = uint224((price1Cumulative - price1CumulativeLast) / blocksElapsed);
        uint secondsElapsed = block.timestamp - blockTimestampLast; // solium-disable-line security/no-block-members
        if (secondsElapsed < period) {
            // warning, haven't fully thought through the rounding and such here...
            price0Average = uint224((price0Average * (period - secondsElapsed) + price0 * secondsElapsed) / period);
            price1Average = uint224((price1Average * (period - secondsElapsed) + price1 * secondsElapsed) / period);
        } else {
            price0Average = price0;
            price1Average = price1;
        }
        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockNumberLast = blockNumber;
        blockTimestampLast = uint224(block.timestamp); // solium-disable-line security/no-block-members
    }
}
