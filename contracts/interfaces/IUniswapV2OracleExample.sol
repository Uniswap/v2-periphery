pragma solidity 0.5.15;

interface IUniswapV2OracleExample {
    function exchange() external returns (address);
    function token0() external returns (address);
    function token1() external returns (address);
    function period() external returns (uint);
    function initialized() external returns (bool);
    function price0Average() external returns (uint);
    function price1Average() external returns (uint);

    function quote(address tokenIn, uint amountIn) external view returns (uint amountOut);

    function initialize() external;
    function update() external;
}
