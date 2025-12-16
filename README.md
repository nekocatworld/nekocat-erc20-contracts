# NEKO Coin ERC20 Contracts

A comprehensive ERC20 token ecosystem for NEKO Coin with advanced security features, role-based access control, staking rewards, ICO mechanics, and gas optimization. Deployed on **Base Sepolia** (testnet) and **Soneium Mainnet**.

## 🌟 Overview

The NEKO Coin ecosystem consists of multiple interconnected smart contracts that provide:

- ERC20 token with transfer tax system
- Multi-stage ICO/Presale with referral rewards
- Flexible staking with multiple pools and durations
- Linear vesting with cliff periods
- Referral code system
- Ecosystem reward distribution
- Treasury management

## 📊 Contract Addresses

### Base Sepolia (Testnet)

- **NekoCoin**: `0x98662a4cAc11b4dffeCf8e2D96aE1Ba9eD529330`
- **NekoICO**: `0xC42f0ea546a82B66ED9b792304f6Ed3c16f5B685`
- **NekoVesting**: `0x9B81B974Ff999CdAB96c01088CBBE73837Ff2F18`
- **NekoStaking**: `0x941d9D0bf2F19fD5cBe799D8b4d7E4D5EAe7cb84`
- **NekoTreasuryERC20**: `0x78c810CD9C94A7d644ee75DfeDc329745Dbb7B1B`
- **NekoReferralCode**: `0xaF66073536cC4A84be8766f250a91e9321E90038`
- **NekoEcosystemReward**: `0x5a37c5E78AF28D2E80B60A7F684dB1408Ee4DA97`
- **NekoActivityReward**: `0xC68F69Ca97A5e073A2033e516f4332e10d971CdE`
- **NekoPriceManager**: `0xcC3Ced4285d8923F2C5a50fdE7a2668DbB89C93b`

### Block Explorer

- **Base Sepolia**: https://sepolia-explorer.base.org
- **Soneium Mainnet**: https://explorer.soneium.org

## 🏗️ Architecture

### Core Contracts

#### NekoCoin.sol

Main ERC20 token contract with transfer tax system.

**Features:**

- Full ERC20 standard compliance
- 3% transfer tax (configurable, max 10%)
- Role-based access control
- Pausable functionality
- Burnable tokens
- Batch operations
- Gas-optimized storage

**Key Functions:**

```solidity
function transfer(address to, uint256 amount) external returns (bool)
function approve(address spender, uint256 amount) external returns (bool)
function burn(uint256 amount) external
function mint(address to, uint256 amount) external
```

#### NekoICO.sol

Multi-stage ICO/Presale contract with referral rewards.

**Features:**

- Multiple stages with progressive pricing
- Referral code system integration
- Ecosystem reward distribution
- Treasury integration
- Vesting integration
- Whitelist support
- Pausable functionality

**Key Functions:**

```solidity
function buyWithETH() external payable
function buyWithETHByCode(string memory referralCode) external payable
function claimTokens() external
function getCurrentStageInfo() external view returns (StageInfo memory)
```

#### NekoStaking.sol

Flexible staking contract with multiple pools and durations.

**Features:**

- Multiple staking pools (30, 90, 180, 365 days)
- Configurable APY per pool (up to 25%)
- Minimum and maximum stake limits
- Pool capacity limits
- Reward calculation
- Immortality integration with NFT contract
- Emergency unstake functionality

**Key Functions:**

```solidity
function stake(uint256 poolId, uint256 amount) external
function unstake(uint256 stakeId) external
function claimRewards(uint256 stakeId) external
function claimAllRewards() external
function getUserActiveStakes(address user) external view returns (StakeInfo[] memory)
```

#### NekoVesting.sol

Linear vesting contract with cliff periods.

**Features:**

- Linear vesting schedule
- Configurable cliff periods
- Multiple vesting schedules per user
- Claimable amount calculation
- Pausable functionality

**Key Functions:**

```solidity
function createVestingSchedule(address beneficiary, uint256 amount, uint256 startTime, uint256 duration, uint256 cliff) external
function claim() external
function getClaimableAmount(address beneficiary) external view returns (uint256)
```

#### NekoReferralCode.sol

Referral code system for ICO participation.

**Features:**

- Unique referral code generation
- Code-to-address mapping
- Address-to-code mapping
- Code existence validation
- Code update functionality

