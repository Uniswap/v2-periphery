pragma solidity =0.5.16;

import './interfaces/IUniswapV2Helper.sol';
import './libraries/SafeMath.sol';
import './interfaces/V2/IUniswapV2Factory.sol';
import './interfaces/V2/IUniswapV2Exchange.sol';

contract UniswapV2Helper is IUniswapV2Helper {
    using SafeMath for uint;

    // factory address is identical across mainnet and testnets but differs between testing and deployed environments
    IUniswapV2Factory public constant factory = IUniswapV2Factory(0xdCCc660F92826649754E357b11bd41C31C0609B9);
    bytes32 public constant initCodeHash = 0x762dbd0ad132fda0dfcfbc963d8f43f78fc3e23b604fc4c34f61c2ca7b3e1b36;

    function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'Helper: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'Helper: ZERO_ADDRESS');
    }

    function exchangeFor(address tokenA, address tokenB) public pure returns (address exchange) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        exchange = address(uint(keccak256(abi.encodePacked(
            hex'ff',
            factory,
            keccak256(abi.encodePacked(token0, token1)),
            initCodeHash
        ))));
    }

    function getReserves(address tokenA, address tokenB) public view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        if (tokenA == token0) {
            (reserveA, reserveB,) = IUniswapV2Exchange(exchangeFor(tokenA, tokenB)).getReserves();
        } else {
            (reserveB, reserveA,) = IUniswapV2Exchange(exchangeFor(tokenA, tokenB)).getReserves();   
        }
    }

    function quote(uint amountA, uint reserveA, uint reserveB) public pure returns (uint amountB) {
        require(amountA > 0, 'Helper: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'Helper: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }
    
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure returns (uint amountOut) {
        require(amountIn > 0, 'Router: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'Router: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public pure returns (uint amountIn) {
        require(amountOut > 0, 'Router: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'Router: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }
 
    function getAmountsOut(uint amountIn, address[] memory path) public view returns (uint[] memory amounts) {
        require(path.length >= 2, 'Router: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    function getAmountsIn(uint amountOut, address[] memory path) public view returns (uint[] memory amounts) {
        require(path.length >= 2, 'Router: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
