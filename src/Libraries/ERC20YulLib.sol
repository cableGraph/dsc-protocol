// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

library ERC20YulLib {
    error ERC20_CALL_FAILED();

    function safeTransfer(address token, address to, uint256 amount) internal {
        assembly {
            let ptr := mload(0x40)

            // transfer(address,uint256)
            mstore(
                ptr,
                0xa9059cbb00000000000000000000000000000000000000000000000000000000
            )
            mstore(add(ptr, 0x04), to)
            mstore(add(ptr, 0x24), amount)

            let success := call(gas(), token, 0, ptr, 0x44, 0, 0x20)

            if iszero(success) {
                revert(0, 0)
            }

            switch returndatasize()
            case 0 {}
            case 0x20 {
                returndatacopy(ptr, 0, 0x20)
                if iszero(mload(ptr)) {
                    revert(0, 0)
                }
            }
            default {
                revert(0, 0)
            }
        }
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        assembly {
            let ptr := mload(0x40)

            // transferFrom(address,address,uint256)
            mstore(
                ptr,
                0x23b872dd00000000000000000000000000000000000000000000000000000000
            )
            mstore(add(ptr, 0x04), from)
            mstore(add(ptr, 0x24), to)
            mstore(add(ptr, 0x44), amount)

            let success := call(gas(), token, 0, ptr, 0x64, 0, 0x20)

            if iszero(success) {
                revert(0, 0)
            }

            switch returndatasize()
            case 0 {}
            case 0x20 {
                returndatacopy(ptr, 0, 0x20)
                if iszero(mload(ptr)) {
                    revert(0, 0)
                }
            }
            default {
                revert(0, 0)
            }
        }
    }
    function balanceOf(
        address token,
        address account
    ) internal view returns (uint256) {
        // Yul implementation similar to transfer/transferFrom
    }
}
