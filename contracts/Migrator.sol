pragma solidity =0.5.16;

import './interfaces/IMigrator.sol';
import './interfaces/V1/IUniswapV1Factory.sol';
import './interfaces/V1/IUniswapV1Exchange.sol';
import './interfaces/IUniswapV2Router.sol';

contract Migrator is IMigrator {
    bytes4 public constant approveSelector = bytes4(keccak256(bytes('approve(address,uint256)')));
    bytes4 public constant transferSelector = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factoryV1;
    address public router;

    function _safeApprove(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(approveSelector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'APPROVE_FAILED');
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(transferSelector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }

    function _safeTransferETH(address to, uint value) private {
        (bool success,) = to.call.value(value)('');
        require(success, 'ETH_TRANSFER_FAILED');
    }

    constructor(address _factoryV1, address _router) public {
        factoryV1 = _factoryV1;
        router = _router;
    }

    function() external payable {}

    function migrate(address token, uint amountTokenMin, uint amountETHMin, address to, uint deadline)
        external
    {
        IUniswapV1Exchange exchangeV1 = IUniswapV1Exchange(IUniswapV1Factory(factoryV1).getExchange(token));
        require(address(exchangeV1) != address(0), 'INVALID_TOKEN');
        uint liquidityV1 = exchangeV1.balanceOf(msg.sender);
        require(liquidityV1 > 0, 'INSUFFICIENT_LIQUIDITY');
        require(exchangeV1.transferFrom(msg.sender, address(this), liquidityV1), 'TRANSFER_FROM_FAILED');
        (uint amountETHV1, uint amountTokenV1) = exchangeV1.removeLiquidity(liquidityV1, 1, 1, uint(-1));
        _safeApprove(token, router, uint(-1));
        (uint amountTokenV2, uint amountETHV2,) = IUniswapV2Router(router).addLiquidityETH.value(amountETHV1)(
            token,
            amountTokenV1,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );
        if (amountTokenV1 > amountTokenV2) _safeTransfer(token, msg.sender, amountTokenV1 - amountTokenV2);
        if (amountETHV1 > amountETHV2) _safeTransferETH(msg.sender, amountETHV1 - amountETHV2);
    }
}
