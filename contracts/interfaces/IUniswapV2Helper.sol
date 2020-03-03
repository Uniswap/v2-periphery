pragma solidity =0.5.16;

interface IUniswapV2Helper {
    function factory() external pure returns (address);

    function sortTokens(address tokenA, address tokenB) external pure returns (address token0, address token1);
    function exchangeFor(address tokenA, address tokenB) external pure returns (address exchange);
    function getReserves(address tokenA, address tokenB) external view returns (uint reserveA, uint reserveB);
    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}
