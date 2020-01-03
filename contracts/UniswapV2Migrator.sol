pragma solidity 0.5.15;

import "./interfaces/IUniswapV2Migrator.sol";
import "./interfaces/IUniswapV1Factory.sol";
import "./interfaces/IUniswapV1.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IERC20.sol";

contract UniswapV2Migrator is IUniswapV2Migrator {
    address public factoryV1;
    address public factoryV2;
    address public router;

    function _safeTransfer(address token, address to, uint value) private {
        // solium-disable-next-line security/no-low-level-calls
        (bool success, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "UniswapV2Migrator: TRANSFER_FAILED");
    }
    function _sendETH(address to, uint value) private {
        (bool success,) = to.call.value(value)(""); // solium-disable-line security/no-call-value
        require(success, "UniswapV2Migrator: CALL_FAILED");
    }

    constructor(address _factoryV1, address _factoryV2, address _router) public {
        factoryV1 = _factoryV1;
        factoryV2 = _factoryV2;
        router = _router;
    }

    function migrate(address token, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external {
        address exchangeV1 = IUniswapV1Factory(factoryV1).getExchange(token);
        uint liquidityV1 = IERC20(exchangeV1).balanceOf(msg.sender);
        IERC20(exchangeV1).transferFrom(msg.sender, address(this), liquidityV1);
        (uint amountETHV1, uint amountTokenV1) = IUniswapV1(exchangeV1).removeLiquidity(liquidityV1, 1, 1, uint(-1));
        (uint amountETHV2, uint amountTokenV2,) = IUniswapV2Router(router).addLiquidityETH.value(amountETHV1)(
            token, amountTokenV1, amountTokenMin, amountETHMin, to, deadline
        );
        if (amountETHV1 > amountETHV2) _sendETH(msg.sender, amountETHV1 - amountETHV2);
        if (amountTokenV1 > amountTokenV2) _safeTransfer(token, msg.sender, amountTokenV1 - amountTokenV2);
    }
}
