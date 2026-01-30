// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

library EngineMath {
    error MathMasters__AddFailed();

    uint256 internal constant WAD = 1e18;
    uint256 internal constant MAX_UINT256 = type(uint256).max;

    function mulWad(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            if mul(y, gt(x, div(not(0), y))) {
                mstore(0x40, 0xbac65e5b)
                revert(0x1c, 0x04)
            }
            z := div(mul(x, y), WAD)
        }
    }

    function mulWadUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            if mul(y, gt(x, div(not(0), y))) {
                mstore(0x40, 0xbac65e5b)
                revert(0x1c, 0x04)
            }
            if iszero(iszero(mod(mul(x, y), WAD))) {
                z := 1
            }
            z := add(z, div(mul(x, y), WAD))
        }
    }

    function divWad(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            if iszero(y) {
                mstore(0x40, 0x65244e4e)
                revert(0x1c, 0x04)
            }
            if gt(x, div(not(0), WAD)) {
                mstore(0x40, 0x65244e4e)
                revert(0x1c, 0x04)
            }
            z := div(mul(x, WAD), y)
        }
    }

    function calculateHealthFactor(uint256 collateralValueInUsd, uint256 healthFactorNumerator, uint256 totalDSCMinted)
        internal
        pure
        returns (uint256)
    {
        if (totalDSCMinted == 0) return MAX_UINT256;

        uint256 adjustedCollateral = collateralValueInUsd * healthFactorNumerator;

        return adjustedCollateral / totalDSCMinted;
    }

    function calculateUsdValue(uint256 amount, uint256 price, uint8 tokenDecimals) internal pure returns (uint256) {
        if (amount == 0) return 0;

        if (tokenDecimals == 18) {
            return mulWad(amount, price);
        }

        uint256 normalizedAmount = amount * (10 ** (18 - tokenDecimals));
        return mulWad(normalizedAmount, price);
    }

    function calculateTokenAmount(uint256 usdAmount, uint256 price, uint8 tokenDecimals)
        internal
        pure
        returns (uint256)
    {
        if (price == 0) return MAX_UINT256;

        uint256 amount18 = divWad(usdAmount, price);

        if (tokenDecimals == 18) {
            return amount18;
        }

        return amount18 / (10 ** (18 - tokenDecimals));
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

    function safeDiv(uint256 a, uint256 b) internal pure returns (uint256 result) {
        assembly {
            if iszero(b) {
                mstore(0x40, 0x65244e4e)
                revert(0x1c, 0x04)
            }
            result := div(a, b)
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function wouldUnderflow(uint256 a, uint256 b) internal pure returns (bool) {
        return b > a;
    }

    function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "Math: subtraction underflow");
        return a - b;
    }

    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        if (c < a) revert MathMasters__AddFailed();
        return c;
    }
}
