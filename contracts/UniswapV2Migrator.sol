pragma solidity =0.5.16;

import './interfaces/IUniswapV2Migrator.sol';
import './interfaces/V1/IUniswapV1Factory.sol';
import './interfaces/V1/IUniswapV1Exchange.sol';
import './interfaces/IUniswapV2Router01.sol';

contract UniswapV2Migrator is IUniswapV2Migrator {
    bytes4 private constant SELECTOR_APPROVE = bytes4(keccak256(bytes('approve(address,uint256)')));
    bytes4 private constant SELECTOR_TRANSFER = bytes4(keccak256(bytes('transfer(address,uint256)')));

    IUniswapV1Factory public factoryV1;
    // router address is identical across mainnet and testnets but differs between testing and deployed environments
    IUniswapV2Router01 public constant router = IUniswapV2Router01(0x84e924C5E04438D2c1Df1A981f7E7104952e6de1);

    function _safeApprove(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR_APPROVE, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'APPROVE_FAILED');
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR_TRANSFER, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }

    function _safeTransferETH(address to, uint value) private {
        (bool success,) = to.call.value(value)(new bytes(0));
        require(success, 'ETH_TRANSFER_FAILED');
    }

    constructor(address _factoryV1) public {
        factoryV1 = IUniswapV1Factory(_factoryV1);
    }

    // needs to accept ETH from any v1 exchange and the router. ideally this could be enforced, as in the router,
    // but it's not possible because it requires a call to the v1 factory, which takes too much gas
    function() external payable {}

    function migrate(address token, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external {
        IUniswapV1Exchange exchangeV1 = IUniswapV1Exchange(factoryV1.getExchange(token));
        uint liquidityV1 = exchangeV1.balanceOf(msg.sender);
        require(exchangeV1.transferFrom(msg.sender, address(this), liquidityV1), 'TRANSFER_FROM_FAILED');
        (uint amountETHV1, uint amountTokenV1) = exchangeV1.removeLiquidity(liquidityV1, 1, 1, uint(-1));
        _safeApprove(token, address(router), amountTokenV1);
        (uint amountTokenV2, uint amountETHV2,) = router.addLiquidityETH.value(amountETHV1)(
            token,
            amountTokenV1,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );
        if (amountTokenV1 > amountTokenV2) {
            _safeApprove(token, address(router), 0); // be a good blockchain citizen, reset allowance to 0
            _safeTransfer(token, msg.sender, amountTokenV1 - amountTokenV2);
        } else if (amountETHV1 > amountETHV2) {
            // addLiquidityETH guarantees that all of amountETHV1 or amountTokenV1 will be used, hence this else is safe
            _safeTransferETH(msg.sender, amountETHV1 - amountETHV2);
        }
    }
}
