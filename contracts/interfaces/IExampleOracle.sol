pragma solidity =0.5.16;

interface IExampleOracle {
    function period() external pure returns (uint);
    function initialized() external view returns (bool);
    function exchange() external view returns (address);

    function price0CumulativeLastCached() external view returns (uint);
    function price1CumulativeLastCached() external view returns (uint);
    function blockTimestampLastCached() external view returns (uint32);
    function price0Average() external view returns (uint224);
    function price1Average() external view returns (uint224);

    function initialize() external;
    function update() external;
    function quote(address tokenIn, uint amountIn) external view returns (uint amountOut);
}
