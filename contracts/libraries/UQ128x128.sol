pragma solidity 0.5.13;

library UQ128x128 {
    uint constant Q128 = 2**128;

    function qmul(uint x, uint128 y) internal pure returns (uint z) {
        z = x * y;
    }

    function decode(uint y) internal pure returns (uint128 z) {
        return uint128(y / Q128);
    }
}
