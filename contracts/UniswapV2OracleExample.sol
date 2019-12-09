pragma solidity 0.5.13;

import "./interfaces/IUniswapV2OracleExample.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Math.sol";
import "./libraries/UQ128x128.sol";

contract UniswapV2OracleExample is IUniswapV2OracleExample {
    using SafeMath  for uint;
    using UQ128x128 for uint;

    address public exchangeAddress;

    uint   private priceCumulative0;
    uint   private priceCumulative1;
    uint64 private priceCumulative0Overflow;
    uint64 private priceCumulative1Overflow;
    uint64 private blockNumber;
    uint64 private blockTimestamp;

    uint public price0;
    uint public price1;
    uint constant public period = 24 hours;

    constructor(address factory, address tokenA, address tokenB) public {
        exchangeAddress = IUniswapV2Factory(factory).getExchange(tokenA, tokenB);
    }

    function quote0(uint128 amount0) public view returns (uint amount1) {
        amount1 = UQ128x128.decode(price1.qmul(amount0));
    }

    function quote1(uint128 amount1) public view returns (uint amount0) {
        amount0 = UQ128x128.decode(price0.qmul(amount1));
    }

    function initialize() public {
        require(blockNumber == 0, "UniswapV2Oracle: ALREADY_INITIALIZED");
        IUniswapV2 uniswap = IUniswapV2(exchangeAddress);
        if (block.number > uniswap.blockNumber()) uniswap.sync();
        priceCumulative0 = uniswap.priceCumulative0();
        priceCumulative1 = uniswap.priceCumulative1();
        priceCumulative0Overflow = uniswap.priceCumulative0Overflow();
        priceCumulative1Overflow = uniswap.priceCumulative1Overflow();
        blockNumber = uint64(block.number);
        // don't set blockTimestamp so that the first call to update sets the price without time discounting
    }

    function update() public {
        require(blockNumber != 0, "UniswapV2Oracle: NOT_INITIALIZED");
        IUniswapV2 uniswap = IUniswapV2(exchangeAddress);
        if (block.number > uniswap.blockNumber()) uniswap.sync();
        uint priceCumulative0New = uniswap.priceCumulative0();
        uint priceCumulative0NewOverflow = uniswap.priceCumulative0Overflow();
        uint priceCumulative1New = uniswap.priceCumulative1();
        uint priceCumulative1NewOverflow = uniswap.priceCumulative1Overflow();
        (uint priceCumulative0Delta, uint priceCumulative0DeltaOverflow) = Math.sub512(
            priceCumulative0New,
            priceCumulative0NewOverflow,
            priceCumulative0,
            priceCumulative0Overflow
        );
        (uint priceCumulative1Delta, uint priceCumulative1DeltaOverflow) = Math.sub512(
            priceCumulative1New,
            priceCumulative1NewOverflow,
            priceCumulative1,
            priceCumulative1Overflow
        );
        // fail on overflow
        require(priceCumulative0DeltaOverflow == 0 && priceCumulative1DeltaOverflow == 0, "UniswapV2Oracle: OVERFLOW");
        uint blocksElapsed = block.number - blockNumber;
        uint price0New = priceCumulative0Delta / blocksElapsed;
        uint price1New = priceCumulative1Delta / blocksElapsed;
        uint secondsElapsed = block.timestamp - blockTimestamp; // solium-disable-line security/no-block-members
        if (secondsElapsed < period) {
            price0 = (price0.mul(period.sub(secondsElapsed)).add(price0New.mul(secondsElapsed))) / period;
            price1 = (price1.mul(period.sub(secondsElapsed)).add(price1New.mul(secondsElapsed))) / period;
        } else {
            price0 = price0New;
            price1 = price1New;
        }
        priceCumulative0 = priceCumulative0New;
        priceCumulative1 = priceCumulative1New;
        priceCumulative0Overflow = uint64(priceCumulative0NewOverflow);
        priceCumulative1Overflow = uint64(priceCumulative1NewOverflow);
        blockNumber = uint64(block.number);
        blockTimestamp = uint64(block.timestamp); // solium-disable-line security/no-block-members
    }
}
