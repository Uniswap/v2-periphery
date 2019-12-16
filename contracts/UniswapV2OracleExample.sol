pragma solidity 0.5.14;

import "./interfaces/IUniswapV2OracleExample.sol";
import "./libraries/UQ112x112.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2.sol";

contract UniswapV2OracleExample is IUniswapV2OracleExample {
    using UQ112x112 for uint224;

    address public exchange;

    uint    private price0CumulativeLast;
    uint    private price1CumulativeLast;
    uint32  private blockNumberLast;
    uint224 private blockTimestampLast;

    uint224 public price0Average;
    uint224 public price1Average;

    uint constant public period = 24 hours;

    bool public initialized;

    constructor(address factory, address tokenA, address tokenB) public {
        exchange = IUniswapV2Factory(factory).getExchange(tokenA, tokenB);
    }

    function quote0(uint amount0) public view returns (uint amount1) {
        amount1 = UQ112x112.decode(price1Average.qmul(amount0));
    }

    function quote1(uint amount1) public view returns (uint amount0) {
        amount0 = UQ112x112.decode(price0Average.qmul(amount1));
    }

    function initialize() public {
        require(!initialized, "UniswapV2OracleExample: ALREADY_INITIALIZED");
        IUniswapV2 uniswap = IUniswapV2(exchange);
        price0CumulativeLast = uniswap.price0CumulativeLast();
        price1CumulativeLast = uniswap.price1CumulativeLast();
        blockNumberLast = uniswap.blockNumberLast();
        // intentionally not setting blockTimestampLast so the first update() sets the price without time discounting
        initialized = true;
    }

    function update() public {
        require(initialized, "UniswapV2OracleExample: NOT_INITIALIZED");
        IUniswapV2 uniswap = IUniswapV2(exchange);

        uint32 blockNumber = uint32(block.number % 2**32);
        require(blockNumber != blockNumberLast, "UniswapV2OracleExample: ALREADY_UPDATED");
        if (blockNumber != uniswap.blockNumberLast()) uniswap.sync();

        uint price0Cumulative = uniswap.price0CumulativeLast();
        uint price1Cumulative = uniswap.price1CumulativeLast();
        uint32 blocksElapsed = blockNumber - blockNumberLast; // overflow is desired
        // in the following 2 lines, overflow is desired
        uint224 price0 = uint224((price0Cumulative - price0CumulativeLast) / blocksElapsed);
        uint224 price1 = uint224((price1Cumulative - price1CumulativeLast) / blocksElapsed);

        uint secondsElapsed = block.timestamp - blockTimestampLast; // solium-disable-line security/no-block-members
        if (secondsElapsed < period) {
            // in the following 2 lines, overflow shouldn't happen
            price0Average = uint224(
                (uint(price0Average) * (period - secondsElapsed) + uint(price0) * secondsElapsed) / period
            );
            price1Average = uint224(
                (uint(price1Average) * (period - secondsElapsed) + uint(price1) * secondsElapsed) / period
            );
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
