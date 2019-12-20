pragma solidity 0.5.15;

interface IwETH {
    function deposit() external payable;
    function withdraw(uint) external;
}
