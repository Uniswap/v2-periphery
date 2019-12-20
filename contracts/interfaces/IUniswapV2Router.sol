pragma solidity 0.5.15;

interface IUniswapV2Router {
    function factory() external returns (address);
    function WETH() external returns (address);
}
