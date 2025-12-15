# DSCEngine — Line-by-Line Professional Audit

> **Status:** Audit started. This document is the working audit canvas. It contains: (1) a prioritized list of findings, (2) a line-by-line checklist you can apply to every function/section, (3) concrete fixes and code snippets for common issues (SafeERC20, mint/burn, redeems, oracles, reentrancy), and (4) test & CI guidance to prove security. Update this doc with your contract source or paste problematic functions and I'll annotate them inline.

---

## 1) How this audit will proceed (methodology)

1. **Automated surface scan (developer-level):** imports, interfaces, modifiers, storage layout, public variables, external calls.
2. **Line-by-line code review:** every function and modifier; check preconditions, postconditions, state updates order, events, error handling.
3. **Economic & invariant analysis:** validate mint/burn flows, collateral accounting, health-factor math, rounding, and liquidation economics.
4. **Attack-scenario enumeration:** flash-loan, oracle manipulation, reentrancy, griefing, denial-of-service, malicious ERC20 tokens.
5. **Test harness cross-check:** confirm unit/fuzz/invariant tests coverage maps to every high-risk path.
6. **Tooling pass:** Slither, foundry fuzz/invariant runs, Echidna/SMT fuzzing where applicable.
7. **Remediation suggestions and patches** with code snippets and gas-aware alternatives.

---

## 2) Immediate high-priority findings (apply first)

These are things you should fix immediately across the codebase (global changes):

* **Use SafeERC20 everywhere.** Replace raw `.call`, `.transfer`, and `.transferFrom` uses with `IERC20(...).safeTransfer(...)` / `safeTransferFrom(...)` after importing `SafeERC20` and applying `using SafeERC20 for IERC20;`.

* **Normalize token decimals early.** All price math should convert token collateral amounts into USD with a standardized `PRECISION` (e.g., 1e18) and be explicit about token decimals in price feed wrappers.

* **Add explicit oracle sanity checks**: `require(price > 0)` and `require(block.timestamp - lastUpdated < ORACLE_MAX_AGE)` or similar.

* **Remove boolean-transfer checks**: where you currently do `bool success = token.transfer(...)` remove and use SafeERC20; if you rely on `bool` from `mint()` keep it or prefer revert-on-failure design.

* **Guard all external calls with reentrancy and state ordering**: state updates before external calls, or use the Checks-Effects-Interactions pattern.

* **Enforce role-based emergency controls behind multisig + timelock** if you have privileged functions.

---

## 3) Line-by-line checklist (apply to each function / modifier)

For every function, run through these checks and annotate the source with ✅/⚠️/❌.

1. **Signature & visibility** — correct visibility and mutability (`public` vs `external` vs `view` vs `pure`)? payable only when required.
2. **Modifiers** — are they restrictive enough? `onlyOwner`, `nonReentrant`, `isAllowedToken`, `moreThanZero` — verify they revert early.
3. **Input validation** — `address(0)` checks, `amount > 0`, token listed, decimals sanity.
4. **State reads** — cached in local variables where possible to save gas and reduce SLOADs.
5. **Checks-Effects-Interactions** — perform checks first, then update local state, then external calls.
6. **External calls** — wrap token calls with `SafeERC20`; wrap external protocol calls with `try/catch` if they revert unpredictably.
7. **Events** — emitted AFTER successful state update and before/after external interactions as appropriate.
8. **Error handling** — use custom errors where practical (gas savings) and consistent error names.
9. **Gas/loop risks** — if pushing into arrays (`tokensUsed.push`) consider duplicates & unbounded growth; add cap or dedupe.
10. **Reentrancy** — nonReentrant modifier or manual reentrancy guard; ensure state is updated before transfers.
11. **Precision & overflow** — validate use of `unchecked` and safe multipliers.
12. **Test mapping** — map tests (unit/fuzz/invariant) to this function’s high-risk paths.

---

## 4) Concrete fixes and examples (apply and search across repo)

