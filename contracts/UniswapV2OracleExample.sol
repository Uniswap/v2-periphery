pragma solidity 0.5.15;

import "./interfaces/IUniswapV2OracleExample.sol";
import "./libraries/UQ112x112.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2.sol";

contract UniswapV2OracleExample is IUniswapV2OracleExample {
    using UQ112x112 for uint224;

    uint constant public period = 24 hours;
    bool public initialized;

    address public exchange;
    address public token0;
    address public token1;

    uint    private price0CumulativeLast_;
    uint    private price1CumulativeLast_;
    uint32  private blockNumberLast_;
    uint224 private blockTimestampLast_;
    uint224 public  price0Average;
    uint224 public  price1Average;

    constructor(address factory, address tokenA, address tokenB) public {
        exchange = IUniswapV2Factory(factory).getExchange(tokenA, tokenB);
        token0 = IUniswapV2(exchange).token0();
        token1 = IUniswapV2(exchange).token1();
    }

    function initialize() external {
        require(!initialized, "UniswapV2OracleExample: FORBIDDEN");
        initialized = true;
        price0CumulativeLast_ = IUniswapV2(exchange).price0CumulativeLast();
        price1CumulativeLast_ = IUniswapV2(exchange).price1CumulativeLast();
        (,,blockNumberLast_) = IUniswapV2(exchange).getReserves();
        // intentionally not setting blockTimestampLast_ so the first update() sets the price without time discounting
    }

    function quote(address tokenIn, uint amountIn) external view returns (uint amountOut) {
        if (tokenIn == token0) {
            amountOut = UQ112x112.decode(price0Average.qmul(amountIn));
        } else {
            require(tokenIn == token1, "UniswapV2OracleExample: INVALID_INPUT_TOKEN");
            amountOut = UQ112x112.decode(price1Average.qmul(amountIn));
        }
    }

    function update() external {
        require(initialized, "UniswapV2OracleExample: FORBIDDEN");
        uint32 blockNumber = uint32(block.number % 2**32);
        require(blockNumber != blockNumberLast_, "UniswapV2OracleExample: ALREADY_UPDATED");
        (,, uint32 blockNumberLast) = IUniswapV2(exchange).getReserves();
        if (blockNumber != blockNumberLast) IUniswapV2(exchange).sync(); // sync exchange if it hasn't yet this block
        uint price0Cumulative = IUniswapV2(exchange).price0CumulativeLast();
        uint price1Cumulative = IUniswapV2(exchange).price1CumulativeLast();
        uint32 blocksElapsed = blockNumber - blockNumberLast_; // overflow is desired
        // - overflow is desired, / never overflows, casting never truncates
        uint224 price0 = uint224((price0Cumulative - price0CumulativeLast_) / blocksElapsed);
        uint224 price1 = uint224((price1Cumulative - price1CumulativeLast_) / blocksElapsed);
        uint secondsElapsed = block.timestamp - blockTimestampLast_; // solium-disable-line security/no-block-members
        if (secondsElapsed < period) {
            price0Average = uint224((price0Average * (period - secondsElapsed) + price0 * secondsElapsed) / period);
            price1Average = uint224((price1Average * (period - secondsElapsed) + price1 * secondsElapsed) / period);
        } else {
            price0Average = price0;
            price1Average = price1;
        }
        price0CumulativeLast_ = price0Cumulative;
        price1CumulativeLast_ = price1Cumulative;
        blockNumberLast_ = blockNumber;
        blockTimestampLast_ = uint224(block.timestamp); // solium-disable-line security/no-block-members
    }
}
