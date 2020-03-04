pragma solidity =0.5.16;

import '../interfaces/V2/IUniswapV2Callee.sol';
import '../interfaces/V2/IUniswapV2Factory.sol';
import '../interfaces/V2/IUniswapV2Exchange.sol';

contract UniswapV2Callee is IUniswapV2Callee {
    // factory address is identical across mainnet and testnets but differs between testing and deployed environments
    IUniswapV2Factory public constant factory = IUniswapV2Factory(0xdCCc660F92826649754E357b11bd41C31C0609B9);

    function uniswapV2Call(
        address,       /* sender  */
        uint256,       /* amount0 */
        uint256,       /* amount1 */
        bytes calldata /* data    */
    ) external {
        address token0 = IUniswapV2Exchange(msg.sender).token0();
        address token1 = IUniswapV2Exchange(msg.sender).token1();
        require(factory.getExchange(token0, token1) == msg.sender, 'FORBIDDEN');
        // execute arbitrary logic here 💥
    }
}
