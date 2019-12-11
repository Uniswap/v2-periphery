pragma solidity 0.5.13;

import "./interfaces/IUniswapV2OracleExample.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2.sol";
import "./libraries/UQ112x112.sol";

contract UniswapV2OracleExample is IUniswapV2OracleExample {
    using UQ112x112 for uint224;

    address public exchangeAddress;

    uint    private priceCumulative0Last;
    uint    private priceCumulative1Last;
    uint32  private blockNumberLast;
    uint224 private blockTimestampLast;

    uint224 public priceAverage0;
    uint224 public priceAverage1;

    uint constant public period = 24 hours;

    bool public initialized;

    constructor(address factory, address tokenA, address tokenB) public {
        exchangeAddress = IUniswapV2Factory(factory).getExchange(tokenA, tokenB);
    }

    function quote0(uint amount0) public view returns (uint amount1) {
        amount1 = UQ112x112.decode(priceAverage1.qmul(amount0));
    }

    function quote1(uint amount1) public view returns (uint amount0) {
        amount0 = UQ112x112.decode(priceAverage0.qmul(amount1));
    }

    function initialize() public {
        require(!initialized, "UniswapV2Oracle: ALREADY_INITIALIZED");
        IUniswapV2 uniswap = IUniswapV2(exchangeAddress);
        priceCumulative0Last = uniswap.priceCumulative0Last();
        priceCumulative1Last = uniswap.priceCumulative1Last();
        blockNumberLast = uniswap.blockNumberLast();
        // intentionally not setting blockTimestampLast so the first update() sets the price without time discounting
        initialized = true;
    }

    function update() public {
        require(initialized, "UniswapV2Oracle: NOT_INITIALIZED");
        IUniswapV2 uniswap = IUniswapV2(exchangeAddress);

        uint32 blockNumber = uint32(block.number % 2**32);
        if (blockNumber != uniswap.blockNumberLast()) uniswap.sync();

        uint priceCumulative0 = uniswap.priceCumulative0Last();
        uint priceCumulative1 = uniswap.priceCumulative1Last();
        uint32 blocksElapsed = blockNumber - blockNumberLast; // overflow is desired
        // in the following 2 lines, overflow is desired
        uint224 price0 = uint224((priceCumulative0 - priceCumulative0Last) / blocksElapsed);
        uint224 price1 = uint224((priceCumulative1 - priceCumulative1Last) / blocksElapsed);

        uint secondsElapsed = block.timestamp - blockTimestampLast; // solium-disable-line security/no-block-members
        if (secondsElapsed < period) {
            // the following shouldn't overflow
            priceAverage0 = uint224((priceAverage0 * (period - secondsElapsed) + price0 * secondsElapsed) / period);
            priceAverage1 = uint224((priceAverage1 * (period - secondsElapsed) + price1 * secondsElapsed) / period);
        } else {
            priceAverage0 = price0;
            priceAverage1 = price1;
        }
        priceCumulative0Last = priceCumulative0;
        priceCumulative1Last = priceCumulative1;
        blockNumberLast = blockNumber;
        blockTimestampLast = uint224(block.timestamp); // solium-disable-line security/no-block-members
    }
}
