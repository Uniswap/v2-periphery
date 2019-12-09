pragma solidity 0.5.13;

library Math {
    function sub512(uint x0, uint x1, uint y0, uint y1) internal pure returns (uint z0, uint z1) {
        assembly { // solium-disable-line security/no-inline-assembly
            z0 := sub(x0, y0)
            z1 := sub(sub(x1, y1), lt(x0, y0))
        }
    }
}
