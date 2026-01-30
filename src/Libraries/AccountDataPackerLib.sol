// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

library AccountDataPacker {
    uint256 private constant LAST_ACTIVITY_SHIFT = 192;
    uint256 private constant DEPOSIT_COUNT_SHIFT = 160;

    function pack(uint64 lastActivity, uint32 depositCount, uint160 flags) internal pure returns (uint256 packed) {
        assembly {
            packed := flags
            packed := or(packed, shl(DEPOSIT_COUNT_SHIFT, depositCount))
            packed := or(packed, shl(LAST_ACTIVITY_SHIFT, lastActivity))
        }
    }

    function safeMul(uint256 a, uint256 b) internal pure returns (uint256 result) {
        assembly {
            if gt(a, div(not(0), b)) {
                mstore(0x40, 0xbac65e5b)
                revert(0x1c, 0x04)
            }
            result := mul(a, b)
        }
    }

    function unpack(uint256 data) internal pure returns (uint64 lastActivity, uint32 depositCount, uint160 flags) {
        assembly {
            lastActivity := shr(LAST_ACTIVITY_SHIFT, data)

            depositCount := shr(DEPOSIT_COUNT_SHIFT, data)
            depositCount := and(depositCount, 0xFFFFFFFF)

            let flagsMask := sub(shl(160, 1), 1)
            flags := and(data, flagsMask)
        }
    }

    function updateLastActivity(uint256 currentData, uint64 newTimestamp) internal pure returns (uint256) {
        (, uint32 depositCount, uint160 flags) = unpack(currentData);
        return pack(newTimestamp, depositCount, flags);
    }

    function incrementDepositCount(uint256 currentData) internal pure returns (uint256) {
        (uint64 lastActivity, uint32 depositCount, uint160 flags) = unpack(currentData);
        if (depositCount == type(uint32).max) {
            revert("Deposit count overflow");
        }
        return pack(lastActivity, depositCount + 1, flags);
    }

    function getLastActivity(uint256 data) internal pure returns (uint64 lastActivity) {
        assembly {
            lastActivity := shr(LAST_ACTIVITY_SHIFT, data)
        }
    }

    function getDepositCount(uint256 data) internal pure returns (uint32 depositCount) {
        assembly {
            depositCount := shr(DEPOSIT_COUNT_SHIFT, data)
            depositCount := and(depositCount, 0xFFFFFFFF)
        }
    }

    function getFlags(uint256 data) internal pure returns (uint160 flags) {
        assembly {
            let flagsMask := sub(shl(160, 1), 1)
            flags := and(data, flagsMask)
        }
    }

    function updateActivityAndIncrementDeposit(uint256 currentData) internal view returns (uint256) {
        (uint64 lastActivity, uint32 depositCount, uint160 flags) = unpack(currentData);
        if (depositCount == type(uint32).max) {
            revert("Deposit count overflow");
        }
        return pack(uint64(block.timestamp), depositCount + 1, flags);
    }

    function updateActivity(uint256 currentData) internal view returns (uint256) {
        (, uint32 depositCount, uint160 flags) = unpack(currentData);
        return pack(uint64(block.timestamp), depositCount, flags);
    }
}
