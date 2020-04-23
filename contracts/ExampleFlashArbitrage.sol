pragma solidity >=0.6.2;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

import "./interfaces/V1/IUniswapV1Factory.sol";
import "./interfaces/V1/IUniswapV1Exchange.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";
import "./libraries/SafeMath.sol";
import "./UniswapV2Library.sol";

// uses flash swaps in UniswapV2 to arbitrage against UniswapV1 with zero price risk
// i.e. any caller can provide a token pair and the liquidity in UniswapV2 will be used to move the marginal price in V1
// to be the same as the marginal price in V2, and forward any resulting profits
// all the caller pays for is gas. gas and gas prices are not considered in the arbitrage profitability.
contract ExampleFlashArbitrage is UniswapV2Library, IUniswapV2Callee {
    using SafeMath for uint;

    IUniswapV1Factory public immutable v1Factory;
    IWETH public immutable weth;

    // this is temporarily set during the callback so we can prevent ETH from accidentally being sent to this contract
    address private pendingReceiveAddress;

    constructor(IUniswapV1Factory v1Factory_, address v2Factory_, IWETH weth_) UniswapV2Library(v2Factory_) public {
        v1Factory = v1Factory_;
        weth = weth_;
    }

    // receives ETH from V1 exchanges. must first be prepared to receive via pendingReceiveAddress.
    receive() external payable {
        require(msg.sender == pendingReceiveAddress, "ExampleFlashArbitrage: RECEIVE_NOT_PENDING");
    }

    // emitted when a successful arbitrage occurs
    event Arbitrage(address token0, uint profit0, address token1, uint profit1);

    // arbitrages the token/ETH pair between Uniswap V1 and V2
    // this function deliberately excludes the possibility that you want to arbitrage weth against eth.
    // to do that you should use the WETH contract
    // the computation for optimal token/ETH pairs arbitrage amounts is simpler because it only requires one v1 swap
    function arbitrageETH(address token, address recipient) private {
        require(token != address(weth), "ExampleFlashArbitrage: INVALID_TOKEN");
        address v1Exchange = v1Factory.getExchange(token);
        require(v1Exchange != address(0), "ExampleFlashArbitrage: V1_EXCHANGE_NOT_EXIST");

        uint256 tokenBalanceV1 = IERC20(token).balanceOf(v1Exchange);
        uint256 ethBalanceV1 = v1Exchange.balance;
        require(tokenBalanceV1 > 0 && ethBalanceV1 > 0, "ExampleFlashArbitrage: V1_NO_LIQUIDITY");

        address v2Pair = pairFor(token, address(weth));
        require(v2Pair != address(0), "ExampleFlashArbitrage: V2_PAIR_NOT_EXIST");
        IUniswapV2Pair(v2Pair).sync();

        uint256 tokenBalanceV2;
        uint256 ethBalanceV2;
        bool isToken0Eth = (IUniswapV2Pair(v2Pair).token0() == address(weth));
        {
            (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(v2Pair).getReserves();
            (ethBalanceV2, tokenBalanceV2) = isToken0Eth ?
                (uint256(reserve0), uint256(reserve1)) :
                (uint256(reserve1), uint256(reserve0));
        }

        require(tokenBalanceV2 > 0 && ethBalanceV2 > 0, "ExampleFlashArbitrage: V2_NO_LIQUIDITY");

        // if the tokens to eth is less in v2 than v1, eth is cheaper in v2 in terms of token.
        // that means we should borrow eth from v2 and sell it on v1 for tokens.
        // otherwise we should borrow tokens from v2 and sell it on v1 for eth.
        // division by zero not possible
        bool borrowEth = tokenBalanceV2.mul(ethBalanceV1) / ethBalanceV2 < tokenBalanceV1;

        // the amount of eth we borrow should be the amount that moves the marginal price of the token in ETH to be
        // the same in both V1 and V2.
        if (borrowEth) {
            // (z1 + (b * 0.997)) / t1 = (z2 - (b * 0.997)) / t2 solve for b
            // where z1/t1 are eth/token reserves in v1, and z2/t2 are eth/token reserves in v2
            // try the above query in wolfram alpha
            uint borrowAmount = uint256(1000).mul(tokenBalanceV1.mul(ethBalanceV2).sub(tokenBalanceV2.mul(ethBalanceV1))) /
                uint256(997).mul(tokenBalanceV1.add(tokenBalanceV2));

            // this may happen if the profit exactly equals the swap fees
            require(borrowAmount > 0, 'ExampleFlashArbitrage: NO_PROFIT');

            bytes memory callback_data = abi.encode(
                isToken0Eth ? address(weth) : token,
                isToken0Eth ? token : address(weth),
                getAmountIn(borrowAmount, tokenBalanceV2, ethBalanceV2)
            );

            IUniswapV2Pair(v2Pair)
                .swap(isToken0Eth ? borrowAmount : 0, isToken0Eth ? 0 : borrowAmount, address(this), callback_data);

            // just forward the whole balance of the token we ended up with
            uint profit = IERC20(token).balanceOf(address(this));
            TransferHelper.safeTransfer(token, recipient, profit);
            emit Arbitrage(
                isToken0Eth ? address(weth) : token,
                isToken0Eth ? 0 : profit,
                isToken0Eth ? token : address(weth),
                isToken0Eth ? profit : 0
            );
        } else {
            // z1 / (t1 + b * 0.997) = z2 / (t2  - (b * 0.997)) solve for b
            uint borrowAmount = uint256(1000).mul(tokenBalanceV2.mul(ethBalanceV1).sub(tokenBalanceV1.mul(ethBalanceV2))) /
                uint256(997).mul(ethBalanceV1.add(ethBalanceV2));

            // this may happen if the profit exactly equals the swap fees
            require(borrowAmount > 0, 'ExampleFlashArbitrage: NO_PROFIT');

            bytes memory callback_data = abi.encode(
                isToken0Eth ? address(weth) : token,
                isToken0Eth ? token : address(weth),
                getAmountIn(borrowAmount, ethBalanceV2, tokenBalanceV2)
            );

            IUniswapV2Pair(v2Pair)
                .swap(isToken0Eth ? 0 : borrowAmount, isToken0Eth ? borrowAmount : 0, address(this), callback_data);

            uint profit = IERC20(address(weth)).balanceOf(address(this));
            // just forward the whole balance of ETH we ended up with
            TransferHelper.safeTransfer(address(weth), recipient, profit);
            emit Arbitrage(
                isToken0Eth ? address(weth) : token,
                isToken0Eth ? profit : 0,
                isToken0Eth ? token : address(weth),
                isToken0Eth ? 0 : profit
            );
        }
    }

    // arbitrage any two tokens. if token0 or token1 are WETH, falls back to arbitrageETH
    function arbitrage(address token0, address token1, address recipient) external {
        require(recipient != address(0), 'ExampleFlashArbitrage: INVALID_TO');

        if (token0 == address(weth)) {
            arbitrageETH(token1, recipient);
            return;
        } else if (token1 == address(weth)) {
            arbitrageETH(token0, recipient);
            return;
        }

        revert("TODO: 2 token arbitrage");
    }

    // this callback takes any amount received of token0 and token1 and exchanges the entire amount on uniswap v1 for
    // the other token.
    // it has special case handling for weth to wrap/unwrap the token when interacting with V1.
    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) override external {
        // this contract should initiate all flash swaps
        require(sender == address(this), "ExampleFlashArbitrage: FLASH_SWAP_FROM_OTHER");

        // only trades in a single direction
        require((amount0 > 0 && amount1 == 0) || (amount0 == 0 && amount1 > 0), "ExampleFlashArbitrage: CALLBACK_AMOUNT_XOR");

        // at this point we have received the loan to this contract and we must trade the full amount to
        // uniswap v1 and repay v2 the amount owed for the borrow
        (address token0, address token1, uint returnAmount) = abi.decode(data, (address, address, uint));

        // the token we receive from v2 vs. the token we send back to v2
        (address tokenReceived, uint amountReceived, address tokenReturn) = amount0 > 0 ?
            (token0, amount0, token1) :
            (token1, amount1, token0);

        // do the v1 swap
        if (tokenReceived == address(weth)) {
            pendingReceiveAddress = address(weth);
            weth.withdraw(amountReceived);
            delete pendingReceiveAddress;

            IUniswapV1Exchange returnExchange = IUniswapV1Exchange(v1Factory.getExchange(tokenReturn));
            returnExchange.ethToTokenSwapInput{value: amountReceived}(1, block.timestamp);
        } else if (tokenReturn == address(weth)) {
            IUniswapV1Exchange receivedExchange = IUniswapV1Exchange(v1Factory.getExchange(tokenReceived));
            TransferHelper.safeApprove(tokenReceived, address(receivedExchange), amountReceived);

            // prepare to get ETH from the v1 exchange
            pendingReceiveAddress = address(receivedExchange);
            uint ethReceived = receivedExchange.tokenToEthSwapInput(amountReceived, 1, block.timestamp);
            // refund most of the gas from the temporary set
            delete pendingReceiveAddress;

            weth.deposit{value: ethReceived}();
        } else {
            IUniswapV1Exchange receivedExchange = IUniswapV1Exchange(v1Factory.getExchange(tokenReceived));
            IUniswapV1Exchange returnExchange = IUniswapV1Exchange(v1Factory.getExchange(tokenReturn));

            // prepare to get ETH from the first exchange
            TransferHelper.safeApprove(tokenReceived, address(receivedExchange), amountReceived);
            pendingReceiveAddress = address(receivedExchange);
            uint ethReceived = receivedExchange.tokenToEthSwapInput(amountReceived, 1, block.timestamp);
            // refund most of the gas from the temporary set
            delete pendingReceiveAddress;

            returnExchange.ethToTokenSwapInput{value: ethReceived}(1, block.timestamp);
        }

        // now pay back v2 what is owed
        TransferHelper.safeTransfer(tokenReturn, msg.sender, returnAmount);
    }
}
