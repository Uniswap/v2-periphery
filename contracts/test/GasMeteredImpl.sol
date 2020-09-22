pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import '../GasMetered.sol';
import '../libraries/SafeMath.sol';
import '../TestTarget.sol';

contract GasMeteredImpl is GasMetered, TestTarget {
    uint256 public immutable reserveInput;
    uint256 public immutable reserveOutput;

    constructor(uint256 _reserveInput, uint256 _reserveOutput) public {
        reserveInput = _reserveInput;
        reserveOutput = _reserveOutput;
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public override pure returns (uint256) {
        return amountIn.mul(reserveIn) / reserveOut;
    }

    function getEthExchangeRate(address) internal override returns (uint256, uint256) {
        return (reserveInput, reserveOutput);
    }
}
