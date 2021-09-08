pragma solidity >=0.5.0;

interface IDelioswapV1Factory {
    function getExchange(address) external view returns (address);
}
