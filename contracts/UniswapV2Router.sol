pragma solidity 0.5.15;

import "./interfaces/IUniswapV2Router.sol";
import "./libraries/SafeMath.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IwETH.sol";

contract UniswapV2Router is IUniswapV2Router {
    using SafeMath for uint;

    address public factory;
    address public WETH;

    function _safeTransferFrom(address token, address from, address to, uint value) private {
        // solium-disable-next-line security/no-low-level-calls
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "UniswapV2Router: TRANSFER_FROM_FAILED");
    }

    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }

    // function _checkDeadline(uint deadline) private view {
    //     // solium-disable-next-line security/no-block-members
    //     require(deadline > block.timestamp, "UniswapV2Router: EXPIRED");
    // }

    // // ** send tokens or weth to an exchange **
    // function _sendToExchange(address token, address exchange, uint amount) private {
    //     _safeTransferFrom(token, msg.sender, exchange, amount);
    // }
    // function _sendToExchange(address exchange, uint amount) private {
    //     IwETH(WETH).deposit.value(amount)();
    //     require(IERC20(WETH).transfer(exchange, amount), "UniswapV2Router: TRANSFER_FAILED");
    // }

    // function _getReserves(address exchange, address tokenA) private view returns (uint112 reserveA, uint112 reserveB) {
    //     (uint112 reserve0, uint112 reserve1) = (IUniswapV2(exchange).reserve0(), IUniswapV2(exchange).reserve1());
    //     return tokenA == IUniswapV2(exchange).token0() ? (reserve0, reserve1) : (reserve1, reserve0);
    // }

    // function addLiquidity(
    //     address tokenA, address tokenB, uint amountAIn, uint amountBIn, uint amountAMin, uint amountBMin, uint deadline
    // )
    //     external returns (uint liquidity)
    // {
    //     _checkDeadline(deadline);
    //     address exchange = IUniswapV2Factory(factory).getExchange(tokenA, tokenB);
    //     if (exchange == address(0)) exchange = IUniswapV2Factory(factory).createExchange(tokenA, tokenB);
    //     (uint112 reserveA, uint112 reserveB) = _getReserves(exchange, tokenA);
    //     uint amountBBest = amountAIn.mul(reserveB) / reserveA;
    //     uint amountABest;
    //     if (amountBBest >= amountBIn) { // send all of amountBIn
    //         amountABest = amountBIn.mul(reserveA) / reserveB;
    //         require(amountABest >= amountAMin, "UniswapV2Router: INSUFFICIENT_AMOUNT_A");
    //         _safeTransferFrom(tokenA, msg.sender, exchange, amountABest);
    //         _safeTransferFrom(tokenB, msg.sender, exchange, amountBIn);
    //         liquidity = IUniswapV2(exchange).mint();
    //     } else { // send all of amountAIn
    //         require(amountBBest >= amountBMin, "UniswapV2Router: INSUFFICIENT_AMOUNT_B");
    //         _safeTransferFrom(tokenA, msg.sender, exchange, amountAIn);
    //         _safeTransferFrom(tokenB, msg.sender, exchange, amountBBest);
    //         liquidity = IUniswapV2(exchange).mint();
    //     }
    // }

    // function _getReserves(address exchange) private view returns (uint112 reserve0, uint112 reserve1) {
    //     return (IUniswapV2(exchange).reserve0(), IUniswapV2(exchange).reserve1());
    // }

    // // ** get a token<>token or token<>weth exchange **
    // function _getExchange(address tokenA, address tokenB) private view returns (IUniswapV2 exchange) {
    //     exchange = IUniswapV2(IUniswapV2Factory(factory).getExchange(tokenA, tokenB));
    //     require(address(exchange) != address(0), "UniswapV2Router: NO_EXCHANGE");
    // }
    // function _getExchange(address token) private view returns (IUniswapV2 exchange) {
    //     exchange = IUniswapV2(IUniswapV2Factory(factory).getExchange(token, WETH));
    //     require(address(exchange) != address(0), "UniswapV2Router: NO_EXCHANGE");
    // }

    // function swap(IUniswapV2 exchange, address output, address recipient) private returns (uint amountOutput) {
    //     amountOutput = exchange.token0() == output ? exchange.swap1(recipient) : exchange.swap0(recipient);
    // }

    // function sendToRecipient(uint amount, address recipient) private {
    //     IwETH(WETH).withdraw(amount);
    //     require(IERC20(WETH).transfer(recipient, amount),  "UniswapV2Router: TRANSFER_FAILED");
    // }

    // function verify(uint amount, uint amountMinimum) private pure {
    //     require(amount >= amountMinimum, "UniswapV2Router: MINIMUM_NOT_EXCEEDED");
    // }

    // function swapExactTokensForTokens(
    //     address input, uint amountInput, address output, address recipient, uint amountOutputMinimum, uint deadline
    // )
    //     external
    // {
    //     _checkDeadline(deadline);
    //     IUniswapV2 exchange = getExchange(input, output);
    //     sendToExchange(input, exchange, amountInput);
    //     uint amountOutput = swap(exchange, output, recipient);
    //     verify(amountOutput, amountOutputMinimum);
    // }

    // function swapExactETHForTokens(address output, address recipient, uint amountOutputMinimum, uint deadline)
    //     external payable
    // {
    //     _checkDeadline(deadline);
    //     IUniswapV2 exchange = getExchange(output);
    //     sendToExchange(exchange, msg.value);
    //     uint amountOutput = swap(exchange, output, recipient);
    //     verify(amountOutput, amountOutputMinimum);
    // }

    // function swapExactTokensForETH(
    //     address input, uint amountInput, address recipient, uint amountOutputMinimum, uint deadline
    // )
    //     external
    // {
    //     _checkDeadline(deadline);
    //     IUniswapV2 exchange = getExchange(input);
    //     sendToExchange(input, exchange, amountInput);
    //     uint amountOutput = swap(exchange, WETH, address(this));
    //     verify(amountOutput, amountOutputMinimum);
    //     sendToRecipient(amountOutput, recipient);
    // }

    // function getOutputPrice(uint outputAmount, uint inputReserve, uint outputReserve) public pure returns (uint) {
    //     require(inputReserve > 0 && outputReserve > 0, "UniswapV2: INSUFFICIENT_RESERVES");
    //     uint numerator = inputReserve.mul(outputAmount).mul(1000);
    //     uint denominator = outputReserve.sub(outputAmount).mul(997);
    //     return (numerator / denominator).add(1);
    // }

    // function getAmountInput(IUniswapV2 exchange, address output, uint amountOutput, uint amountInputMaximum)
    //     private view returns (uint amountInput)
    // {
    //     uint112 reserve0 = exchange.reserve0();
    //     uint112 reserve1 = exchange.reserve1();
    //     amountInput = exchange.token0() == output ?
    //         getOutputPrice(amountOutput, reserve1, reserve0) :
    //         getOutputPrice(amountOutput, reserve0, reserve1);
    //     require(amountInput <= amountInputMaximum, "UniswapV2Router: MAXIMUM_EXCEEDED");
    // }

    // function swapTokensForExactTokens(
    //     address input, uint amountOutput, address output, address recipient, uint amountInputMaximum, uint deadline
    // )
    //     external
    // {
    //     _checkDeadline(deadline);
    //     IUniswapV2 exchange = getExchange(input, output);
    //     uint amountInput = getAmountInput(exchange, output, amountOutput, amountInputMaximum);
    //     sendToExchange(input, exchange, amountInput);
    //     swap(exchange, output, recipient);
    // }

    // function swapETHForExactTokens(address output, uint amountOutput, address recipient, uint deadline)
    //     external payable
    // {
    //     _checkDeadline(deadline);
    //     IUniswapV2 exchange = getExchange(output);
    //     uint amountInput = getAmountInput(exchange, output, amountOutput, msg.value);
    //     sendToExchange(exchange, amountInput);
    //     swap(exchange, output, recipient);
    //     // refund dust ETH
    //     uint dust = msg.value.sub(amountInput);
    //     if (dust > 0) {
    //         (bool success,) = msg.sender.call.value(dust)(""); // solium-disable-line security/no-call-value
    //         require(success, "UniswapV2Router: CALL_FAILED");
    //     }
    // }

    // function swapTokensForExactETH(
    //     address input, uint amountOutput, address recipient, uint amountInputMaximum, uint deadline
    // )
    //     external
    // {
    //     _checkDeadline(deadline);
    //     IUniswapV2 exchange = getExchange(input);
    //     uint amountInput = getAmountInput(exchange, WETH, amountOutput, amountInputMaximum);
    //     sendToExchange(input, exchange, amountInput);
    //     swap(exchange, WETH, address(this));
    //     sendToRecipient(amountOutput, recipient);
    // }
}
