pragma solidity 0.5.15;

interface IUniswapV1Factory {
    function getExchange(address) external returns (address);
}
