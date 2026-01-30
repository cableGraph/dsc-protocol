// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

library ERC20YulLib {
    function safeTransfer(address token, address to, uint256 amount) internal {
        assembly {
            let ptr := mload(0x40)

            mstore(ptr, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
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

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        bool success;
        assembly {
            let ptr := mload(0x40)

            mstore(ptr, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), from)
            mstore(add(ptr, 0x24), to)
            mstore(add(ptr, 0x44), amount)

            success := call(gas(), token, 0, ptr, 0x64, 0, 0)

            if gt(returndatasize(), 0) {
                returndatacopy(ptr, 0, returndatasize())
                success := and(success, mload(ptr))
            }

            mstore(0x40, add(ptr, 0x80))
        }

        require(success, "ERC20YulLib: transfer failed");
    }

    function balanceOf(address token, address account) internal view returns (uint256 tokenBalance) {
        assembly {
            let ptr := mload(0x40)

            mstore(ptr, 0x70a0823100000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), account)

            let success := staticcall(gas(), token, ptr, 0x24, 0, 0x20)

            if iszero(success) {
                revert(0, 0)
            }

            returndatacopy(ptr, 0, 0x20)
            tokenBalance := mload(ptr)

            mstore(0x40, add(ptr, 0x40))
        }
    }
}
