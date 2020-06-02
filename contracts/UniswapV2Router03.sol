pragma solidity =0.6.6;

import './UniswapV2Router02.sol';

contract UniswapV2Router03 is UniswapV2Router02 {
    constructor(address _factory, address _WETH) public UniswapV2Router02(_factory, _WETH) {}
}
