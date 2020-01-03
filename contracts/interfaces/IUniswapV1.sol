pragma solidity 0.5.15;

interface IUniswapV1 {
    function removeLiquidity(uint, uint, uint, uint) external returns (uint, uint);
}
