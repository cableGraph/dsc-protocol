// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author TrustAutomated
 * @notice This library provides utility functions for interacting with price oracles.
 * It checks for stale price Feed Data
 * If the price feed data is stale, the function will revert and render the DSCEngine unusable by design.
 * We want DSCEngine to freeze if prices become stale.
 * So if chainlink oracles explode, and the protocol had a ton of money, We get covered.
 * @dev This library is intended to be used with Chainlink price feeds.
 *
 */

library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant STALE_PRICE_TIME = 3 hours;

    function StaleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > STALE_PRICE_TIME) {
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