**Key Functions:**

```solidity
function generateReferralCode() external returns (string memory)
function setReferralCode(string memory code) external
function getCodeFromAddress(address user) external view returns (string memory)
function getAddressFromCode(string memory code) external view returns (address)
```

#### NekoEcosystemReward.sol

Ecosystem reward distribution contract.

**Features:**

- Referral reward pool
- Ecosystem reward pool
- Authorized caller system
- Reward distribution
- Pool balance tracking

**Key Functions:**

```solidity
function addReferralReward(address referrer, uint256 amount) external
function addEcosystemReward(address recipient, uint256 amount) external
function claimAllRewards() external
function getTotalRewards(address user) external view returns (uint256)
```

#### NekoTreasuryERC20.sol

Treasury contract for ERC20 token management.

**Features:**

- Token balance management
- Withdrawal functionality
- Integration with ICO and staking contracts
- Multi-signature support (optional)

**Key Functions:**

```solidity
function withdrawFunds(address token, uint256 amount, address to) external
function getBalance(address token) external view returns (uint256)
```

### Roles

- **DEFAULT_ADMIN_ROLE**: Full administrative control
- **MINTER_ROLE**: Can mint new tokens
- **BURNER_ROLE**: Can burn tokens from any address
- **PAUSER_ROLE**: Can pause/unpause contracts
- **TAX_MANAGER_ROLE**: Can manage tax settings

## 🚀 Getting Started

### Prerequisites

- **Node.js** >= 18.0.0
- **npm** >= 8.0.0
- **Hardhat** >= 2.22.0
- **MetaMask** or compatible wallet

### Installation

```bash
# Install dependencies
npm install

# Copy environment template
cp env.example .env

# Edit .env with your configuration
```

### Environment Configuration

Edit the `.env` file:

```env
# Private keys
PRIVATE_KEY=your_private_key_here

# RPC endpoints
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
SONEIUM_MAINNET_RPC_URL=https://rpc.soneium.org

# API keys
ETHERSCAN_API_KEY=your_etherscan_api_key
BASESCAN_API_KEY=your_basescan_api_key

# Token configuration
TOKEN_NAME=NEKO Coin
TOKEN_SYMBOL=NEKO
TOTAL_SUPPLY=777777777777000000000000000000
```

## 📝 Usage

### Compilation

```bash
npm run compile
```

### Testing

```bash
# Run all tests
npm test

# Run tests with gas reporting
npm run test:gas

# Run coverage
npm run coverage
```

### Deployment

```bash
# Deploy to Base Sepolia testnet
npm run deploy:testnet

# Deploy to Soneium mainnet
npm run deploy:soneium

# Deploy to local network
npm run deploy:local
```

### Contract Linking

After deployment, link contracts together:

```bash
# Link ICO to referral system
npm run link:referral:testnet

# Link NFT contracts
npm run link:nft:testnet

# Verify all links
npm run verify:links:testnet
```

### Verification

```bash
# Verify on Base Sepolia
npm run verify:base

# Verify on Soneium
npm run verify:soneium
```

## 🔧 Hardhat Tasks

### Token Management

```bash
# Get token information
npx hardhat token-info --address <contract_address>

# Mint tokens
npx hardhat mint-tokens --address <contract_address> --to <address> --amount "1000"

# Burn tokens
npx hardhat burn-tokens --address <contract_address> --from <address> --amount "100"
```

### Tax Management

```bash
# Get tax information
npx hardhat tax:info --address <contract_address>

# Update tax rate (300 = 3%)
npx hardhat tax:update-rate --address <contract_address> --rate 300

# Update tax collector
npx hardhat tax:update-collector --address <contract_address> --collector <address>

# Toggle tax on/off
npx hardhat tax:toggle --address <contract_address> --enabled true

# Set all tax parameters
npx hardhat tax:set-params --address <contract_address> --rate 300 --collector <address> --enabled true

# Calculate tax for an amount
npx hardhat tax:calculate --address <contract_address> --amount 1000
```

### Role Management

```bash
# Grant role
npx hardhat grant-role --address <contract_address> --role MINTER_ROLE --account <address>

# Revoke role
npx hardhat revoke-role --address <contract_address> --role MINTER_ROLE --account <address>
```

### Contract Control

