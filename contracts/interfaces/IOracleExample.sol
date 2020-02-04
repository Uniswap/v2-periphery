pragma solidity =0.5.16;

interface IOracleExample {
    function period() external returns (uint);
    function initialized() external returns (bool);
    function exchange() external returns (address);
    function token0() external returns (address);
    function token1() external returns (address);
    function price0Average() external returns (uint);
    function price1Average() external returns (uint);

    function quote(address tokenIn, uint amountIn) external view returns (uint amountOut);

    function update() external;

    function initialize() external; // only called once
}
