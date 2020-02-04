pragma solidity =0.5.16;

interface IUniswapV1Factory {
    function getExchange(address) external returns (address);
}
