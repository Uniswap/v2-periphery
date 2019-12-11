pragma solidity 0.5.13;

interface IUniswapV2OracleExample {
    function exchangeAddress() external returns (address);
    function priceAverage0() external returns (uint224);
    function priceAverage1() external returns (uint224);
    function period() external returns (uint);
    function initialized() external returns (bool);

    function quote0(uint amount0) external view returns (uint amount1);
    function quote1(uint amount1) external view returns (uint amount0);

    function initialize() external;
    function update() external;
}
