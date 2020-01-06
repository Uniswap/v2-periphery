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

    // **** VALUE TRANSFER HELPERS ****
    function _safeTransfer(address token, address to, uint value) private {
        // solium-disable-next-line security/no-low-level-calls
        (bool success, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "UniswapV2Router: TRANSFER_FAILED");
    }
    function _safeTransferFrom(address token, address from, address to, uint value) private {
        // solium-disable-next-line security/no-low-level-calls
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "UniswapV2Router: TRANSFER_FROM_FAILED");
    }
    function _sendETH(address to, uint value) private {
        (bool success,) = to.call.value(value)(""); // solium-disable-line security/no-call-value
        require(success, "UniswapV2Router: CALL_FAILED");
    }
    function _sendETHAsWETH(address to, uint value) private {
        IwETH(WETH).deposit.value(value)();
        _safeTransfer(WETH, to, value);
    }
    function _sendWETHAsETH(address to, uint value) private {
        IwETH(WETH).withdraw(value);
        _sendETH(to, value);
    }


    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }


    // **** GENERAL HELPERS ****
    function _checkDeadline(uint deadline) private view {
        // solium-disable-next-line security/no-block-members
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
    }
    function _getExchange(address tokenA, address tokenB) private view returns (address exchange) {
        exchange = IUniswapV2Factory(factory).getExchange(tokenA, tokenB);
        require(exchange != address(0), "UniswapV2Router: NO_EXCHANGE");
    }
    function _getReserves(address exchange, address token) private view returns (uint112, uint112) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2(exchange).getReserves();
        return token == IUniswapV2(exchange).token0() ? (reserve0, reserve1) : (reserve1, reserve0);
    }


    // **** ADD LIQUIDITY ****
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountAIn,
        uint amountBIn,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    )
        external returns (uint amountA, uint amountB, uint liquidity)
    {
        _checkDeadline(deadline);
        address exchange = IUniswapV2Factory(factory).getExchange(tokenA, tokenB);
        if (exchange == address(0)) exchange = IUniswapV2Factory(factory).createExchange(tokenA, tokenB);
        (uint112 reserveA, uint112 reserveB) = _getReserves(exchange, tokenA);
        if (reserveA == 0 && reserveB == 0) {
            amountA = amountAIn;
        } else {
            amountA = amountBIn.mul(reserveA) / reserveB;
        }
        if (amountA <= amountAIn) { // send amountA and amountBIn
            require(amountA >= amountAMin, "UniswapV2Router: INSUFFICIENT_A_AMOUNT");
            _safeTransferFrom(tokenA, msg.sender, exchange, amountA);
            _safeTransferFrom(tokenB, msg.sender, exchange, amountB = amountBIn);
        } else {
            amountB = amountAIn.mul(reserveB) / reserveA;
            require(amountB >= amountBMin, "UniswapV2Router: INSUFFICIENT_B_AMOUNT");
            _safeTransferFrom(tokenA, msg.sender, exchange, amountA = amountAIn);
            _safeTransferFrom(tokenB, msg.sender, exchange, amountB);
        }
        liquidity = IUniswapV2(exchange).mint(to);
    }
    function addLiquidityETH(
        address token, uint amountTokenIn, uint amountTokenMin, uint amountETHMin, address to, uint deadline
    )
        external payable returns (uint amountToken, uint amountETH, uint liquidity)
    {
        uint amountETHIn = msg.value;
        _checkDeadline(deadline);
        address exchange = IUniswapV2Factory(factory).getExchange(token, WETH);
        if (exchange == address(0)) exchange = IUniswapV2Factory(factory).createExchange(token, WETH);
        (uint112 reserveToken, uint112 reserveETH) = _getReserves(exchange, token);
        if (reserveToken == 0 && reserveETH == 0) {
            amountToken = amountTokenIn;
        } else {
            amountToken = amountETHIn.mul(reserveToken) / reserveETH;
        }
        if (amountToken <= amountTokenIn) { // send amountToken and amountETHIn
            require(amountToken >= amountTokenMin, "UniswapV2Router: INSUFFICIENT_TOKEN_AMOUNT");
            _safeTransferFrom(token, msg.sender, exchange, amountToken);
            _sendETHAsWETH(exchange, amountETH = amountETHIn);
        } else {
            amountETH = amountTokenIn.mul(reserveETH) / reserveToken;
            require(amountETH >= amountETHMin, "UniswapV2Router: INSUFFICIENT_ETH_AMOUNT");
            _safeTransferFrom(token, msg.sender, exchange, amountToken = amountTokenIn);
            _sendETHAsWETH(exchange, amountETH);
        }
        liquidity = IUniswapV2(exchange).mint(to);
        if (amountETHIn > amountETH) _sendETH(msg.sender, amountETHIn - amountETH); // refund dust eth (if any)
    }


    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA, address tokenB, uint liquidity, uint amountAMin, uint amountBMin, address to, uint deadline
    )
        external returns (uint amountA, uint amountB)
    {
        _checkDeadline(deadline);
        address exchange = _getExchange(tokenA, tokenB);
        _safeTransferFrom(exchange, msg.sender, exchange, liquidity);
        (uint amount0, uint amount1) = IUniswapV2(exchange).burn(to);
        (amountA, amountB) = tokenA == IUniswapV2(exchange).token0() ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "UniswapV2Router: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "UniswapV2Router: INSUFFICIENT_B_AMOUNT");
    }
    function removeLiquidityETH(
        address token, uint liquidity, uint amountTokenMin, uint amountETHMin, address to, uint deadline
    )
        external returns (uint amountToken, uint amountETH)
    {
        _checkDeadline(deadline);
        address exchange = _getExchange(token, WETH);
        _safeTransferFrom(exchange, msg.sender, exchange, liquidity);
        (uint amount0, uint amount1) = IUniswapV2(exchange).burn(address(this));
        (amountToken, amountETH) = token == IUniswapV2(exchange).token0() ? (amount0, amount1) : (amount1, amount0);
        require(amountToken >= amountTokenMin, "UniswapV2Router: INSUFFICIENT_TOKEN_AMOUNT");
        require(amountETH >= amountETHMin, "UniswapV2Router: INSUFFICIENT_ETH_AMOUNT");
        _safeTransferFrom(token, address(this), to, amountToken);
        _sendWETHAsETH(to, amountETH);
    }


    // **** SWAP ****
    function _getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) private pure returns (uint amountOut) {
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Router: INSUFFICIENT_RESERVES");
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }
    function _getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) private pure returns (uint amountIn) {
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Router: INSUFFICIENT_RESERVES");
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }
    function swapExactTokensForTokens(
        uint amountIn, address[] calldata tokens, uint amountOutMin, address to, uint deadline
    )
        external returns (uint amountOut)
    {
        require(tokens.length >= 2, "UniswapV2Router: INSUFFICIENT_NUMBER_OF_TOKENS");
        _checkDeadline(deadline);
        address[] memory recipients = new address[](tokens.length); // all the exchanges + to
        recipients[tokens.length-1] = to;
        uint[] memory amounts = new uint[](tokens.length); // amountIn + all the amountOuts
        amounts[0] = amountIn;
        for (uint i; i < tokens.length-1; i++) { // populate recipients + amounts
            recipients[i] = _getExchange(tokens[i], tokens[i+1]);
            (uint112 reserveIn, uint112 reserveOut) = _getReserves(recipients[i], tokens[i]);
            amounts[i+1] = _getAmountOut(amounts[i], reserveIn, reserveOut);
        }
        amountOut = amounts[tokens.length-1];
        require(amountOut >= amountOutMin, "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        _safeTransferFrom(tokens[0], msg.sender, recipients[0], amounts[0]); // send tokens to first exchange
        for (uint j; j < recipients.length-1; j++) { // execute all the swaps
            IUniswapV2(recipients[j]).swap(tokens[j], amounts[j+1], recipients[j+1]);
        }
    }
    function swapTokensForExactTokens(
        uint amountInMax, address[] calldata tokens, uint amountOut, address to, uint deadline
    )
        external returns (uint amountIn)
    {
        require(tokens.length >= 2, "UniswapV2Router: INSUFFICIENT_NUMBER_OF_TOKENS");
        _checkDeadline(deadline);
        address[] memory recipients = new address[](tokens.length); // all the exchanges + to
        recipients[tokens.length-1] = to;
        uint[] memory amounts = new uint[](tokens.length); // all the amountIns + amountOut
        amounts[tokens.length-1] = amountOut;
        for (uint i = tokens.length-1; i > 0; i--) { // fill out recipients and amounts
            recipients[i-1] = _getExchange(tokens[i-1], tokens[i]);
            (uint112 reserveIn, uint112 reserveOut) = _getReserves(recipients[i-1], tokens[i-1]);
            amounts[i-1] = _getAmountIn(amounts[i], reserveIn, reserveOut);
        }
        amountIn = amounts[0];
        require(amountIn <= amountInMax, "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT");
        _safeTransferFrom(tokens[0], msg.sender, recipients[0], amounts[0]); // send tokens to first exchange
        for (uint j; j < recipients.length-1; j++) { // execute all the swaps
            IUniswapV2(recipients[j]).swap(tokens[j], amounts[j+1], recipients[j+1]);
        }
    }
    // TODO implement the other (ETH x exact) functions
}
