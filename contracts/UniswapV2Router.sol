pragma solidity =0.5.16;

import './interfaces/IUniswapV2Router.sol';
import './UniswapV2Helper.sol';
import './interfaces/V2/IUniswapV2Factory.sol';
import './interfaces/IWETH.sol';

contract UniswapV2Router is IUniswapV2Router, UniswapV2Helper {
    bytes4 public constant transferSelector = bytes4(keccak256(bytes('transfer(address,uint256)')));
    bytes4 public constant transferFromSelector = bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));

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

    constructor(address _WETH) public {
        WETH = _WETH;
    }

    function() external payable {
        require(msg.sender == WETH, 'Router: INVALID_ETH_TRANSFER'); // only accept ETH from the WETH contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) private returns (uint amountA, uint amountB) {
        if (IUniswapV2Factory(factory).getExchange(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createExchange(tokenA, tokenB); // create exchange if it doesn't exist
        }
        (uint reserveA, uint reserveB) = getReserves(tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = quote(amountADesired, reserveA, reserveB);
            uint amountAOptimal = quote(amountBDesired, reserveB, reserveA);
            if (amountBOptimal <= amountBDesired) {
                (amountA, amountB) = (amountADesired, amountBOptimal);
                require(amountB >= amountBMin, 'Router: INSUFFICIENT_B_AMOUNT');
            } else {
                assert(amountAOptimal <= amountADesired);
                (amountA, amountB) = (amountAOptimal, amountBDesired);
                require(amountA >= amountAMin, 'Router: INSUFFICIENT_A_AMOUNT');
            }
        }
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address exchange = exchangeFor(tokenA, tokenB);
        _safeTransferFrom(tokenA, msg.sender, exchange, amountA);
        _safeTransferFrom(tokenB, msg.sender, exchange, amountB);
        liquidity = IUniswapV2Exchange(exchange).mint(to);
    }
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(token, WETH, amountTokenDesired, msg.value, amountTokenMin, amountETHMin);
        address exchange = exchangeFor(token, WETH);
        _safeTransferFrom(token, msg.sender, exchange, amountToken);
        IWETH(WETH).deposit.value(amountETH)();
        assert(IWETH(WETH).transfer(exchange, amountETH));
        liquidity = IUniswapV2Exchange(exchange).mint(to);
        if (msg.value > amountETH) {
            _safeTransferETH(msg.sender, msg.value - amountETH); // refund dust eth
        }
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
        address exchange = exchangeFor(tokenA, tokenB);
        IUniswapV2Exchange(exchange).transferFrom(msg.sender, exchange, liquidity); // send liquidity to exchange
        (uint amount0, uint amount1) = IUniswapV2Exchange(exchange).burn(to);
        (address token0,) = sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
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
        address exchange = exchangeFor(tokenA, tokenB);
        IUniswapV2Exchange(exchange).permit(msg.sender, address(this), liquidity, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
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
        address exchange = exchangeFor(token, WETH);
        IUniswapV2Exchange(exchange).permit(msg.sender, address(this), liquidity, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** SWAP ****
    function _swap(uint[] memory amounts, address[] memory path, address _to) private {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? exchangeFor(output, path[i + 2]) : _to;
            IUniswapV2Exchange(exchangeFor(input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'Router: INSUFFICIENT_OUTPUT_AMOUNT');
        _safeTransferFrom(path[0], msg.sender, exchangeFor(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        amounts = getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, 'Router: EXCESSIVE_INPUT_AMOUNT');
        _safeTransferFrom(path[0], msg.sender, exchangeFor(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'Router: INVALID_PATH');
        amounts = getAmountsOut(msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit.value(amounts[0])();
        assert(IWETH(WETH).transfer(exchangeFor(path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'Router: INVALID_PATH');
        amounts = getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, 'Router: EXCESSIVE_INPUT_AMOUNT');
        _safeTransferFrom(path[0], msg.sender, exchangeFor(path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        _safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'Router: INVALID_PATH');
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'Router: INSUFFICIENT_OUTPUT_AMOUNT');
        _safeTransferFrom(path[0], msg.sender, exchangeFor(path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        _safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'Router: INVALID_PATH');
        amounts = getAmountsIn(amountOut, path);
        require(amounts[0] <= msg.value, 'Router: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit.value(amounts[0])();
        assert(IWETH(WETH).transfer(exchangeFor(path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        if (msg.value > amounts[0]) {
            _safeTransferETH(msg.sender, msg.value - amounts[0]); // refund dust eth
        }
    }
}
