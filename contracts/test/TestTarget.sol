pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

contract TestTarget {
    uint256 public val;

    function increment() public {
        val = val + 1;
    }
}
