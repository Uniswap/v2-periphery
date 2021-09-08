pragma solidity =0.6.6;

import '@delioswap/lib/contracts/libraries/TransferHelper.sol';

import './interfaces/IDelioswapMigrator.sol';
import './interfaces/V1/IDelioswapV1Factory.sol';
import './interfaces/V1/IDelioswapV1Exchange.sol';
import './interfaces/IDelioswapRouter01.sol';
import './interfaces/IERC20.sol';

contract DelioswapMigrator is IDelioswapMigrator {
    IDelioswapV1Factory immutable factoryV1;
    IDelioswapRouter01 immutable router;

    constructor(address _factoryV1, address _router) public {
        factoryV1 = IDelioswapV1Factory(_factoryV1);
        router = IDelioswapRouter01(_router);
    }

    // needs to accept ETH from any v1 exchange and the router. ideally this could be enforced, as in the router,
    // but it's not possible because it requires a call to the v1 factory, which takes too much gas
    receive() external payable {}

    function migrate(address token, uint amountTokenMin, uint amountETHMin, address to, uint deadline)
        external
        override
    {
        IDelioswapV1Exchange exchangeV1 = IDelioswapV1Exchange(factoryV1.getExchange(token));
        uint liquidityV1 = exchangeV1.balanceOf(msg.sender);
        require(exchangeV1.transferFrom(msg.sender, address(this), liquidityV1), 'TRANSFER_FROM_FAILED');
        (uint amountETHV1, uint amountTokenV1) = exchangeV1.removeLiquidity(liquidityV1, 1, 1, uint(-1));
        TransferHelper.safeApprove(token, address(router), amountTokenV1);
        (uint amountTokenV2, uint amountETHV2,) = router.addLiquidityETH{value: amountETHV1}(
            token,
            amountTokenV1,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );
        if (amountTokenV1 > amountTokenV2) {
            TransferHelper.safeApprove(token, address(router), 0); // be a good blockchain citizen, reset allowance to 0
            TransferHelper.safeTransfer(token, msg.sender, amountTokenV1 - amountTokenV2);
        } else if (amountETHV1 > amountETHV2) {
            // addLiquidityETH guarantees that all of amountETHV1 or amountTokenV1 will be used, hence this else is safe
            TransferHelper.safeTransferETH(msg.sender, amountETHV1 - amountETHV2);
        }
    }
}
