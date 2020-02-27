pragma solidity =0.5.16;

import '../interfaces/V2/IUniswapV2Callee.sol';
import '../interfaces/V2/IUniswapV2Exchange.sol';
import '../interfaces/V2/IUniswapV2Factory.sol';

contract UniswapV2Callee is IUniswapV2Callee {
    address public factory;

    constructor(address _factory) public {
        factory = _factory;
    }

    function uniswapV2Call(
        address, /* sender */
        uint256, /*amount0 */
        uint256, /*amount1 */
        bytes calldata /* data */
    ) external {
        address token0 = IUniswapV2Exchange(msg.sender).token0();
        address token1 = IUniswapV2Exchange(msg.sender).token1();
        require(IUniswapV2Factory(factory).getExchange(token0, token1) == msg.sender, 'FORBIDDEN');
        // execute arbitrary logic here...
    }
}
