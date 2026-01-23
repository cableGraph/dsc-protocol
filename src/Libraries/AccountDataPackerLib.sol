// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

library AccountDataPacker {
    uint256 private constant LAST_ACTIVITY_SHIFT = 192;
    uint256 private constant DEPOSIT_COUNT_SHIFT = 160;

    function pack(
        uint64 lastActivity,
        uint32 depositCount,
        uint160 flags
    ) internal pure returns (uint256) {
        assembly {
            // Pack: lastActivity << 192 | depositCount << 160 | flags
            let packed := flags
            packed := or(packed, shl(DEPOSIT_COUNT_SHIFT, depositCount))
            packed := or(packed, shl(LAST_ACTIVITY_SHIFT, lastActivity))
            mstore(0x00, packed)
            return(0x00, 0x20)
        }
    }

    function unpack(
        uint256 data
    ) internal pure returns (uint64, uint32, uint160) {
        assembly {
            let lastActivity := shr(LAST_ACTIVITY_SHIFT, data)
            let depositCount := shr(DEPOSIT_COUNT_SHIFT, data)
            depositCount := and(depositCount, 0xFFFFFFFF)

            let flagsMask := sub(shl(160, 1), 1)
            let flags := and(data, flagsMask)

            mstore(0x00, lastActivity)
            mstore(0x20, depositCount)
            mstore(0x40, flags)
            return(0x00, 0x60)
        }
    }

    /**
     * @dev Update only the lastActivity timestamp
     */
    function updateLastActivity(
        uint256 currentData,
        uint64 newTimestamp
    ) internal pure returns (uint256) {
        (, uint32 depositCount, uint160 flags) = unpack(currentData);
        return pack(newTimestamp, depositCount, flags);
    }

    /**
     * @dev Increment the deposit count
     */
    function incrementDepositCount(
        uint256 currentData
    ) internal pure returns (uint256) {
        (uint64 lastActivity, uint32 depositCount, uint160 flags) = unpack(
            currentData
        );
        // Prevent overflow (max 4.29B deposits per account)
        if (depositCount == type(uint32).max) {
            revert("Deposit count overflow");
        }
        return pack(lastActivity, depositCount + 1, flags);
    }

    /**
     * @dev Get only the lastActivity from packed data
     */
    function getLastActivity(uint256 data) internal pure returns (uint64) {
        assembly {
            let lastActivity := shr(LAST_ACTIVITY_SHIFT, data)
            mstore(0x00, lastActivity)
            return(0x00, 0x20)
        }
    }

    /**
     * @dev Get only the depositCount from packed data
     */
    function getDepositCount(uint256 data) internal pure returns (uint32) {
        assembly {
            let depositCount := shr(DEPOSIT_COUNT_SHIFT, data)
            depositCount := and(depositCount, 0xFFFFFFFF)
            mstore(0x00, depositCount)
            return(0x00, 0x20)
        }
    }

    /**
     * @dev Get only the flags from packed data
     */
    function getFlags(uint256 data) internal pure returns (uint160) {
        assembly {
            // Calculate mask: (1 << 160) - 1
            let flagsMask := sub(shl(160, 1), 1)
            let flags := and(data, flagsMask)
            mstore(0x00, flags)
            return(0x00, 0x20)
        }
    }

    /**
     * @dev Gas-optimized: Update both lastActivity and increment depositCount in one operation
     */
    function updateActivityAndIncrementDeposit(
        uint256 currentData
    ) internal view returns (uint256) {
        (uint64 lastActivity, uint32 depositCount, uint160 flags) = unpack(
            currentData
        );
        // Prevent overflow
        if (depositCount == type(uint32).max) {
            revert("Deposit count overflow");
        }
        return pack(uint64(block.timestamp), depositCount + 1, flags);
    }

    /**
     * @dev Gas-optimized: Update only lastActivity (for non-deposit operations)
     */
    function updateActivity(
        uint256 currentData
    ) internal view returns (uint256) {
        (, uint32 depositCount, uint160 flags) = unpack(currentData);
        return pack(uint64(block.timestamp), depositCount, flags);
    }
}
