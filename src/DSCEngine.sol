// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./Libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author CableGraph
 * The system design is minimalistic as possible and have the tokens maintain the 1 token = $1 peg.
 * The token has the properties:
 * - Exogenous Collateral
 * - Algorithmic Supply Control
 * - Pegged to USD
 * - Crypto Collateral Backing
 * Our DS system should always be overcollateralized to ensure the stability of the coin.
 * At no point should the value of all the collateral be less than the value of all the DSC tokens.
 *
 * It's similar to DAI if DAI had no governance, no fees and was only backed by wETH and wBTC.
 * @notice This contract is the core of the DSC system.
 * It handles all the logic for minting and redeeming DSC, as well as depositing and
 * withdrawing collateral.
 * @notice This contract is very loosely based on the MakerDAO DSS (DAI Stablecoin System).
 */
contract DSCEngine is ReentrancyGuard {
    //////////////////
    ////ERRORS///////
    //////////////////
    error DSCEngine__AmountMustBeAboveZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesLengthMismatch();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__BreaksHealthFactor(uint256 HealthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__InvalidAmount();
    DecentralizedStableCoin private immutable i_dsc;
    /////////////////
    //// Type ////
    ///////////////
    using OracleLib for AggregatorV3Interface;
    using SafeERC20 for IERC20;
    /////////////////
    //// EVENTS ////
    ///////////////
    event CollateralDeposited(
        address indexed user,
        address indexed tokenCollateralAddress,
        uint256 collateralAmount
    );
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        uint256 amountCollateral,
        address indexed tokenCollateralAddress
    );
    event DSCBurned(
        address indexed burnedFrom,
        address indexed burnedBy,
        uint256 amountBurned
    );
    event DSCMinted(address indexed minter, uint256 amountMinted);

    //////////////////////
    //// STATE VARS /////
    ////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 150; //200%
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint8 private constant STANDARD_DECIMALS = 18;
    uint256 private constant HEALTH_FACTOR_NUMERATOR =
        (LIQUIDATION_THRESHOLD * PRECISION) / LIQUIDATION_PRECISION;

    address public owner = msg.sender;
    bool public paused;

    struct UserAccount {
        uint256 DSCMinted;
        mapping(address => uint256) collateral;
        address[] tokensUsed;
    }

    mapping(address => UserAccount) private s_accounts;
    mapping(address token => uint8 decimals) private s_tokenDecimals;
    mapping(address token => address priceFeed) private s_priceFeeds;
    address[] private s_collateralTokens;

    modifier isAllowedToken(address token) {
        __isAllowedToken(token);
        _;
    }
    modifier moreThanZero(uint256 amount) {
        __moreThanZero(amount);
        _;
    }
    modifier notPaused() {
        require(!paused, "paused");
        _;
    }

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscEngine,
        uint8[] memory expectedDecimals
    ) {
        require(dscEngine != address(0), "Invalid DSC address");

        owner = msg.sender;

        uint256 tokenAddrLength = tokenAddresses.length;
        uint256 priceFeedAddrLength = priceFeedAddresses.length;

        if (
            tokenAddrLength != priceFeedAddrLength ||
            tokenAddrLength != expectedDecimals.length
        ) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesLengthMismatch();
        }
        address[] memory _tokenAddresses = tokenAddresses;
        address[] memory _priceFeeds = priceFeedAddresses;

        for (uint256 i; i < tokenAddrLength; ) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeeds[i];
            s_collateralTokens.push(_tokenAddresses[i]);
            s_tokenDecimals[_tokenAddresses[i]] = expectedDecimals[i];

            unchecked {
                i++;
            }
        }
        i_dsc = DecentralizedStableCoin(dscEngine);
    }

    //////////////////////////////
    //// EXTERNAL FUNCTIONS /////
    ////////////////////////////
    /**
     * follows CEI
     * tokenCollateralAddress - the address of the token to Deposit as collateral
     * collateralAmount - the amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 collateralAmount
    )
        public
        nonReentrant
        moreThanZero(collateralAmount)
        isAllowedToken(tokenCollateralAddress)
        notPaused
    {
        require(tokenCollateralAddress != address(0), "Invalid token");

        UserAccount storage account = s_accounts[msg.sender];
        uint256 currentCollateral = account.collateral[tokenCollateralAddress];
        if (currentCollateral == 0) {
            account.tokensUsed.push(tokenCollateralAddress);
        }

        account.collateral[tokenCollateralAddress] =
            currentCollateral +
            collateralAmount;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            collateralAmount
        );

        IERC20(tokenCollateralAddress).safeTransferFrom(
            msg.sender,
            address(this),
            collateralAmount
        );
    }

    /**
     * @notice follows the CEI patern
     * @param amountDSCToMint - the amount of decentralized stable coin to mint
     * @notice they must have more collateral value than the minimum threshhold
     */
    function mintDSC(
        uint256 amountDSCToMint
    ) public nonReentrant moreThanZero(amountDSCToMint) notPaused {
        UserAccount storage account = s_accounts[msg.sender];
        uint256 newDSCMinted = account.DSCMinted + amountDSCToMint;

        uint256 healthFactor = _calculateHealthFactorForAccount(
            msg.sender,
            newDSCMinted
        );
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(healthFactor);
        }

        account.DSCMinted = newDSCMinted;
        emit DSCMinted(msg.sender, amountDSCToMint);
    

        /**
         * @dev Using boolean check for defensive programming - handles both
         *     revert-on-failure and bool-return mint implementations
         */
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 collateralAmount,
        uint256 amountDSCToMint
    ) external nonReentrant moreThanZero(collateralAmount) notPaused {
        depositCollateral(tokenCollateralAddress, collateralAmount);
        mintDSC(amountDSCToMint);
    }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public nonReentrant moreThanZero(amountCollateral) {
        require(tokenCollateralAddress != address(0), "Invalid token");

        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDSC(uint256 amount) public nonReentrant moreThanZero(amount) {
        require(msg.sender != address(0), "Invalid user");

        _burnDSC(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * This function burns and redeem the underying collateral in one tx.
     * Health factor checked in the redeemCollateral func
     * @param tokenCollateralAddress The collateralAddress to redeem.
     * @param amountCollateral The amountOfCollateral to redeem.
     * @param amountDSCToBurn The amount of DSC to burn.
     */
    function redeemCollateralForDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToBurn
    ) external nonReentrant {
        require(
            tokenCollateralAddress != address(0),
            "Invalid collateral token"
        );
        require(msg.sender != address(0), "Invalid user");

        burnDSC(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        //Health factor checked in the redeemCollateral func
    }

    /**
     * Follows CEI
     * @param collateral The ERC20 collateral address to liquidate.
     * @param user The user who has brocken their health Factor.
     * Their healthFactor should be below MIN_HEALTH_FACTOR.
     * @param debtToCover The amount of DCS you want to burn to improve the user's
     * Health Factor.
     * @notice You can partially liquidate a user.
     * @notice You will get a bonus for taking the users funds.
     * @notice This function working assumes that the protocal will be roughly
     * 200% overcollateralized for this to work.
     * @notice A known bug would be if the collateral were 100% or less collateralized
     * then we wouldn't be able to incentivise liquidators
     * @notice For example if the price of the collateral plummeted before anyone
     * could be liquidated
     */
    function liquidate(
        address user,
        address collateral,
        uint256 debtToCover
    ) external nonReentrant moreThanZero(debtToCover) notPaused {
        require(user != address(0), "Invalid user address");
        require(collateral != address(0), "Invalid collateral token");
        require(msg.sender != address(0), "Invalid liquidator");

        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        uint256 tokenPrice = _getAdjustedPrice(collateral);
        uint8 tokenDecimals = s_tokenDecimals[collateral];

        uint256 normalizedTokenAmount = (debtToCover * PRECISION) / tokenPrice;
        uint256 tokenAmountFromDebtCovered = tokenDecimals == STANDARD_DECIMALS
            ? normalizedTokenAmount
            : normalizedTokenAmount /
                (10 ** (STANDARD_DECIMALS - tokenDecimals));

        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;
        UserAccount storage account = s_accounts[user];
        require(
            account.collateral[collateral] >= totalCollateralToRedeem,
            "Not enough collateral"
        );

        account.collateral[collateral] -= totalCollateralToRedeem;
        account.DSCMinted -= debtToCover;
        emit CollateralRedeemed(
            user,
            msg.sender,
            totalCollateralToRedeem,
            collateral
        );

        IERC20(collateral).safeTransfer(msg.sender, totalCollateralToRedeem);
        IERC20(address(i_dsc)).safeTransferFrom(
            msg.sender,
            address(this),
            debtToCover
        );
        i_dsc.burn(debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function emergencyWithdraw(address token) external {
        require(msg.sender == owner, "Not owner");
        require(paused, "Not paused");
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(owner, balance);
    }

    

    function pause() external {
        require(msg.sender == owner, "Not owner");
        paused = true;
    }

    function unpause() external {
        require(msg.sender == owner, "Not owner");
        paused = false;
    }

    ////////////////////////////////////////
    //// PRIVATE AND INTERNAL FUNCTIONS ////
    ////////////////////////////////////////
    /**
     * @dev Low level Internal function! Do not call it unless the functions calling it
     * is checking for health factor being brocken
     */
    function _burnDSC(
        uint256 amountToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        if (amountToBurn == 0) revert DSCEngine__InvalidAmount();

        UserAccount storage account = s_accounts[onBehalfOf];
        require(
            account.DSCMinted >= amountToBurn,
            "Cannot Burn More Than Minted"
        );
        account.DSCMinted -= amountToBurn;
        emit DSCBurned(onBehalfOf, dscFrom, amountToBurn);

        IERC20(address(i_dsc)).safeTransferFrom(
            dscFrom,
            address(this),
            amountToBurn
        );
        i_dsc.burn(amountToBurn);
    }

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        UserAccount storage account = s_accounts[from];
        account.collateral[tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            amountCollateral,
            tokenCollateralAddress
        );
        IERC20(tokenCollateralAddress).safeTransfer(to, amountCollateral);
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUsd)
    {
        UserAccount storage account = s_accounts[user];
        totalDSCMinted = account.DSCMinted;
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * Returns how close the user is to liquidation
     * @dev if the health factor drops below 1, the user is liquidatable
     * @param user - the user to calculate the health factor for
     * @return the health factor of the user
     */
    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalDSCMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        if (totalDSCMinted == 0) {
            return type(uint256).max;
        }
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUsd);
    }

    function _calculateHealthFactor(
        uint256 totalDSCMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        if (totalDSCMinted == 0) return type(uint256).max;
        return
            (collateralValueInUsd * HEALTH_FACTOR_NUMERATOR) / totalDSCMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function __isAllowedToken(address token) internal view {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
    }

    function __moreThanZero(uint256 amount) internal pure {
        if (amount == 0) {
            revert DSCEngine__AmountMustBeAboveZero();
        }
    }

    function _getAdjustedPrice(address token) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.StaleCheckLatestRoundData();
        uint8 feedDecimals = priceFeed.decimals();
        return uint256(price) * (10 ** (18 - feedDecimals));
    }

    function _calculateHealthFactorForAccount(
        address user,
        uint256 dscMinted
    ) private view returns (uint256) {
        if (dscMinted == 0) return type(uint256).max;
        uint256 collateralValue = getAccountCollateralValue(user);
        if (collateralValue == 0) return 0;
        return (collateralValue * HEALTH_FACTOR_NUMERATOR) / dscMinted;
    }

    //////////////////////////////////
    ////// BATCH FUNCTIONS///////////
    ////////////////////////////////
    function getMultipleAccountInformation(
        address[] calldata users
    )
        external
        view
        returns (
            uint256[] memory totalDSCMinted,
            uint256[] memory collateralValues
        )
    {
        uint256 length = users.length;
        totalDSCMinted = new uint256[](length);
        collateralValues = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            UserAccount storage account = s_accounts[users[i]];
            totalDSCMinted[i] = account.DSCMinted;
            collateralValues[i] = getAccountCollateralValue(users[i]);
        }
    }

    function getMultipleTokenPrices(
        address[] calldata tokens
    ) external view returns (uint256[] memory prices) {
        uint256 length = tokens.length;
        prices = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            prices[i] = _getAdjustedPrice(tokens[i]);
        }
    }

    ///////////////////////////////////////////
    //// PUBLIC EXTERNAL VIEW FUNCTIONS //////
    /////////////////////////////////////////
    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        uint256 adjustedPrice = _getAdjustedPrice(token);
        uint8 tokenDecimals = s_tokenDecimals[token];

        uint256 normalizedAmount = (usdAmountInWei * PRECISION) / adjustedPrice;

        return
            tokenDecimals == STANDARD_DECIMALS
                ? normalizedAmount
                : normalizedAmount /
                    (10 ** (STANDARD_DECIMALS - tokenDecimals));
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalValueInUsd) {
        UserAccount storage account = s_accounts[user];
        address[] memory tokens = account.tokensUsed.length > 0
            ? account.tokensUsed
            : s_collateralTokens;
        uint256 len = tokens.length;

        for (uint256 i; i < len; ) {
            address token = tokens[i];
            uint256 amount = account.collateral[token];
            if (amount != 0) {
                uint256 adjustedPrice = _getAdjustedPrice(token);
                uint8 tokenDecimals = s_tokenDecimals[token];

                uint256 normalizedAmount = tokenDecimals == STANDARD_DECIMALS
                    ? amount
                    : amount * (10 ** (STANDARD_DECIMALS - tokenDecimals));
                totalValueInUsd +=
                    (normalizedAmount * adjustedPrice) /
                    PRECISION;
            }

            unchecked {
                ++i;
            }
        }
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        uint8 tokenDecimals = s_tokenDecimals[token];
        uint256 adjustedPrice = _getAdjustedPrice(token);

        uint256 normalizedAmount = tokenDecimals == STANDARD_DECIMALS
            ? amount
            : amount * (10 ** (STANDARD_DECIMALS - tokenDecimals));

        return (normalizedAmount * adjustedPrice) / PRECISION;
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUsd)
    {
        (totalDSCMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralDeposited(
        address user,
        address token
    ) external view returns (uint256) {
        return s_accounts[user].collateral[token];
    }

    function calculateHealthFactor(
        uint256 totalDSCMinted,
        uint256 collateralValueInUsd
    ) external pure returns (uint256) {
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUsd);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        require(user != address(0), "Invalid user address");
        return _healthFactor(user);
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(
        address user,
        address token
    ) public view returns (uint256) {
        return s_accounts[user].collateral[token];
    }

    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_priceFeeds[token];
    }
}
