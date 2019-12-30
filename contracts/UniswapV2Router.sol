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

    function _safeTransfer(address token, address to, uint value) private {
        // solium-disable-next-line security/no-low-level-calls
        (bool success, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "UniswapV2: TRANSFER_FAILED");
    }
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


    function _checkDeadline(uint deadline) private view {
        // solium-disable-next-line security/no-block-members
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
    }


    function _getExchange(address tokenA, address tokenB) private view returns (address exchange) {
        exchange = IUniswapV2Factory(factory).getExchange(tokenA, tokenB);
        require(exchange != address(0), "UniswapV2Router: NO_EXCHANGE");
    }
    function _getExchangeETH(address token) private view returns (address exchange) {
        exchange = IUniswapV2Factory(factory).getExchange(token, WETH);
        require(exchange != address(0), "UniswapV2Router: NO_EXCHANGE");
    }


    function _getReserves(address exchange, address token) private view returns (uint112, uint112) {
        (uint112 reserve0, uint112 reserve1) = (IUniswapV2(exchange).reserve0(), IUniswapV2(exchange).reserve1());
        return token == IUniswapV2(exchange).token0() ? (reserve0, reserve1) : (reserve1, reserve0);
    }


    function _sendToExchange(address token, address exchange, uint amount) private {
        _safeTransferFrom(token, msg.sender, exchange, amount);
    }
    function _sendToExchangeETH(address exchange, uint amount) private {
        IwETH(WETH).deposit.value(amount)();
        require(IERC20(WETH).transfer(exchange, amount), "UniswapV2Router: TRANSFER_FAILED");
    }
    function _sendToSender(address token, uint amount) private {
        _safeTransferFrom(token, address(this), msg.sender, amount);
    }
    function _sendToSenderETH(uint amount) private {
        (bool success,) = msg.sender.call.value(amount)(""); // solium-disable-line security/no-call-value
        require(success, "UniswapV2Router: CALL_FAILED");
    }


    function _sendToSenderLiquidity(address exchange, uint amount) private {
        IERC20(exchange).transfer(msg.sender, amount);
    }
    function addLiquidity(
        address tokenA, address tokenB, uint amountAIn, uint amountBIn, uint amountAMin, uint amountBMin, uint deadline
    )
        external returns (uint liquidity)
    {
        _checkDeadline(deadline);
        address exchange = IUniswapV2Factory(factory).getExchange(tokenA, tokenB);
        if (exchange == address(0)) exchange = IUniswapV2Factory(factory).createExchange(tokenA, tokenB);
        (uint112 reserveA, uint112 reserveB) = _getReserves(exchange, tokenA);
        uint amountABest = amountBIn.mul(reserveA) / reserveB;
        uint amountBBest;
        if (amountABest >= amountAIn) { // send all of amountBIn
            require(amountABest > amountAMin, "UniswapV2Router: INSUFFICIENT_A_AMOUNT");
            _sendToExchange(tokenA, exchange, amountABest);
            _sendToExchange(tokenB, exchange, amountBIn);
        } else { // send all of amountAIn
            amountBBest = amountAIn.mul(reserveB) / reserveA;
            require(amountBBest > amountBMin, "UniswapV2Router: INSUFFICIENT_B_AMOUNT");
            _sendToExchange(tokenA, exchange, amountAIn);
            _sendToExchange(tokenB, exchange, amountBBest);
        }
        liquidity = IUniswapV2(exchange).mint();
        _sendToSenderLiquidity(exchange, liquidity);
    }
    function addLiquidityETH(address token, uint amountTokenIn, uint amountTokenMin, uint amountETHMin, uint deadline)
        external payable returns (uint liquidity)
    {
        _checkDeadline(deadline);
        address exchange = IUniswapV2Factory(factory).getExchange(token, WETH);
        if (exchange == address(0)) exchange = IUniswapV2Factory(factory).createExchange(token, WETH);
        (uint112 reserveToken, uint112 reserveETH) = _getReserves(exchange, token);
        uint amountETHIn = msg.value;
        uint amountTokenBest = amountETHIn.mul(reserveToken) / reserveETH;
        uint amountETHBest;
        if (amountTokenBest >= amountETHBest) { // send all of amountETHIn
            require(amountTokenBest > amountTokenMin, "UniswapV2Router: INSUFFICIENT_TOKEN_AMOUNT");
            _sendToExchange(token, exchange, amountTokenBest);
            _sendToExchangeETH(exchange, amountETHIn);
        } else { // send all of amountTokenIn
            amountETHBest = amountTokenIn.mul(reserveETH) / reserveToken;
            require(amountETHBest > amountETHMin, "UniswapV2Router: INSUFFICIENT_ETH_AMOUNT");
            _sendToExchange(token, exchange, amountTokenIn);
            _sendToExchangeETH(exchange, amountETHBest);
        }
        liquidity = IUniswapV2(exchange).mint();
        _sendToSenderLiquidity(exchange, liquidity);
        if (amountETHBest > 0) _sendToSenderETH(amountETHIn.sub(amountETHBest)); // if any, refund dust eth
    }


    function _sendToExchangeLiquidity(address exchange, address from, uint amount) private {
        IERC20(exchange).transferFrom(from, exchange, amount);
    }
    function removeLiquidity(
        address tokenA, address tokenB, uint liquidity, uint amountAMin, uint amountBMin, uint deadline
    )
        external returns (uint amountA, uint amountB)
    {
        _checkDeadline(deadline);
        address exchange = _getExchange(tokenA, tokenB);
        _sendToExchangeLiquidity(exchange, msg.sender, liquidity);
        (uint amount0, uint amount1) = IUniswapV2(exchange).burn();
        (amountA, amountB) = tokenA == IUniswapV2(exchange).token0() ? (amount0, amount1) : (amount1, amount0);
        require(amountA > amountAMin, "UniswapV2Router: INSUFFICIENT_A_AMOUNT");
        require(amountB > amountBMin, "UniswapV2Router: INSUFFICIENT_B_AMOUNT");
        _sendToSender(tokenA, amountA);
        _sendToSender(tokenB, amountB);
    }
    function removeLiquidityETH(address token, uint liquidity, uint amountTokenMin, uint amountETHMin, uint deadline)
        external returns (uint amountToken, uint amountETH)
    {
        _checkDeadline(deadline);
        address exchange = _getExchange(token, WETH);
        _sendToExchangeLiquidity(exchange, msg.sender, liquidity);
        (uint amount0, uint amount1) = IUniswapV2(exchange).burn();
        (amountToken, amountETH) = token == IUniswapV2(exchange).token0() ? (amount0, amount1) : (amount1, amount0);
        require(amountToken > amountTokenMin, "UniswapV2Router: INSUFFICIENT_TOKEN_AMOUNT");
        require(amountETH > amountETHMin, "UniswapV2Router: INSUFFICIENT_ETH_AMOUNT");
        _sendToSender(token, amountToken);
        _sendToSenderETH(amountETH);
    }

    function _getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure returns (uint amountOut) {
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2: INSUFFICIENT_RESERVES");
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }
    function _swap(address exchange, address tokenIn, uint amountOut) private {
        IUniswapV2(exchange).swap(tokenIn, amountOut);
    }
    function swapExactTokensForTokens(
        address tokenIn, uint amountIn, address tokenOut, uint amountOutMin, uint deadline
    )
        external
    {
        _checkDeadline(deadline);
        address exchange = _getExchange(tokenIn, tokenOut);
        (uint112 reserveIn, uint112 reserveOut) = _getReserves(exchange, tokenIn);
        uint amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut > amountOutMin, "UniswapV2Router: MINIMUM_NOT_EXCEEDED");
        _sendToExchange(tokenIn, exchange, amountIn);
        _swap(exchange, tokenIn, amountOut);
        _sendToSender(tokenOut, amountOut);
    }

    // TODO implement all the other functions (eth x exact), the below are old versions

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