### A. Imports & using

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DSCEngine is ReentrancyGuard {
    using SafeERC20 for IERC20;
    // ...
}
```

Search & replace all raw token interactions.

### B. `depositCollateral` — safe pattern (Checks-Effects-Interactions)

**Pattern to use:**

1. Validate inputs & token allowed.
2. Update accounting (EFFECTS).
3. Emit event.
4. `safeTransferFrom` (INTERACTIONS).

```solidity
function depositCollateral(address tokenCollateralAddress, uint256 collateralAmount)
    public
    nonReentrant
    moreThanZero(collateralAmount)
    isAllowedToken(tokenCollateralAddress)
{
    // Checks done by modifiers

    UserAccount storage account = s_accounts[msg.sender];
    uint256 currentCollateral = account.collateral[tokenCollateralAddress];

    if (currentCollateral == 0) {
        account.tokensUsed.push(tokenCollateralAddress);
    }

    unchecked {
        account.collateral[tokenCollateralAddress] = currentCollateral + collateralAmount;
    }

    emit CollateralDeposited(msg.sender, tokenCollateralAddress, collateralAmount);

    // Interaction
    IERC20(tokenCollateralAddress).safeTransferFrom(msg.sender, address(this), collateralAmount);
}
```

**Extra checks to add:**

* Confirm `tokenCollateralAddress` has a price feed and decimals mapping.
* `require(tokenDecimals <= 36)` (safety bound).

### C. `_redeemCollateral` — safe transfer out

* Always update accounting first.
* Avoid using boolean returns; use `safeTransfer`.
* Prevent dust: if resulting collateral underflow or small rounding dust, handle.

```solidity
function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) private {
    UserAccount storage account = s_accounts[from];

    // Effects
    uint256 current = account.collateral[tokenCollateralAddress];
    require(current >= amountCollateral, "Insufficient collateral");
    unchecked { account.collateral[tokenCollateralAddress] = current - amountCollateral; }

    emit CollateralRedeemed(from, to, amountCollateral, tokenCollateralAddress);

    // Interaction
    IERC20(tokenCollateralAddress).safeTransfer(to, amountCollateral);
}
```

### D. Burn flow (pull DSC then burn)

If `i_dsc` implements `burn(uint256)` and `mint`:

```solidity
function burnDsc(address dscFrom, uint256 amountToBurn) internal {
    IERC20(address(i_dsc)).safeTransferFrom(dscFrom, address(this), amountToBurn);
    i_dsc.burn(amountToBurn); // assume burn is internal and will revert on failure
}
```

If `i_dsc.mint` returns bool, keep the bool check; if it reverts on failure, prefer try/catch.

### E. Mint flow — best practice

* **Preferred token design:** `mint()` should `revert` on failure (no bool). If that is the case, call `i_dsc.mint(...)` and optionally wrap in `try/catch` to convert to custom error.

```solidity
try i_dsc.mint(msg.sender, amount) {} catch {
    revert DSCEngine__MintFailed();
}
```

If `mint()` returns `bool`:

```solidity
bool minted = i_dsc.mint(msg.sender, amount);
if (!minted) revert DSCEngine__MintFailed();
```

### F. Health factor math — prefer precomputed constant (gas) but ensure precision

If you use `HEALTH_FACTOR_NUMERATOR` constant, ensure it is computed without truncation loss. Add unit tests for extremes (tiny collateral, huge collateral). Add `require(dscMinted > 0)` or handle zero-case.

### G. Oracle calls (wrap and sanity check)

Always call Chainlink or any feed via a wrapper:

```solidity
function getPrice(address token) internal view returns (uint256 price, uint8 decimals) {
    AggregatorV3Interface feed = s_priceFeeds[token];
    (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();
    require(answer > 0, "Invalid price");
    require(block.timestamp - updatedAt <= ORACLE_MAX_AGE, "Stale price");
    return (uint256(answer), feed.decimals());
}
```

### H. Access control & admin patterns

* Prefer `Ownable` + `timelock` for admin-critical operations. Keep `pause()` under multisig.
* If using upgradeable pattern, freeze initialization and use `onlyProxyAdmin` checks.

---

## 5) Tests & fuzz additions to strengthen confidence

Add/update the following tests (Foundry preferred):

* **Fuzz mint/deposit/withdraw:** random user amounts, random token decimals.
* **Oracle staleness simulation:** warp time and ensure critical functions revert if price too old.
* **Flash-loan simulation:** attacker borrows massive DSC or collateral and tries to manipulate HF and liquidate across block.
* **Malicious ERC20 mocks:** token that reverts on `transfer`, token that consumes all gas in fallback, token that returns false.
* **Invariant tests:** total minted ≤ total collateral value * liquidation threshold; sum of all user collateral balances equals contract token balance for each token.
* **Integration tests with multiple tokens and multiple users:** chained deposits, partial redeems, multiple liquidations.

---

## 6) Static analysis & CI

Add to CI pipeline:

1. `forge test` (with coverage) — fail on < 95% for critical modules
2. `slither .` — fix high/medium findings or mark false positives with comments
3. `myth`/`mythril` or `manticore` for additional checks
4. `echidna` fuzzing for invariants
5. `safety checks` — verify no tx uses `delegatecall` from user-supplied addresses

---

## 7) Deliverables I will produce as I perform the line-by-line audit

* **Annotated source**: I will take each function and annotate risk, recommended patch, test cases; mark severity.
* **Remediation patches**: minimal diff-ready code blocks to paste into your contract
* **Test additions**: Foundry test cases to add per function
* **Final audit report**: executive summary, full findings, severity (Critical/High/Medium/Low), and acceptance checklist

---

## 8) Next steps (how you can help me immediately)

Paste the full `DSCEngine.sol` contract (or point to the main functions) into this canvas under a new section and I will start annotating line-by-line. If you prefer, paste only functions in the following order I will audit them:

1. constructor & initialization
2. depositCollateral / redeemCollateral
3. mint / burn / mintDsc
4. liquidate / _liquidate
5. health factor calc & price fetchers
6. role and admin functions
7. modifiers a

herii

---

## 9) PASTED CONTRACT — Line-by-line annotations

Below I paste your contract and annotate each section with findings, suggested fixes, and explicit code patches. Use this as the single source of truth for remediation.

```solidity
// SPDX-License-Identifier: MIT

// This is considered an Exogenouns, Decentralized, Anchored (pegged), Crypto Collateralized low volatility coin

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

    //////////////////////
    //// STATE VARS /////
    ////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200%
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant HEALTH_FACTOR_NUMERATOR =
        (LIQUIDATION_THRESHOLD * PRECISION) / LIQUIDATION_PRECISION;

    struct UserAccount {
        uint256 DSCMinted;
        mapping(address => uint256) collateral;
        address[] tokensUsed;
    }

    mapping(address => UserAccount) private s_accounts;

    mapping(address token => address priceFed) private s_priceFeeds;
    address[] private s_collateralTokens;

    modifier isAllowedToken(address token) {
        __isAllowedToken(token);
        _;
    }
    modifier moreThanZero(uint256 amount) {
        __moreThanZero(amount);
        _;
    }

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscEngine
    ) {
        uint256 length = tokenAddresses.length;
        if (length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesLengthMismatch();
        }
        address[] memory _tokenAddresses = tokenAddresses;
        address[] memory _priceFeeds = priceFeedAddresses;

        for (uint256 i; i < length; ) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeeds[i];
            s_collateralTokens.push(_tokenAddresses[i]);
            unchecked {
                i++;
            }
        }

        i_dsc = DecentralizedStableCoin(dscEngine);
    }

    //////////////////////////////
    //// EXTERNAL FUNCTIONS /////
    ////////////////////////////

    function depositCollateral(
        address tokenCollateralAddress,
        uint256 collateralAmount
    )
        public
        nonReentrant
        moreThanZero(collateralAmount)
        isAllowedToken(tokenCollateralAddress)
    {
        UserAccount storage account = s_accounts[msg.sender];
        uint256 currentCollateral = account.collateral[tokenCollateralAddress];
        if (currentCollateral == 0) {
            account.tokensUsed.push(tokenCollateralAddress);
        }
        account.collateral[tokenCollateralAddress] =
            currentCollateral +
            collateralAmount;

        IERC20(tokenCollateralAddress).safeTransferFrom(
            msg.sender,
            address(this),
            collateralAmount
        );
    }

    function mintDSC(
        uint256 amountDSCToMint
    ) public nonReentrant moreThanZero(amountDSCToMint) {
        UserAccount storage account = s_accounts[msg.sender];
        uint256 newDSCMinted = account.DSCMinted + amountDSCToMint;
        account.DSCMinted = newDSCMinted;

        uint256 healthFactor = _calculateHealthFactorForAccount(
            msg.sender,
            newDSCMinted
        );
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(healthFactor);
        }
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 collateralAmount,
        uint256 amountDSCToMint
    ) external moreThanZero(collateralAmount) {
        depositCollateral(tokenCollateralAddress, collateralAmount);
        mintDSC(amountDSCToMint);
    }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public nonReentrant moreThanZero(amountCollateral) {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDSC(uint256 amount) public moreThanZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateralForDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToBurn
    ) external {
        burnDSC(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function liquidate(
        address user,
        address collateral,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        uint256 tokenPrice = _getAdjustedPrice(collateral);
        uint256 tokenAmountFromDebtCovered = (debtToCover * PRECISION) /
            (tokenPrice * PRECISION);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;

        _redeemCollateral(
            collateral,
            totalCollateralToRedeem,
            user,
            msg.sender
        );
        _burnDSC(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ////////////////////////////////////////
    //// PRIVATE AND INTERNAL FUNCTIONS ///
    ////////////////////////////////////////

    function _burnDSC(
        uint256 amountToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        UserAccount storage account = s_accounts[onBehalfOf];
        account.DSCMinted -= amountToBurn;

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
        return (uint256(price) * ADDITIONAL_FEED_PRECISION) / PRECISION;
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

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        uint256 adjustedPrice = _getAdjustedPrice(token);
        return (usdAmountInWei * PRECISION) / (adjustedPrice * PRECISION);
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
                totalValueInUsd += adjustedPrice * amount;
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
        return _getAdjustedPrice(token) * amount;
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
```

---

### Line-by-line findings & remediation (prioritized)

I reviewed the pasted contract and produced targeted findings below grouped by severity. For each finding I give: (A) short description, (B) exact location (function/line), (C) impact, (D) recommended fix & code snippet.

#### Critical / High

1. **No oracle staleness or zero-price checks in `_getAdjustedPrice`**

* Location: `_getAdjustedPrice`
* Impact: If price feed returns zero or stale data, protocol's health math breaks → incorrect liquidations and potential loss.
* Fix: Use `latestRoundData()` and validate `answer > 0` and `block.timestamp - updatedAt <= ORACLE_MAX_AGE`. Use `OracleLib.StaleCheckLatestRoundData()` only if that wrapper includes checks; otherwise add explicit checks.

```solidity
function _getAdjustedPrice(address token) internal view returns (uint256) {
    AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
    (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
    if (price <= 0) revert DSCEngine__TokenNotAllowed();
    require(block.timestamp - updatedAt <= ORACLE_MAX_AGE, "Stale price");
    return (uint256(price) * ADDITIONAL_FEED_PRECISION) / PRECISION;
}
```

Add `uint256 private constant ORACLE_MAX_AGE = 1 hours;` (or config param).

2. **Unsafe math order in `liquidate` price -> tokenAmountFromDebtCovered**

* Location: `liquidate`
* Impact: Expression `(debtToCover * PRECISION) / (tokenPrice * PRECISION)` simplifies to `debtToCover / tokenPrice` but multiplication by PRECISION twice cancels; may lead to division by zero or precision issues.
* Fix: Prefer `(debtToCover * PRECISION) / tokenPrice` if tokenPrice is already scaled to PRECISION. Clarify price scaling; add `require(tokenPrice > 0)`.

3. **Missing underflow/overflow checks around user balances**

* Location: `_burnDSC`, `_redeemCollateral`, mintDSC
* Impact: You subtract without checking; if attacker gets into path where amount > balance it will underflow (in Solidity 0.8+ it reverts, but better to require explicit checks and give clear error)
* Fix: Add `require(account.DSCMinted >= amountToBurn)` in `_burnDSC` and `require(current >= amountCollateral)` in `_redeemCollateral` and protect mint increments.

#### Medium

4. **`tokensUsed` array can grow unbounded and contain duplicates**

* Location: `depositCollateral`
* Impact: Gas DoS for loops that iterate `tokensUsed`; expensive calls to `getAccountCollateralValue` may gas out.
* Fix: Deduplicate on push or limit size by config. Add mapping to check presence `mapping(address => mapping(address => bool)) s_userTokenExists;` or push only if not present.

5. **No admin/pausing or timelock for critical operations**

* Location: Global
* Impact: If an admin key is compromised, protocol vulnerable.
* Fix: Add `Ownable`, `Pausable` or require multisig timelock for upgrades and price feed changes.

6. **`getTokenAmountFromUsd` and other math have redundant `* PRECISION` cancels**

* Location: `getTokenAmountFromUsd`, `getAccountCollateralValue`, `getUsdValue`
* Impact: Confusing math and potential loss of precision.
* Fix: Standardize price scaling and simplify formulae.

#### Low

7. **`mintDSC` updates state before checking health factor**

* Location: `mintDSC` — updates `account.DSCMinted = newDSCMinted` then calculates healthFactor. This is OK for CEI but may be surprising if further external calls revert.
* Fix: It's consistent with CEI; keep but consider calculating health factor using `newDSCMinted` without committing state until after checks to reduce reverts' side effects.

8. **`getTokenAmountFromUsd` divides by `(adjustedPrice * PRECISION)` leading to potential division by zero**

* Fix: Ensure `adjustedPrice > 0`.

9. **Naming & comments: minor typos and clarity issues (e.g., 'Exogenouns')**

---

## Recommended immediate patches (copy/paste)

1. Add constants and imports at top:

```solidity
uint256 private constant ORACLE_MAX_AGE = 1 hours;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; // if using
```

2. Harden `_redeemCollateral`:

```solidity
function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) private {
    UserAccount storage account = s_accounts[from];
    uint256 current = account.collateral[tokenCollateralAddress];
    if (current < amountCollateral) revert DSCEngine__AmountMustBeAboveZero(); // better custom error
    unchecked { account.collateral[tokenCollateralAddress] = current - amountCollateral; }
    emit CollateralRedeemed(from, to, amountCollateral, tokenCollateralAddress);
    IERC20(tokenCollateralAddress).safeTransfer(to, amountCollateral);
}
```

3. Harden `_burnDSC`:

```solidity
function _burnDSC(uint256 amountToBurn, address onBehalfOf, address dscFrom) private {
    UserAccount storage account = s_accounts[onBehalfOf];
    if (account.DSCMinted < amountToBurn) revert DSCEngine__AmountMustBeAboveZero();
    unchecked { account.DSCMinted = account.DSCMinted - amountToBurn; }
    IERC20(address(i_dsc)).safeTransferFrom(dscFrom, address(this), amountToBurn);
    i_dsc.burn(amountToBurn);
}
```

4. Fix `liquidate` token amount calc:

```solidity
uint256 tokenAmountFromDebtCovered = (debtToCover * PRECISION) / tokenPrice; // if tokenPrice scaled to PRECISION
```

5. Dedupe tokensUsed push:

```solidity
mapping(address => mapping(address => bool)) private s_userHasToken;
// in depositCollateral
if (!s_userHasToken[msg.sender][tokenCollateralAddress]) {
    account.tokensUsed.push(tokenCollateralAddress);
    s_userHasToken[msg.sender][tokenCollateralAddress] = true;
}
```

---

## Tests to add (priority order)

1. Oracle staleness tests (warp beyond ORACLE_MAX_AGE) causing reverts.
2. Fuzz of deposit → mint → partial redeem → liquidate with random prices.
3. Malicious ERC20 tokens that revert on `transfer` or return `false`.
4. Gas exhaustion test for `getAccountCollateralValue` with many tokensUsed.
5. Underflow/overflow tests for `_burnDSC` and `_redeemCollateral` paths.

---

## Next steps I will take (if you confirm)

1. I will continue annotating each function with exact line numbers and severity if you want deeper granularity.
2. I can produce patch diffs you can apply directly.
3. I can auto-generate Foundry test stubs for the new test cases.

---

*Paste any updated version or say "continue" and I will produce per-function line-numbered annotations and concrete git-style patch diffs.*
