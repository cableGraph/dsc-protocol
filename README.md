

#  DeFi Protocol Core

![Solidity](https://img.shields.io/badge/Solidity-0.8.18-363636?style=for-the-badge&logo=solidity&logoColor=white)
![Foundry](https://img.shields.io/badge/Foundry-Framework-FF6B35?style=for-the-badge&logo=ethereum&logoColor=white)
![Chainlink](https://img.shields.io/badge/Chainlink-Oracles-375BD2?style=for-the-badge&logo=chainlink&logoColor=white)
![DeFi](https://img.shields.io/badge/DeFi-Protocol-8A2BE2?style=for-the-badge&logo=ethereum&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-00D4AA?style=for-the-badge)



##  Overview

The **Decentralized StableCoin (DSC)** Protocol is a sophisticated DeFi primitive delivering impermeable stablecoin infrastructure. Featuring algorithmic supply control, multi-collateral backing, and real-time risk management, it sets the standard for decentralized financial infrastructure.

## 🏗 Architecture

```mermaid
graph TB
    A[User] --> B[Deposit Collateral]
    B --> C[Health Factor Check]
    C --> D[Mint DSC]
    D --> E[Use in DeFi]
    E --> F[Redeem/Burn]
    F --> G[Withdraw Collateral]
    
    H[Liquidator] --> I[Monitor Positions]
    I --> J{Liquidation Check}
    J -->|Health < 1.0| K[Execute Liquidation]
    J -->|Health > 1.0| I
    
    L[Chainlink Oracles] --> M[Price Feeds]
    M --> N[Risk Engine]
    N --> C
```


### Live Deployment

| Contract | Address | Status |
|----------|----------|--------|
| **DSC Engine** | [`0xa9B9Ae7bC2D242CE380137BEFA82a184747b2f3C`](https://sepolia.etherscan.io/address/0xa9b9ae7bc2d242ce380137befa82a184747b2f3c) | ✅ Verified |
| **DSC Token** | [`0x7F3aBfdeBba3ee1C31704B2c9cbf0B4C0EbFf142`](https://sepolia.etherscan.io/address/0x7f3abfdebba3ee1c31704b2c9cbf0b4c0ebff142) | ✅ Verified |

##  Core Features

|  Security |  Performance |  Scalability |
|-------------|----------------|----------------|
| Multi-collateral backing | Sub-second liquidations | Extensible architecture |
| Real-time health monitoring | Gas-optimized operations | Cross-chain ready |
| Formal verification | CEI pattern enforcement | Enterprise integration |

### Smart Contract Suite

| Component | Role | Technology Stack |
|-----------|------|------------------|
| **DSCEngine** | Core protocol logic | Solidity 0.8.18, Foundry |
| **DecentralizedStableCoin** | Stablecoin token | ERC20, Burnable |
| **OracleLib** | Price security layer | Chainlink Aggregators |

##  Quick Start

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Installation & Development

```bash
# Clone and setup
git clone https://github.com/trustauto/dsc-protocol.git
cd dsc-protocol

# Install dependencies
forge install

# Compile contracts
forge build

# Run comprehensive test suite
forge test -vv
```

### Environment Configuration

```bash
# .env
SEPOLIA_RPC_URL="https://eth-sepolia.g.alchemy.com/v2/your-key"
PRIVATE_KEY="0xyour_private_key"
ETHERSCAN_API_KEY="your_etherscan_key"
```

##  Integration

### Basic Usage Flow

```solidity
// Import and initialize
import {DSCEngine} from "./src/DSCEngine.sol";

DSCEngine dsc = DSCEngine(0xa9B9Ae7bC2D242CE380137BEFA82a184747b2f3C);

// Deposit collateral and mint
dsc.depositCollateralAndMintDSC(
    0xdd13E55209Fd76AfE204dBda4007C227904f0a81, // WETH
    1 ether,    // Collateral
    500 ether   // Mint amount
);

// Monitor position
uint256 healthFactor = dsc.getHealthFactor(msg.sender);
require(healthFactor > 1e18, "Position at risk");
```

### Supported Collateral

| Asset | Contract Address | Oracle |
|-------|------------------|--------|
| **WETH** | `0xdd13E55209Fd76AfE204dBda4007C227904f0a81` | Chainlink ETH/USD |
| **WBTC** | `0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063` | Chainlink BTC/USD |

##  Protocol Parameters

```solidity
// Risk Management
uint256 private constant LIQUIDATION_THRESHOLD = 150; // 150%
uint256 private constant LIQUIDATION_BONUS = 5;       // 5% bonus
uint256 private constant MIN_HEALTH_FACTOR = 1e18;    // 1.0 threshold

// Precision
uint256 private constant PRECISION = 1e18;
uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
```

##  Testing & Security

### Comprehensive Test Suite

```bash
# Run specific test profiles
forge test --match-test "testDepositCollateral"    # Unit tests
forge test --match-test "testLiquidation"          # Integration tests
forge test --match-contract "Invariant"            # System properties

# With gas optimization reports
forge test --gas-report

# Fuzz testing
forge test --fuzz-runs 10000
```

### Security Features

- ✅ **Reentrancy Protection** - OpenZeppelin NonReentrant
- ✅ **Formal Verification** - Mathematical proof of solvency
- ✅ **Fuzz Testing** - Property-based testing with Foundry
- ✅ **CEI Pattern** - Checks-Effects-Interactions enforcement
- ✅ **Oracle Security** - Stale price feed validation
- ✅ **Input Validation** - Comprehensive sanitization

##  Deployment

### Foundry Deployment

```bash
# Deploy to Sepolia
forge script script/DeployDSC.s.sol:DeployDSC \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv
```

### Production Networks

- **Ethereum Mainnet** - Production ready
- **Polygon PoS** - Low-cost deployment available
- **Arbitrum One** - L2 optimized version
- **Optimism** - Scalable deployment

##  API Reference

### Core Functions

| Function | Description | Access |
|----------|-------------|--------|
| `depositCollateral(address,uint256)` | Deposit collateral assets | External |
| `redeemCollateral(address,uint256)` | Withdraw collateral | External |
| `mintDSC(uint256)` | Mint stablecoins | External |
| `burnDSC(uint256)` | Burn stablecoins | External |
| `liquidate(address,address,uint256)` | Liquidate undercollateralized positions | External |

### View Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `getHealthFactor(address)` | `uint256` | Position health score |
| `getAccountCollateralValue(address)` | `uint256` | Total collateral value |
| `getCollateralTokens()` | `address[]` | Supported assets |
| `getUsdValue(address,uint256)` | `uint256` | Asset valuation |

##  Enterprise Features

| Feature | Description | Status |
|---------|-------------|--------|
| **Multi-Sig Ready** | Gnosis Safe compatibility |  Production |
| **Upgrade Patterns** | Transparent proxy support |  Available |
| **Risk Monitoring** | Real-time dashboard hooks |  In Development |
| **Compliance** | Transaction tracing |  Production |

##  Contributing

We welcome technical contributions and strategic partnerships. For enterprise integration support, contact our engineering team.

### Development Workflow

```bash
# Fork and clone
git clone https://github.com/trustauto/dsc-protocol.git

# Create feature branch
git checkout -b feature/enhancement

# Test changes
forge test -vv

# Submit pull request
git push origin feature/enhancement
```

##  License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Built with precision by TrustAuto Engineering**  
*Professional DeFi infrastructure for institutional applications*

*For enterprise integration: engineering@cableGraph.com*
