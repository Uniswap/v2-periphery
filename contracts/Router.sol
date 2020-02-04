pragma solidity =0.5.16;

import './interfaces/IRouter.sol';
import './libraries/SafeMath.sol';
import './interfaces/V2/IUniswapV2Factory.sol';
import './interfaces/V2/IUniswapV2Exchange.sol';
import './interfaces/IWETH.sol';

contract Router is IRouter {
    using SafeMath for uint;

    bytes4 public constant transferSelector = bytes4(keccak256(bytes('transfer(address,uint256)')));
    bytes4 public constant transferFromSelector = bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));

    address public factory;
    address public WETH;

    // **** TRANSFER HELPERS ****
    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(transferSelector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Router: TRANSFER_FAILED');
    }
    function _safeTransferFrom(address token, address from, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(transferFromSelector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Router: TRANSFER_FROM_FAILED');
    }
    function _safeTransferETH(address to, uint value) private {
        (bool success,) = to.call.value(value)('');
        require(success, 'Router: ETH_TRANSFER_FAILED');
    }

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'Router: EXPIRED');
        _;
    }

    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }

    // payable fallback to receive ETH from the WETH contract
    function() external payable {
        require(msg.sender == WETH, 'Router: INVALID_ETH_TRANSFER');
    }

    // **** GENERAL HELPERS ****
    function _getExchange(address tokenA, address tokenB) private view returns (address exchange) {
        exchange = IUniswapV2Factory(factory).getExchange(tokenA, tokenB);
        require(exchange != address(0), 'Router: NO_EXCHANGE');
    }
    function _guaranteeExchange(address tokenA, address tokenB) private returns (address exchange) {
        exchange = IUniswapV2Factory(factory).getExchange(tokenA, tokenB);
        if (exchange == address(0)) exchange = IUniswapV2Factory(factory).createExchange(tokenA, tokenB);
    }
    function _getReservesSorted(address exchange, address tokenA) private view returns (uint reserveA, uint reserveB) {
        if (tokenA == IUniswapV2Exchange(exchange).token0()) {
            (reserveA, reserveB,) = IUniswapV2Exchange(exchange).getReserves();
        } else {
            (reserveB, reserveA,) = IUniswapV2Exchange(exchange).getReserves();   
        }
    }

    // **** PRICING HELPERS ****
    function _getAmounts(uint amountAIn, uint amountBIn, uint reserveA, uint reserveB)
        public
        pure
        returns (uint amountA, uint amountB)
    {
        require(amountAIn > 0 && amountBIn > 0, 'Router: INSUFFICIENT_LIQUIDITY');
        if (reserveA != 0 && reserveB != 0) {
            amountA = amountBIn.mul(reserveA) / reserveB;
            if (amountA <= amountAIn) {
                amountB = amountBIn;
            } else {
                amountA = amountAIn;
                amountB = amountAIn.mul(reserveB) / reserveA;
            }
        } else {
            amountA = amountAIn;
            amountB = amountBIn;
        }
    }
    function _getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure returns (uint amountOut) {
        require(amountIn > 0, 'Router: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'Router: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }
    function _getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public pure returns (uint amountIn) {
        require(amountOut > 0, 'Router: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'Router: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }
    function _getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        returns (uint[] memory, address[] memory)
    {
        require(path.length >= 2, 'Router: INVALID_PATH');
        uint[] memory amountsOut = new uint[](path.length - 1);
        address[] memory exchanges = new address[](path.length - 1);
        uint reserveIn;
        uint reserveOut;
        for (uint i; i < path.length - 1; i++) {
            exchanges[i] = _getExchange(path[i], path[i + 1]);
            (reserveIn, reserveOut) = _getReservesSorted(exchanges[i], path[i]);
            amountsOut[i] = _getAmountOut(i == 0 ? amountIn : amountsOut[i - 1], reserveIn, reserveOut);
        }
        return (amountsOut, exchanges);
    }
    function _getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        returns (uint[] memory, address[] memory)
    {
        require(path.length >= 2, 'Router: INVALID_PATH');
        uint[] memory amountsIn = new uint[](path.length - 1);
        address[] memory exchanges = new address[](path.length - 1);
        uint reserveIn;
        uint reserveOut;
        for (uint i = path.length - 1; i > 0; i--) {
            exchanges[i - 1] = _getExchange(path[i - 1], path[i]);
            (reserveIn, reserveOut) = _getReservesSorted(exchanges[i - 1], path[i - 1]);
            amountsIn[i - 1] = _getAmountIn(i == path.length - 1 ? amountOut : amountsIn[i], reserveIn, reserveOut);
        }
        return (amountsIn, exchanges);
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
    ) external ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        address exchange = _guaranteeExchange(tokenA, tokenB);
        // the following is done manually to avoid stack too deep errors
        uint reserveA;
        uint reserveB;
        if (tokenA == IUniswapV2Exchange(exchange).token0()) {
            (reserveA, reserveB,) = IUniswapV2Exchange(exchange).getReserves();
        } else {
            (reserveB, reserveA,) = IUniswapV2Exchange(exchange).getReserves();   
        }
        (amountA, amountB) = _getAmounts(amountAIn, amountBIn, reserveA, reserveB);
        require(amountA >= amountAMin, 'Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'Router: INSUFFICIENT_B_AMOUNT');
        _safeTransferFrom(tokenA, msg.sender, exchange, amountA);
        _safeTransferFrom(tokenB, msg.sender, exchange, amountB);
        liquidity = IUniswapV2Exchange(exchange).mint(to);
    }
    function addLiquidityETH(
        address token,
        uint amountTokenIn,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        uint amountETHIn = msg.value;
        address exchange = _guaranteeExchange(token, WETH);
        (uint reserveToken, uint reserveETH) = _getReservesSorted(exchange, token);
        (amountToken, amountETH) = _getAmounts(amountTokenIn, amountETHIn, reserveToken, reserveETH);
        require(amountToken >= amountTokenMin, 'Router: INSUFFICIENT_TOKEN_AMOUNT');
        require(amountETH >= amountETHMin, 'Router: INSUFFICIENT_ETH_AMOUNT');
        _safeTransferFrom(token, msg.sender, exchange, amountToken);
        IWETH(WETH).deposit.value(amountETH)();
        assert(IWETH(WETH).transfer(exchange, amountETH));
        liquidity = IUniswapV2Exchange(exchange).mint(to);
        if (amountETHIn > amountETH) _safeTransferETH(msg.sender, amountETHIn - amountETH); // refund dust eth if needed
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public ensure(deadline) returns (uint amountA, uint amountB) {
        require(liquidity > 0, 'Router: INSUFFICIENT_LIQUIDITY');
        address exchange = _getExchange(tokenA, tokenB);
        IUniswapV2Exchange(exchange).transferFrom(msg.sender, exchange, liquidity);
        (uint amount0, uint amount1) = IUniswapV2Exchange(exchange).burn(to);
        (amountA, amountB) = tokenA == IUniswapV2Exchange(exchange).token0() ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'Router: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        _safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        _safeTransferETH(to, amountETH);
    }
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB) {
        address exchange = _getExchange(tokenA, tokenB);
        IUniswapV2Exchange(exchange).permit(msg.sender, address(this), liquidity, deadline, v, r, s);
        return removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH) {
        address exchange = _getExchange(token, WETH);
        IUniswapV2Exchange(exchange).permit(msg.sender, address(this), liquidity, deadline, v, r, s);
        return removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** SWAP ****
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountOut) {
        (uint[] memory amountsOut, address[] memory exchanges) = _getAmountsOut(amountIn, path);
        amountOut = amountsOut[amountsOut.length - 1];
        require(amountOut >= amountOutMin, 'Router: INSUFFICIENT_OUTPUT_AMOUNT');
        _safeTransferFrom(path[0], msg.sender, exchanges[0], amountIn); // send tokens to first exchange
        for (uint i; i < exchanges.length; i++) {
            IUniswapV2Exchange(exchanges[i]).swap(
                path[i], 
                amountsOut[i],
                i < exchanges.length - 1 ? exchanges[i + 1] : to
            );
        }
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountIn) {
        (uint[] memory amountsIn, address[] memory exchanges) = _getAmountsIn(amountOut, path);
        amountIn = amountsIn[0];
        require(amountIn <= amountInMax, 'Router: EXCESSIVE_INPUT_AMOUNT');
        _safeTransferFrom(path[0], msg.sender, exchanges[0], amountIn); // send tokens to first exchange
        for (uint i; i < exchanges.length; i++) {
            IUniswapV2Exchange(exchanges[i]).swap(
                path[i], 
                i < exchanges.length - 1 ? amountsIn[i + 1] : amountOut,
                i < exchanges.length - 1 ? exchanges[i + 1] : to
            );
        }
    }
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        ensure(deadline)
        returns (uint amountOut)
    {
        require(path[0] == WETH, 'Router: INVALID_PATH');
        uint amountIn = msg.value;
        (uint[] memory amountsOut, address[] memory exchanges) = _getAmountsOut(amountIn, path);
        amountOut = amountsOut[amountsOut.length - 1];
        require(amountOut >= amountOutMin, 'Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit.value(amountIn)();
        assert(IWETH(WETH).transfer(exchanges[0], amountIn)); // send tokens to first exchange
        for (uint i; i < exchanges.length; i++) {
            IUniswapV2Exchange(exchanges[i]).swap(
                path[i], 
                amountsOut[i],
                i < exchanges.length - 1 ? exchanges[i + 1] : to
            );
        }
    }
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        ensure(deadline)
        returns (uint amountIn)
    {
        require(path[path.length - 1] == WETH, 'Router: INVALID_PATH');
        (uint[] memory amountsIn, address[] memory exchanges) = _getAmountsIn(amountOut, path);
        amountIn = amountsIn[0];
        require(amountIn <= amountInMax, 'Router: EXCESSIVE_INPUT_AMOUNT');
        _safeTransferFrom(path[0], msg.sender, exchanges[0], amountIn); // send tokens to first exchange
        for (uint i; i < exchanges.length; i++) {
            IUniswapV2Exchange(exchanges[i]).swap(
                path[i], 
                i < exchanges.length - 1 ? amountsIn[i + 1] : amountOut,
                i < exchanges.length - 1 ? exchanges[i + 1] : address(this)
            );
        }
        IWETH(WETH).withdraw(amountOut);
        _safeTransferETH(to, amountOut);
    }
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        ensure(deadline)
        returns (uint amountOut)
    {
        require(path[path.length - 1] == WETH, 'Router: INVALID_PATH');
        (uint[] memory amountsOut, address[] memory exchanges) = _getAmountsOut(amountIn, path);
        amountOut = amountsOut[amountsOut.length - 1];
        require(amountOut >= amountOutMin, 'Router: INSUFFICIENT_OUTPUT_AMOUNT');
        _safeTransferFrom(path[0], msg.sender, exchanges[0], amountIn); // send tokens to first exchange
        for (uint i; i < exchanges.length; i++) {
            IUniswapV2Exchange(exchanges[i]).swap(
                path[i], 
                amountsOut[i],
                i < exchanges.length - 1 ? exchanges[i + 1] : address(this)
            );
        }
        IWETH(WETH).withdraw(amountOut);
        _safeTransferETH(to, amountOut);
    }
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        ensure(deadline)
        returns (uint amountIn)
    {
        require(path[0] == WETH, 'Router: INVALID_PATH');
        uint amountInMax = msg.value;
        (uint[] memory amountsIn, address[] memory exchanges) = _getAmountsIn(amountOut, path);
        amountIn = amountsIn[0];
        require(amountIn <= amountInMax, 'Router: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit.value(amountIn)();
        assert(IWETH(WETH).transfer(exchanges[0], amountIn)); // send tokens to first exchange
        for (uint i; i < exchanges.length; i++) {
            IUniswapV2Exchange(exchanges[i]).swap(
                path[i], 
                i < exchanges.length - 1 ? amountsIn[i + 1] : amountOut,
                i < exchanges.length - 1 ? exchanges[i + 1] : to
            );
        }
        if (amountInMax > amountIn) _safeTransferETH(msg.sender, amountInMax - amountIn); // refund dust eth if needed
    }
}
