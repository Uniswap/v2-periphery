pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import './interfaces/IUniswapV2Router04.sol';
import './UniswapV2Router03.sol';
import './libraries/SafeMath.sol';
import './GasMetered.sol';

contract UniswapV2Router04 is GasMetered, UniswapV2Router03 {
    constructor(address _factory, address _WETH) public UniswapV2Router03(_factory, _WETH) GasMetered() {}

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public override(UniswapV2Router03, GasMetered) pure returns (uint256 amountOut) {
        return UniswapV2Router03.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getEthExchangeRate(address token) internal override returns (uint256 reserveInput, uint256 reserveOutput) {
        IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, WETH, token));
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        (address token0, ) = UniswapV2Library.sortTokens(WETH, token);
        (reserveInput, reserveOutput) = WETH == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }
}
