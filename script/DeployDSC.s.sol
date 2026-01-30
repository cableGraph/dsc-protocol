// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DSCEngineV1/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngineV1/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    uint8[] public expectedDecimals;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();

        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc, // uint256 deployerKey
        ) = config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        expectedDecimals = new uint8[](2);
        expectedDecimals[0] = 18;
        expectedDecimals[1] = 8;

        vm.startBroadcast();
        DecentralizedStableCoin dscToken = new DecentralizedStableCoin();
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dscToken), expectedDecimals);
        dscToken.transferOwnership(address(dscEngine));

        vm.stopBroadcast();

        return (dscToken, dscEngine, config);
    }
}
