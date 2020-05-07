pragma solidity >=0.6.2;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';
import '@uniswap/lib/contracts/libraries/Babylonian.sol';

import '../interfaces/V1/IUniswapV1Factory.sol';
import '../interfaces/V1/IUniswapV1Exchange.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IWETH.sol';
import '../libraries/SafeMath.sol';
import '../libraries/UniswapV2Library.sol';
import '../interfaces/IWETH.sol';

// uses flash swaps in UniswapV2 to arbitrage against UniswapV1 with zero price risk
// i.e. any caller can provide a token pair and the liquidity in UniswapV2 will be used to move the marginal price in V1
// to be the same as the marginal price in V2, and forward any resulting profits
// all the caller pays for is gas. gas and gas prices are not considered in the arbitrage profitability.
contract ExampleFlashArbitrage is IUniswapV2Callee {
    using SafeMath for uint;

    IUniswapV1Factory public immutable v1Factory;
    IUniswapV2Factory public immutable v2Factory;
    IWETH public immutable weth;

    // this is temporarily set during the callback so we can prevent ETH from accidentally being sent to this contract
    address private pendingReceiveAddress;

    constructor(IUniswapV1Factory v1Factory_, IUniswapV2Factory v2Factory_, IWETH weth_) public {
        v1Factory = v1Factory_;
        v2Factory = v2Factory_;
        weth = weth_;
    }

    // receives ETH from V1 exchanges. must first be prepared to receive via pendingReceiveAddress.
    receive() external payable {
        require(msg.sender == pendingReceiveAddress, "FlashArbitrage: RECEIVE_NOT_PENDING");
    }

    // this is necessary to avoid multiplication overflow.
    uint private constant PROFIT_DERIVATIVE_DOWNSCALING_BITS_STEP = 8;

    // compute whether profit increases if we withdraw more from v2 to sell on v1
    // used in order to do a binary search and find the maximally profitable withdraw amount
    function profitDerivativePositive(uint x0, uint y0, uint x1, uint y1, uint withdrawX1) pure public returns (bool) {
        uint leftTop = x1.mul(y1); // 224 bits
        uint leftBottom = x1.sub(withdrawX1).mul(x1.sub(withdrawX1)); // 224 bits

        uint rightTop = x0.mul(y0).mul(994009); // assumed not to exceed 224 bits
        // probably < 256 bits
        uint rightBottom = withdrawX1.mul(997).add(x0.mul(1000)).mul(withdrawX1.mul(997).add(x0.mul(1000)));

        // while left and right variables are both greater than max, scale them down
        while (leftTop > uint128(-1) || rightTop > uint128(-1)) {
            leftTop >>= PROFIT_DERIVATIVE_DOWNSCALING_BITS_STEP;
            rightTop >>= PROFIT_DERIVATIVE_DOWNSCALING_BITS_STEP;
        }
        while (rightBottom > uint128(-1) || leftBottom > uint128(-1)) {
            rightBottom >>= PROFIT_DERIVATIVE_DOWNSCALING_BITS_STEP;
            leftBottom >>= PROFIT_DERIVATIVE_DOWNSCALING_BITS_STEP;
        }

        return leftTop.mul(rightBottom) < rightTop.mul(leftBottom);
    }

    uint private constant NUM_ITERATIONS_BINARY_SEARCH = 12;

    // computes the withdraw amount to arbitrage between v1 and v2 eth/token pairs
    // cannot be used for token/token pairs because token/token pairs must make multiple hops in v1
    function computeWithdrawAmountETH(uint v1Eth, uint v1Token, uint v2Eth, uint v2Token) private pure returns (uint withdrawAmount, bool withdrawETH) {
        require(v1Eth > 0 && v1Eth > 0 && v2Eth > 0 && v2Token > 0, 'FlashArbitrage: ALL_INPUTS_NONZERO');

        {
            uint left = v2Token.mul(v1Eth) / v2Eth;
            uint right = v1Token;
            require(left != right, 'FlashArbitrage: EQUIVALENT_PRICE');
            // if the tokens to eth is less in v2 than v1, eth is cheaper in v2 in terms of token.
            // that means we should withdraw eth from v2 and sell it on v1 for tokens.
            // otherwise we should withdraw tokens from v2 and sell it on v1 for eth.
            // division by zero not possible
            withdrawETH = left < right;
        }

        if (withdrawETH) {
            uint lo = 0;
            uint hi = v2Eth - 1;
            for (uint i = 0; i < NUM_ITERATIONS_BINARY_SEARCH; i++) {
                withdrawAmount = (lo + hi) >> 1;
                if (profitDerivativePositive(v1Eth, v1Token, v2Eth, v2Token, withdrawAmount)) {
                    lo = withdrawAmount + 1;
                } else {
                    hi = withdrawAmount;
                }
            }
        } else {
            uint lo = 0;
            uint hi = v2Token - 1;
            for (uint i = 0; i < NUM_ITERATIONS_BINARY_SEARCH; i++) {
                withdrawAmount = (lo + hi) >> 1;
                if (profitDerivativePositive(v1Token, v1Eth, v2Token, v2Eth, withdrawAmount)) {
                    lo = withdrawAmount + 1;
                } else {
                    hi = withdrawAmount;
                }
            }
        }
    }

    // emitted when a successful arbitrage occurs
    event Arbitrage(address token0, uint profit0, address token1, uint profit1);

    // arbitrages the token/ETH pair between Uniswap V1 and V2
    // this function deliberately excludes the possibility that you want to arbitrage weth against eth.
    // to do that you should use the WETH contract
    // the computation for optimal token/ETH pairs arbitrage amounts is simpler because it only requires one v1 swap
    function arbitrageETH(address token, address recipient) private {
        require(token != address(weth), 'FlashArbitrage: INVALID_TOKEN');
        address v1Exchange = v1Factory.getExchange(token);
        require(v1Exchange != address(0), 'FlashArbitrage: V1_EXCHANGE_NOT_EXIST');

        uint256 tokenBalanceV1 = IERC20(token).balanceOf(v1Exchange);
        uint256 ethBalanceV1 = v1Exchange.balance;
        require(tokenBalanceV1 > 0 && ethBalanceV1 > 0, 'FlashArbitrage: V1_NO_LIQUIDITY');

        address v2Pair = UniswapV2Library.pairFor(address(v2Factory), token, address(weth));
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

        require(tokenBalanceV2 > 0 && ethBalanceV2 > 0, 'FlashArbitrage: V2_NO_LIQUIDITY');

        (uint withdrawAmount, bool withdrawETH) =
        computeWithdrawAmountETH(ethBalanceV1, tokenBalanceV1, ethBalanceV2, tokenBalanceV2);

        // the amount of eth we withdraw should be the amount that moves the marginal price of the token in ETH to be
        // the same in both V1 and V2.
        if (withdrawETH) {
            bytes memory callback_data = abi.encode(
                isToken0Eth ? address(weth) : token,
                isToken0Eth ? token : address(weth),
                UniswapV2Library.getAmountIn(withdrawAmount, tokenBalanceV2, ethBalanceV2)
            );

            IUniswapV2Pair(v2Pair)
            .swap(isToken0Eth ? withdrawAmount : 0, isToken0Eth ? 0 : withdrawAmount, address(this), callback_data);

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
            bytes memory callback_data = abi.encode(
                isToken0Eth ? address(weth) : token,
                isToken0Eth ? token : address(weth),
                UniswapV2Library.getAmountIn(withdrawAmount, ethBalanceV2, tokenBalanceV2)
            );

            IUniswapV2Pair(v2Pair)
            .swap(isToken0Eth ? 0 : withdrawAmount, isToken0Eth ? withdrawAmount : 0, address(this), callback_data);

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
        require(recipient != address(0), 'FlashArbitrage: INVALID_TO');

        if (token0 == address(weth)) {
            arbitrageETH(token1, recipient);
            return;
        } else if (token1 == address(weth)) {
            arbitrageETH(token0, recipient);
            return;
        }

        revert('FlashArbitrage: TODO_MULTIHOP_ARBITRAGE');
    }

    // this callback takes any amount received of token0 and token1 and exchanges the entire amount on uniswap v1 for
    // the other token.
    // it has special case handling for weth to wrap/unwrap the token when interacting with V1.
    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) override external {
        // this contract should initiate all flash swaps
        require(sender == address(this), 'FlashArbitrage: FLASH_SWAP_FROM_OTHER');

        // only trades in a single direction
        require((amount0 > 0 && amount1 == 0) || (amount0 == 0 && amount1 > 0), 'FlashArbitrage: CALLBACK_AMOUNT_XOR');

        // at this point we have received the loan to this contract and we must trade the full amount to
        // uniswap v1 and complete the swap
        (address token0, address token1, uint returnAmount) = abi.decode(data, (address, address, uint));

        // the token we receive from v2 vs. the token we send back to v2
        (address tokenReceived, uint amountReceived, address tokenReturn) = amount0 > 0 ?
            (token0, amount0, token1) :
            (token1, amount1, token0);

        // do the v1 swap
        if (tokenReceived == address(weth)) {
            pendingReceiveAddress = address(weth);
            weth.withdraw(amountReceived);
            // refund most of the gas from the temporary set
            delete pendingReceiveAddress;

            IUniswapV1Exchange returnExchange = IUniswapV1Exchange(v1Factory.getExchange(tokenReturn));
            returnExchange.ethToTokenSwapInput{value : amountReceived}(1, block.timestamp);
        } else if (tokenReturn == address(weth)) {
            IUniswapV1Exchange receivedExchange = IUniswapV1Exchange(v1Factory.getExchange(tokenReceived));
            TransferHelper.safeApprove(tokenReceived, address(receivedExchange), amountReceived);

            // prepare to get ETH from the v1 exchange
            pendingReceiveAddress = address(receivedExchange);
            uint ethReceived = receivedExchange.tokenToEthSwapInput(amountReceived, 1, block.timestamp);
            // refund most of the gas from the temporary set
            delete pendingReceiveAddress;

            weth.deposit{value : ethReceived}();
        } else {
            IUniswapV1Exchange receivedExchange = IUniswapV1Exchange(v1Factory.getExchange(tokenReceived));
            IUniswapV1Exchange returnExchange = IUniswapV1Exchange(v1Factory.getExchange(tokenReturn));

            // prepare to get ETH from the first exchange
            TransferHelper.safeApprove(tokenReceived, address(receivedExchange), amountReceived);
            pendingReceiveAddress = address(receivedExchange);
            uint ethReceived = receivedExchange.tokenToEthSwapInput(amountReceived, 1, block.timestamp);
            // refund most of the gas from the temporary set
            delete pendingReceiveAddress;

            returnExchange.ethToTokenSwapInput{value : ethReceived}(1, block.timestamp);
        }

        // now pay back v2 what is owed
        TransferHelper.safeTransfer(tokenReturn, msg.sender, returnAmount);
    }
}
