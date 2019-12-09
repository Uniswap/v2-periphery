pragma solidity 0.5.13;

interface IUniswapV2OracleExample {
    function exchangeAddress() external returns (address);
    function price0() external returns (uint);
    function price1() external returns (uint);
    function period() external returns (uint);

    function quote0(uint amount0) external view returns (uint amount1);
    function quote1(uint amount1) external view returns (uint amount0);

    function initialize() external;
    function update() external;
}
