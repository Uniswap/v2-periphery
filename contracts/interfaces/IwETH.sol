pragma solidity 0.5.14;

interface IwETH {
    function deposit() external payable;
    function withdraw(uint value) external;
}
