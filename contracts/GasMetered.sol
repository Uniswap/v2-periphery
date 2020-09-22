pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import '@uniswap/lib/contracts/libraries/TransferHelper.sol';
import '@openzeppelin/contracts/cryptography/ECDSA.sol';
import './libraries/SafeMath.sol';

abstract contract GasMetered {
    using SafeMath for uint256;
    mapping(bytes32 => bool) public signedHashes;

    struct GasPayerRefund {
        address payable gasPayer;
        uint256 gasOverhead;
        address token;
    }
    struct ReplayProtection {
        address signer;
        uint256 nonce;
        bytes signature;
    }

    function getEthExchangeRate(address token) internal virtual returns (uint256 reserveInput, uint256 reserveOutput);

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public virtual pure returns (uint256 amountOut);

    function _checkSignatureAndUpdateReplay(
        bytes memory data,
        GasPayerRefund memory gasRefund,
        ReplayProtection memory replayProtection
    ) internal {
        // We sign:
        // * the call data
        // * the signer's address to guarantee only they can store this hash,
        // * the chainID to make sure it is for this fork of the blockchain,
        // * the target contract (this) to make sure it is only used here.
        bytes32 h = keccak256(
            abi.encodePacked(
                data,
                gasRefund.gasPayer,
                gasRefund.gasOverhead,
                gasRefund.token,
                replayProtection.signer,
                replayProtection.nonce,
                getChainID(),
                address(this)
            )
        );
        require(signedHashes[h] == false, 'GasMetered: REPLAY_USED');
        address signer = ECDSA.recover(ECDSA.toEthSignedMessageHash(h), replayProtection.signature); // about 3k

        require(signer == replayProtection.signer, 'GasMetered: INVALID_SIGNER');
        signedHashes[h] = true;
    }

    function getChainID() public pure returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    // **** GAS METERING (allow relays to submit transactions on behalf of users) ****
    function gasMetered(
        bytes memory data,
        GasPayerRefund memory gasRefund,
        ReplayProtection memory replayProtection
    ) public returns (bool success, bytes memory returnData) {
        uint256 gasUsedTracker = gasleft() + gasRefund.gasOverhead;
        _checkSignatureAndUpdateReplay(data, gasRefund, replayProtection);

        // append the signer to the call data so that
        // we can access it in the target function
        (success, returnData) = address(this).call(abi.encodePacked(data, replayProtection.signer));

        (uint256 reserveInput, uint256 reserveOutput) = getEthExchangeRate(gasRefund.token);
        gasUsedTracker = gasUsedTracker.sub(gasleft());
        uint256 ethUsed = tx.gasprice.mul(gasUsedTracker);

        uint256 amountOutput = getAmountOut(ethUsed, reserveInput, reserveOutput);
        TransferHelper.safeTransferFrom(gasRefund.token, replayProtection.signer, gasRefund.gasPayer, amountOutput);
    }
}
