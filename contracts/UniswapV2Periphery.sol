pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import './interfaces/IUniswapV2Periphery.sol';
import './libraries/UniswapV2Library.sol';
import './libraries/SafeMath.sol';

contract UniswapV2Periphery is IUniswapV2Periphery {
    using SafeMath for uint;

    address public immutable override factory;

    constructor(address _factory) public {
        factory = _factory;
    }

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        return UniswapV2Library.sortTokens(tokenA, tokenB);
    }

    function pairFor(address tokenA, address tokenB) internal view returns (address pair) {
        return UniswapV2Library.pairFor(factory, tokenA, tokenB);
    }

    function getReserves(address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        return UniswapV2Library.getReserves(factory, tokenA, tokenB);
    }

    function quote(uint amountA, uint reserveA, uint reserveB) public pure override returns (uint amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure override returns (uint amountOut) {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public pure override returns (uint amountIn) {
        return UniswapV2Library.getAmountOut(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path) public view override returns (uint[] memory amounts) {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path) public view override returns (uint[] memory amounts) {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}
