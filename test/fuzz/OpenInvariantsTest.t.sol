//  // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.18;

// import {Test, console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DSCEngine} from "src/DSCEngine.sol";
// import {DeployDSC} from "script/DeployDSC.s.sol";
// import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
// import {HelperConfig} from "script/HelperConfig.s.sol";
// import {ERC20Mock} from "../Mocks/ERC20Mock.sol";

// contract InvariantTests is StdInvariant, Test {
//     DeployDSC deployer;
//     DSCEngine dscE;
//     DecentralizedStableCoin dsc;
//     HelperConfig config;
//     address weth;
//     address wbtc;

//     function setUp() external {
//         deployer = new DeployDSC();
//         (dsc, dscE, config) = deployer.run();
//         (, , weth, wbtc, ) = config.activeNetworkConfig();

//         targetContract(address(dscE));
//     }
//     function invariant_protocalMustHaveMoreValueThanTotalSupply() public view {
//         // we wanna get the value of all the collateral in the protocal
//         // and compare it to all the debt (DSC)
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethDeposited = ERC20Mock(weth).balanceOf(address(dscE));
//         uint256 totalBtcDeposited = ERC20Mock(wbtc).balanceOf(address(dscE));
//         given
//         uint256 wethValue = dscE.getUsdValue(weth, totalWethDeposited);
//         uint256 wbtcValue = dscE.getUsdValue(wbtc, totalBtcDeposited);

//         console.log("weth value:", wethValue);
//         console.log("wbtc value", wbtcValue);
//         console.log("totalSupply", totalSupply);

//         assert(wethValue + wbtcValue >= totalSupply);
//     }
// }
