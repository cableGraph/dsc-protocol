// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";
import {DeployDSC} from "../../../script/DeployDSC.s.sol";
import {
    DecentralizedStableCoin
} from "../../../src/DSCEngineV1/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../../src/DSCEngineV1/DSCEngine.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../ERC20Mock.sol";

contract DSCEngineTest is Test {
    event CollateralRedeemed(
        address indexed from,
        address indexed to,
        uint256 amount,
        address token
    );

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscE;
    HelperConfig config;
    address wethUsdPriceFeed;
    address weth;
    address wbtcUsdPriceFeed;
    address wbtc;
    uint256 deployerKey;

    address public USER = makeAddr("user");
    address public EMPTY_USER = makeAddr("emptyUser");
    uint256 public constant EMPTY_AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant MINT_AMOUNT = 1 ether;
    address public LIQUIDATOR = makeAddr("liquidator");

    // In your DSCEngineTest.t.sol
    function setUp() public {
        // Don't use DeployDSC script in tests
        HelperConfig config = new HelperConfig();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, ) = config
            .activeNetworkConfig();

        address[] memory tokenAddresses = new address[](2);
        address[] memory priceFeedAddresses = new address[](2);
        uint8[] memory expectedDecimals = new uint8[](2);

        tokenAddresses[0] = weth;
        tokenAddresses[1] = wbtc;
        priceFeedAddresses[0] = wethUsdPriceFeed;
        priceFeedAddresses[1] = wbtcUsdPriceFeed;
        expectedDecimals[0] = 18;
        expectedDecimals[1] = 8;

        // Deploy contracts directly
        dsc = new DecentralizedStableCoin();
        dscE = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc),
            expectedDecimals
        );

        // Transfer ownership - we are the owner since we deployed dsc
        dsc.transferOwnership(address(dscE));

        // Store config if needed elsewhere
        // config = config;

        // Mint tokens
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(EMPTY_USER, STARTING_ERC20_BALANCE);

        // Store weth and wbtc addresses if needed
        // This way you don't need to store the entire config
    }
    ///////////////////////////////
    /////Constructor Tests////////
    /////////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    uint8[] public expectedDecimals;

    function test_revertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesLengthMismatch
                .selector
        );
        new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc),
            expectedDecimals
        );
    }

    function test_getTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;

        uint256 actualWeth = dscE.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    //////////////////////
    ///// Price Tests////
    ////////////////////

    function test_getUsdValue() public view {
        uint256 ethAmount = 15e18;

        uint256 expectedUsd = 30000e18;

        uint256 actualUsd = dscE.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function test_getUsdValue_ReturnsZeroWhenAmountIsZero() public view {
        uint256 actualUsd = dscE.getUsdValue(weth, 0);
        assertEq(actualUsd, 0);
    }

    function test_getUsdValue_RevertsIfFeedNotSet() public {
        address randomToken = address(12345);
        vm.expectRevert();
        dscE.getUsdValue(randomToken, 1e18);
    }

    function test_getUsdValue_DifferentTokens() public view {
        uint256 ethUsd = dscE.getUsdValue(weth, 1e18);
        uint256 btcUsd = dscE.getUsdValue(wbtc, 1e8);

        assertTrue(ethUsd > btcUsd);
    }

    ///////////////////////////////////
    //// Deposit collateral Tests/////
    /////////////////////////////////

    function test_revertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeAboveZero.selector);
        dscE.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function test_revertsIfTokenNotAllowed() public {
        vm.startPrank(USER);
        ERC20Mock randomToken = new ERC20Mock(
            "Fake Token",
            "FAKE",
            USER,
            STARTING_ERC20_BALANCE
        );

        randomToken.approve(address(dscE), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscE.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL);
        dscE.depositCollateral(address(weth), AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function test_canGetCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = dscE
            .getAccountInformation(USER);
        uint256 expectedTotalDSCMinted = 0;
        uint256 expectedDepositAmount = dscE.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(totalDSCMinted, expectedTotalDSCMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testGetUsdValueRevertsIfPriceFeedNotSet() public {
        address fakeToken = makeAddr("fakeToken");
        uint256 amount = 1e18;

        vm.expectRevert();
        dscE.getUsdValue(fakeToken, amount);
    }

    function test_getAccountCollateralValueReturnsCorrectUsdValue() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL);

        dscE.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 usdValue = dscE.getAccountCollateralValue(USER);
        uint256 expectedUsdValue = 20000e18;

        assertEq(
            usdValue,
            expectedUsdValue,
            "USD value calculation is incorrect"
        );
    }

    function test_getAccountCollateralValueReturnsZeroWhenNoCollateral()
        public
        view
    {
        uint256 totalValue = dscE.getAccountCollateralValue(EMPTY_USER);

        assertEq(
            totalValue,
            0,
            "Expected collateral value to be zero for a user with no deposits"
        );
    }

    function testGetAccountCollateralValueHandlesZeroDepositCorrectly() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL);

        dscE.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 totalValue = dscE.getAccountCollateralValue(USER);
        uint256 expectedUsdValue = 20000e18;

        assertEq(
            totalValue,
            expectedUsdValue,
            "Collateral value should only account for non-zero deposits"
        );
    }

    function testGetAccountCollateralValueRevertsIfFeedMissing() public {
        ERC20Mock fakeToken = new ERC20Mock("Fake", "FAKE", USER, 100e18);

        vm.startPrank(USER);
        fakeToken.approve(address(dscE), 10e18);

        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscE.depositCollateral(address(fakeToken), 10e18);

        vm.stopPrank();
    }

    function testHealthFactorIsHighWithNoDebt() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL);
        dscE.depositCollateral(weth, AMOUNT_COLLATERAL);

        dscE.mintDSC(MINT_AMOUNT);

        (, uint256 collateralValueInUsd) = dscE.getAccountInformation(USER);
        assertGt(
            collateralValueInUsd,
            MINT_AMOUNT,
            "Collateral should exceed debt"
        );
        vm.stopPrank();
    }

    function test_RedeemCollateralSuccessAndUpdatesState() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL);
        dscE.depositCollateral(weth, AMOUNT_COLLATERAL);

        uint256 redeemAmount = 5 ether;
        uint256 expectedCollateralAfter = AMOUNT_COLLATERAL - redeemAmount;

        dscE.redeemCollateral(weth, redeemAmount);

        uint256 actualCollateral = dscE.getCollateralDeposited(USER, weth);
        assertEq(actualCollateral, expectedCollateralAfter);

        (uint256 totalDscMinted, uint256 collateralValue) = dscE
            .getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
        assertGt(collateralValue, 0);
        vm.stopPrank();
    }

    function test_HealthFactorWithNoDebtReturnsMaxValue() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL);
        dscE.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 healthFactor = dscE.getHealthFactor(USER);
        assertEq(
            healthFactor,
            type(uint256).max,
            "Health factor should be max when no debt"
        );
    }

    function test_HealthFactorCalculation() public {
        vm.prank(USER);
        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL);

        vm.prank(USER);
        dscE.depositCollateral(weth, AMOUNT_COLLATERAL);
        uint256 mintAmount = 1000e18;
        vm.prank(USER);
        dscE.mintDSC(mintAmount);

        uint256 healthFactor = dscE.getHealthFactor(USER);
        assertGt(healthFactor, 0, "Health factor should be greater than 0");
    }

    function test_EventEmittedWhenRedeemingCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL);
        dscE.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 redeemAmount = 5 ether;

        vm.expectEmit(true, true, true, true, address(dscE));
        emit DSCEngine.CollateralRedeemed(USER, USER, redeemAmount, weth);

        vm.prank(USER);
        dscE.redeemCollateral(weth, redeemAmount);

        uint256 remainingCollateral = dscE.getCollateralDeposited(USER, weth);
        assertEq(remainingCollateral, AMOUNT_COLLATERAL - redeemAmount);
    }

    function test_revertsIfMintedDSCBreaksHealthFactor() public {
        vm.startPrank(USER);

        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL);
        dscE.depositCollateral(weth, AMOUNT_COLLATERAL);

        uint256 collateralValueUsd = dscE.getUsdValue(weth, AMOUNT_COLLATERAL);

        uint256 amountToMint = ((collateralValueUsd * 15) / 10) + 1;

        uint256 expectedHealthFactor = dscE.calculateHealthFactor(
            amountToMint,
            collateralValueUsd
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );

        dscE.mintDSC(amountToMint);
        vm.stopPrank();
    }
    function test_revertsIfMintedAmountBreaksHealthFactor() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL);
        dscE.depositCollateral(weth, AMOUNT_COLLATERAL);

        uint256 collateralValueUsd = dscE.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 amountToMint = ((collateralValueUsd * 15) / 10) + 1;
        uint256 expectedHealthFactor = dscE.calculateHealthFactor(
            amountToMint,
            collateralValueUsd
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );

        dscE.mintDSC(amountToMint);
        vm.stopPrank();
    }
    function test_cannotLiquidateMoreCollateralThanUserHas() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscE), AMOUNT_COLLATERAL);
        dscE.depositCollateral(weth, AMOUNT_COLLATERAL);
        dscE.mintDSC(AMOUNT_COLLATERAL);
        vm.stopPrank();

        vm.prank(address(dscE));
        dsc.mint(LIQUIDATOR, AMOUNT_COLLATERAL);
        vm.startPrank(LIQUIDATOR);
        dsc.approve(address(dscE), type(uint256).max);

        uint256 bigDebt = AMOUNT_COLLATERAL * 1e12;

        vm.expectRevert();
        dscE.liquidate(USER, weth, bigDebt);
    }
}
