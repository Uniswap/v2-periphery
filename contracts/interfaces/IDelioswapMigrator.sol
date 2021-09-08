pragma solidity >=0.5.0;

interface IDelioswapMigrator {
    function migrate(address token, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external;
}