```bash
# Pause contract
npx hardhat pause-contract --address <contract_address> --action pause

# Unpause contract
npx hardhat pause-contract --address <contract_address> --action unpause
```

## 🔐 Security Features

### Core Security

- ✅ **OpenZeppelin v5.0.2** (latest stable)
- ✅ **ReentrancyGuard** on all state-changing functions
- ✅ **Pausable** for emergency stops
- ✅ **AccessControl** with role-based permissions
- ✅ **Safe Math** operations (Solidity 0.8.20+)
- ✅ **Custom Errors** for gas efficiency

### Input Validation

- ✅ All parameters validated before processing
- ✅ Array length checks and bounds validation
- ✅ Address zero checks
- ✅ Amount range validation
- ✅ Time-based validation

### Additional Protections

- ✅ **Batch size limits** to prevent DOS
- ✅ **Transaction limits** to prevent large transfers
- ✅ **Emergency functions** for critical situations
- ✅ **Modular design** for separation of concerns

## 💰 Token Economics

### NEKO Token

- **Total Supply**: 777,777,777,777 NEKO (777 billion)
- **Decimals**: 18
- **Transfer Tax**: 3% (configurable, max 10%)
- **Tax Collector**: Admin/deployer wallet

### Staking Rewards

- **Pool Durations**: 30, 90, 180, 365 days
- **APY**: Up to 25% (varies by pool)
- **Minimum Stake**: Configurable per pool
- **Maximum Stake**: Configurable per pool
- **Reward Token**: NEKO

### ICO Stages

- **Multi-stage pricing**: Progressive price increases
- **Referral Rewards**: Earn rewards for referrals
- **Vesting**: Purchased tokens are vested and claimable over time

## 🧪 Testing

The test suite covers:

- Contract deployment and initialization
- Token minting and burning
- Role management
- Pausable functionality
- Transfer restrictions
- Access control
- Reentrancy protection
- Interface support
- ICO mechanics
- Staking operations
- Vesting schedules
- Referral system

Run tests:

```bash
npm test
```

## 📊 Gas Optimization

### Optimizations Applied

- **Packed Storage**: Optimized storage layout
- **Immutable Variables**: Gas-efficient immutable references
- **Custom Errors**: More gas-efficient than require statements
- **Batch Operations**: Efficient batch minting and burning
- **Loop Optimization**: Minimized gas costs in loops
- **Compiler Optimization**: 200 runs enabled

## 🔗 Contract Interactions

### Integration Flow

```
NekoICO
  ├── NekoReferralCode (referral codes)
  ├── NekoEcosystemReward (reward distribution)
  ├── NekoTreasuryERC20 (fund management)
  └── NekoVesting (token vesting)

NekoStaking
  ├── NekoCoin (token staking)
  └── NekoCatNFT (immortality integration)

NekoEcosystemReward
  ├── NekoReferralCode (referral validation)
  └── NekoCoin (reward token)
```

## 📚 Documentation

- **[Root README](../../README.md)**: Project overview
- **[Frontend README](../../frontend/README.md)**: Frontend application
- **[NFT Contracts README](../nft/README.md)**: NFT contracts
- **[Contract Interactions Status](../../docs/CONTRACT_INTERACTIONS_STATUS.md)**: Contract interaction status

## 🚀 Deployment Checklist

1. ✅ Deploy NekoCoin
2. ✅ Deploy NekoReferralCode
3. ✅ Deploy NekoEcosystemReward
4. ✅ Deploy NekoTreasuryERC20
5. ✅ Deploy NekoVesting
6. ✅ Deploy NekoStaking
7. ✅ Deploy NekoICO
8. ✅ Link all contracts
9. ✅ Verify contracts on block explorer
10. ✅ Configure frontend with contract addresses
11. ✅ Test all interactions
12. ✅ Fund reward pools

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details.

## 🔗 Links

- **Website**: [nekocat.world](https://nekocat.world)
- **Block Explorer**: [Base Sepolia Explorer](https://sepolia-explorer.base.org)
- **Documentation**: [Project Docs](../../docs/)

## ⚠️ Disclaimer

This smart contract handles real value. Always:

- Test thoroughly on testnet first
- Audit the contract before mainnet deployment
- Use a hardware wallet for deployment
- Keep private keys secure
- Verify all addresses before deployment

---

by the NEKO Team
