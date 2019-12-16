pragma solidity 0.5.14;

interface IUniswapV2OracleExample {
    function exchange() external returns (address);
    function price0Average() external returns (uint224);
    function price1Average() external returns (uint224);
    function period() external returns (uint);
    function initialized() external returns (bool);

    function quote0(uint amount0) external view returns (uint amount1);
    function quote1(uint amount1) external view returns (uint amount0);

    function initialize() external;
    function update() external;
}
