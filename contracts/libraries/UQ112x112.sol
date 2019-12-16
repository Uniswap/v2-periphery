pragma solidity 0.5.14;

library UQ112x112 {
    uint224 constant Q112 = 2**112;

    // safely multiply a UQ112.112 by a uint and return the result as a uint
    function qmul(uint224 x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = uint256(x) * y) / y == x, "qmul-overflow");
    }

    // decode a UQ112.112 fixed point number as a uint112 s.t. `y := y_encoded / 2**112`
    function decode(uint y) internal pure returns (uint z) {
        z = y / Q112;
    }
}
