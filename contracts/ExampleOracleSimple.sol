pragma solidity =0.5.16;

import './UniswapV2Library.sol';
import './libraries/UQ112x112.sol';

contract ExampleOracleSimple is UniswapV2Library {
    using UQ112x112 for uint224;

    uint public constant PERIOD = 24 hours;
    address public token0;
    address public token1;
    IUniswapV2Pair public pair;

    uint    public price0CumulativeLast;
    uint    public price1CumulativeLast;
    uint32  public blockTimestampLast;
    uint224 public price0Average;
    uint224 public price1Average;

    constructor(address tokenA, address tokenB) public {
        (token0, token1) = sortTokens(tokenA, tokenB);
        pair = IUniswapV2Pair(pairFor(token0, token1));
        price0CumulativeLast = pair.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = pair.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = pair.getReserves();
        assert(reserve0 != 0 && reserve1 != 0); // ensure that there's liquidity in the pair
        assert(blockTimestampLast != 0); // ensure there's a price history
    }

    function update() external {
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        assert(timeElapsed >= PERIOD); // ensure that at least one full period has passed since the last update

        uint price0Cumulative = pair.price0CumulativeLast();
        uint price1Cumulative = pair.price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLastFromPair) = pair.getReserves();
        assert(reserve0 != 0 && reserve1 != 0); // ensure that there's still liquidity in the pair
        if (blockTimestampLastFromPair != blockTimestamp) {
            price0Cumulative += uint(UQ112x112.encode(reserve1).uqdiv(reserve0)) * timeElapsed; // counterfactual
            price1Cumulative += uint(UQ112x112.encode(reserve0).uqdiv(reserve1)) * timeElapsed; // counterfactual
        }

        // - overflow is desired, / never overflows, casting never truncates
        price0Average = uint224((price0Cumulative - price0CumulativeLast) / timeElapsed);
        price1Average = uint224((price1Cumulative - price1CumulativeLast) / timeElapsed);

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    function consult(address token, uint amountIn) external view returns (uint amountOut) {
        if (token == token0) {
            amountOut = UQ112x112.decode(price0Average.uqmul(amountIn));
        } else {
            assert(token == token1);
            amountOut = UQ112x112.decode(price1Average.uqmul(amountIn));
        }
    }
}
