pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

// fixed window oracle that recomputes the average price for the entire period once every period
contract ExampleOracleSimple {
    using FixedPoint for *;

    uint public constant PERIOD = 24 hours;

    IUniswapV2Pair immutable pair;
    address public immutable token0;
    address public immutable token1;

    uint    public price0CumulativeLast;
    uint    public price1CumulativeLast;
    uint32  public blockTimestampLast;
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    constructor(address factory, address tokenA, address tokenB) public {
        IUniswapV2Pair _pair = IUniswapV2Pair(IUniswapV2Factory(factory).getPair(tokenA, tokenB));
        pair = _pair;
        token0 = _pair.token0();
        token1 = _pair.token1();
        price0CumulativeLast = _pair.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = _pair.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = _pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, 'ExampleOracleSimple: NO_RESERVES'); // ensure that there's liquidity in the pair
        require(blockTimestampLast != 0, 'ExampleOracleSimple: NO_PRICE_HISTORY'); // ensure there's a price history
    }

    function update() external {
        // updates the block timestamp and reserves so we don't have to adjust for it
        pair.sync();

        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        assert(timeElapsed >= PERIOD); // ensure that at least one full period has passed since the last update

        uint price0Cumulative = pair.price0CumulativeLast();
        uint price1Cumulative = pair.price1CumulativeLast();

        // - overflow is desired, / never overflows, casting never truncates
        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
        price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    function consult(address token, uint amountIn) external view returns (uint amountOut) {
        if (token == token0) {
            amountOut = price0Average.mul(amountIn).decode144();
        } else {
            assert(token == token1);
            amountOut = price1Average.mul(amountIn).decode144();
        }
    }
}
