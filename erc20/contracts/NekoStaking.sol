// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../lib/NekoCoinConstants.sol";
import "../interfaces/INekoStaking.sol";
import "../lib/NekoCoinErrors.sol";

interface INekoCatNFT {
    function syncImmortality(address user) external;
}

/**
 * @title NekoStaking
 * @dev Comprehensive NEKO Token Staking Contract with flexible reward pools and dynamic admin controls
 *
 * Features:
 * - Multiple staking pools with different durations and rewards
 * - Dynamic reward rate management by admin
 * - Flexible staking periods (30 days, 90 days, 180 days, 365 days)
 * - Early unstaking with penalties
 * - Emergency pause and recovery
 * - Tiered rewards based on staking amount
 * - Lock periods with higher rewards
 *
 * Security:
 * - ReentrancyGuard on all staking/unstaking functions
 * - Pausable for emergency stops
 * - SafeERC20 for token transfers
 * - Input validation on all parameters
 * - Access control for admin functions
 * - Overflow protection with Solidity 0.8+
 */
contract NekoStaking is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // =============================================================================
    // CUSTOM ERRORS
    // =============================================================================
    error InvalidAddress();
    error InvalidAmount();
    error InvalidDuration();
    error InvalidPoolId();
    error InsufficientBalance();
    error StakingNotFound();
    error StakingLocked();
    error PoolNotActive();
    error BelowMinStake();
    error AboveMaxStake();
    error NoRewardsToClaim();
    error InvalidRewardRate();
    error PoolCapExceeded();
    error EarlyUnstakingNotAllowed();

    // =============================================================================
    // STRUCTS
    // =============================================================================
    struct StakingPool {
        string name; // Pool name (e.g., "30 Days", "90 Days")
        uint256 duration; // Staking duration in seconds
        uint256 rewardRate; // Annual reward rate in basis points (e.g., 1000 = 10%)
        uint256 minStakeAmount; // Minimum stake amount
        uint256 maxStakeAmount; // Maximum stake amount per user
        uint256 poolCap; // Maximum total staked in this pool (0 = unlimited)
        uint256 totalStaked; // Current total staked in this pool
        uint256 totalRewardsPaid; // Total rewards paid from this pool
        bool isActive; // Pool active status
        bool allowEarlyUnstaking; // Allow early unstaking with penalty
        uint256 earlyUnstakingPenalty; // Penalty rate in basis points (e.g., 500 = 5%)
    }

    struct UserStake {
        uint256 amount; // Staked amount
        uint256 poolId; // Pool ID
        uint256 startTime; // Staking start timestamp
        uint256 lastClaimTime; // Last reward claim timestamp
        uint256 accumulatedRewards; // Accumulated unclaimed rewards
        bool isActive; // Stake active status
    }

    struct UserInfo {
        uint256 totalStaked; // Total amount staked by user across all pools
        uint256 totalRewardsClaimed; // Total rewards claimed by user
        uint256 activeStakesCount; // Number of active stakes
    }

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================
    IERC20 public immutable nekoToken;
    // Staking contract manages its own rewards - no treasury needed

    uint256 public totalPoolsCount; // Total number of pools
    uint256 public totalStakersCount; // Total unique stakers
    uint256 public totalStakedAmount; // Total staked across all pools
    uint256 public totalRewardsPaid; // Total rewards distributed

    // Security constants
    uint256 private constant TIMESTAMP_TOLERANCE = 15 minutes; // Protection against miner manipulation

    // Pool management
    mapping(uint256 => StakingPool) public stakingPools;

    // User management (optimized for gas)
    mapping(address => UserInfo) public userInfo;
    mapping(address => uint256) public userStakesCount; // user => number of stakes
    mapping(address => mapping(uint256 => UserStake)) public userStakes; // user => stakeIndex => stake
    mapping(address => mapping(uint256 => uint256)) public userPoolStakes; // user => poolId => stake count

    // Admin controls
    uint256 public maxStakesPerUser = 50; // Maximum stakes per user
    bool public stakingEnabled = true; // Global staking enable/disable
    bool public emergencyMode = false; // Emergency mode for immediate unstaking

    // NFT Immortality
    uint256 public immortalityThreshold = 2_000_000 * 10 ** 18; // 2M NEKO (admin updatable)
    address public nftContract; // NekoCat NFT contract address

    // =============================================================================
    // EVENTS
    // =============================================================================
    event PoolCreated(
        uint256 indexed poolId,
        string name,
        uint256 duration,
        uint256 rewardRate
    );
    event PoolUpdated(
        uint256 indexed poolId,
        uint256 rewardRate,
        bool isActive
    );
    event Staked(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount,
        uint256 stakeIndex
    );
    event Unstaked(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount,
        uint256 stakeIndex,
        uint256 rewards,
        uint256 penalty
    );
    event RewardsClaimed(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount,
        uint256 stakeIndex
    );
    event EmergencyUnstaked(
        address indexed user,
        uint256 totalAmount,
        uint256 stakesCount
    );
    event RewardTreasuryUpdated(
        address indexed oldTreasury,
        address indexed newTreasury
    );
    event ImmortalityStatusChanged(
        address indexed user,
        bool hasImmortality,
        uint256 totalStaked
    );
    event ImmortalitySyncFailed(address indexed user);
    event NFTContractUpdated(
        address indexed oldContract,
        address indexed newContract
    );

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================
    constructor(
        address _nekoToken,
        address initialOwner
    ) Ownable(initialOwner) {
        if (_nekoToken == address(0)) revert InvalidAddress();
        if (initialOwner == address(0)) revert InvalidAddress();

        nekoToken = IERC20(_nekoToken);

        // Create default staking pools
        _createDefaultPools();
    }

    // =============================================================================
    // POOL MANAGEMENT
    // =============================================================================
    function createPool(
        string memory name,
        uint256 duration,
        uint256 rewardRate,
        uint256 minStakeAmount,
        uint256 maxStakeAmount,
        uint256 poolCap,
        bool allowEarlyUnstaking,
        uint256 earlyUnstakingPenalty
    ) external onlyOwner {
        if (duration == 0) revert InvalidDuration();
        if (rewardRate == 0 || rewardRate > 50000) revert InvalidRewardRate(); // Max 500% APY
        if (minStakeAmount == 0) revert InvalidAmount();
        if (maxStakeAmount < minStakeAmount) revert InvalidAmount();
        if (earlyUnstakingPenalty > 5000) revert InvalidAmount(); // Max 50% penalty

        uint256 poolId = totalPoolsCount;

        stakingPools[poolId] = StakingPool({
            name: name,
            duration: duration,
            rewardRate: rewardRate,
            minStakeAmount: minStakeAmount,
            maxStakeAmount: maxStakeAmount,
            poolCap: poolCap,
            totalStaked: 0,
            totalRewardsPaid: 0,
            isActive: true,
            allowEarlyUnstaking: allowEarlyUnstaking,
            earlyUnstakingPenalty: earlyUnstakingPenalty
        });

        totalPoolsCount++;

        emit PoolCreated(poolId, name, duration, rewardRate);
    }

    function updatePool(
        uint256 poolId,
        uint256 rewardRate,
        uint256 minStakeAmount,
        uint256 maxStakeAmount,
        uint256 poolCap,
        bool isActive,
        bool allowEarlyUnstaking,
        uint256 earlyUnstakingPenalty
    ) external onlyOwner {
        if (poolId >= totalPoolsCount) revert InvalidPoolId();
        if (rewardRate > 50000) revert InvalidRewardRate();
        if (earlyUnstakingPenalty > 5000) revert InvalidAmount();

        StakingPool storage pool = stakingPools[poolId];
        pool.rewardRate = rewardRate;
        pool.minStakeAmount = minStakeAmount;
        pool.maxStakeAmount = maxStakeAmount;
        pool.poolCap = poolCap;
        pool.isActive = isActive;
        pool.allowEarlyUnstaking = allowEarlyUnstaking;
        pool.earlyUnstakingPenalty = earlyUnstakingPenalty;

        emit PoolUpdated(poolId, rewardRate, isActive);
    }

    // =============================================================================
    // STAKING FUNCTIONS
    // =============================================================================
    function stake(
        uint256 poolId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        if (!stakingEnabled) revert PoolNotActive();
        if (poolId >= totalPoolsCount) revert InvalidPoolId();
        if (amount == 0) revert InvalidAmount();
        if (userStakesCount[msg.sender] >= maxStakesPerUser)
            revert AboveMaxStake();

        StakingPool storage pool = stakingPools[poolId];
        if (!pool.isActive) revert PoolNotActive();
        if (amount < pool.minStakeAmount) revert BelowMinStake();
        if (amount > pool.maxStakeAmount) revert AboveMaxStake();

        // Check pool capacity
        if (pool.poolCap > 0 && pool.totalStaked + amount > pool.poolCap) {
            revert PoolCapExceeded();
        }

        // Check user's total stake in this pool
        uint256 userPoolTotal = getUserTotalStakedInPool(msg.sender, poolId);
        if (userPoolTotal + amount > pool.maxStakeAmount)
            revert AboveMaxStake();

        // Transfer tokens
        nekoToken.safeTransferFrom(msg.sender, address(this), amount);

        // Create stake
        uint256 stakeIndex = userStakesCount[msg.sender];
        userStakes[msg.sender][stakeIndex] = UserStake({
            amount: amount,
            poolId: poolId,
            startTime: block.timestamp,
            lastClaimTime: block.timestamp,
            accumulatedRewards: 0,
            isActive: true
        });
        userStakesCount[msg.sender]++;

        // Update pool and user info
        pool.totalStaked += amount;
        userPoolStakes[msg.sender][poolId]++;

        UserInfo storage user = userInfo[msg.sender];
        if (user.totalStaked == 0) {
            totalStakersCount++;
        }
        user.totalStaked += amount;
        user.activeStakesCount++;

        totalStakedAmount += amount;

        emit Staked(msg.sender, poolId, amount, stakeIndex);

        // Check and emit immortality status change
        checkImmortalityStatus(msg.sender);

        // Sync immortality in NFT contract (grant immortality if stake increased above threshold)
        // Use try-catch to prevent stake failure if NFT contract has issues
        if (nftContract != address(0)) {
            try INekoCatNFT(nftContract).syncImmortality(msg.sender) {
                // Success - immortality synced
            } catch {
                // Log error but don't revert stake transaction
                // This ensures users can always stake even if NFT contract has issues
                emit ImmortalitySyncFailed(msg.sender);
            }
        }
    }

    function unstake(uint256 stakeIndex) external nonReentrant {
        if (stakeIndex >= userStakesCount[msg.sender]) revert StakingNotFound();

        UserStake storage userStake = userStakes[msg.sender][stakeIndex];
        if (!userStake.isActive) revert StakingNotFound();

        StakingPool storage pool = stakingPools[userStake.poolId];

        uint256 stakedAmount = userStake.amount;
        uint256 rewards = calculateRewards(msg.sender, stakeIndex);
        uint256 penalty = 0;

        // Add timestamp tolerance to prevent miner manipulation
        bool isEarlyUnstaking = block.timestamp + TIMESTAMP_TOLERANCE <
            userStake.startTime + pool.duration;

        // Check if early unstaking is allowed
        if (isEarlyUnstaking && !pool.allowEarlyUnstaking && !emergencyMode) {
            revert EarlyUnstakingNotAllowed();
        }

        // Calculate penalty for early unstaking
        if (isEarlyUnstaking && !emergencyMode) {
            penalty =
                (stakedAmount * pool.earlyUnstakingPenalty) /
                NekoCoinConstants.BASIS_POINTS;
        }

        // Update stake status
        userStake.isActive = false;
        userStake.accumulatedRewards += rewards;

        // Update pool and user info
        pool.totalStaked -= stakedAmount;
        pool.totalRewardsPaid += rewards;

        UserInfo storage user = userInfo[msg.sender];
        user.totalStaked -= stakedAmount;
        user.activeStakesCount--;
        user.totalRewardsClaimed += rewards;

        totalStakedAmount -= stakedAmount;
        totalRewardsPaid += rewards;

        // Transfer tokens back to user (minus penalty)
        uint256 returnAmount = stakedAmount - penalty;
        if (returnAmount > 0) {
            nekoToken.safeTransfer(msg.sender, returnAmount);
        }

        // Transfer rewards if any
        if (rewards > 0) {
            nekoToken.safeTransfer(msg.sender, rewards);
        }

        // Send penalty to owner if any
        if (penalty > 0) {
            nekoToken.safeTransfer(owner(), penalty);
        }

        emit Unstaked(
            msg.sender,
            userStake.poolId,
            stakedAmount,
            stakeIndex,
            rewards,
            penalty
        );

        // Check and emit immortality status change
        checkImmortalityStatus(msg.sender);

        // Sync immortality in NFT contract (remove excess immortal NFTs if stake decreased)
        // Use try-catch to prevent unstake failure if NFT contract has issues
        if (nftContract != address(0)) {
            try INekoCatNFT(nftContract).syncImmortality(msg.sender) {
                // Success - immortality synced
            } catch {
                // Log error but don't revert unstake transaction
                // This ensures users can always unstake even if NFT contract has issues
                emit ImmortalitySyncFailed(msg.sender);
            }
        }
    }

    function claimRewards(uint256 stakeIndex) external nonReentrant {
        if (stakeIndex >= userStakesCount[msg.sender]) revert StakingNotFound();

        UserStake storage userStake = userStakes[msg.sender][stakeIndex];
        if (!userStake.isActive) revert StakingNotFound();

        uint256 rewards = calculateRewards(msg.sender, stakeIndex);
        if (rewards == 0) revert NoRewardsToClaim();

        // Update last claim time and accumulated rewards
        userStake.lastClaimTime = block.timestamp;
        userStake.accumulatedRewards += rewards;

        // Update pool and user info
        StakingPool storage pool = stakingPools[userStake.poolId];
        pool.totalRewardsPaid += rewards;

        userInfo[msg.sender].totalRewardsClaimed += rewards;
        totalRewardsPaid += rewards;

        // Transfer rewards to user
        nekoToken.safeTransfer(msg.sender, rewards);

        emit RewardsClaimed(msg.sender, userStake.poolId, rewards, stakeIndex);
    }

    function claimAllRewards() external nonReentrant {
        uint256 totalRewards = 0;
        uint256 stakesCount = userStakesCount[msg.sender];

        for (uint256 i = 0; i < stakesCount; i++) {
            UserStake storage userStake = userStakes[msg.sender][i];
            if (!userStake.isActive) continue;

            uint256 rewards = calculateRewards(msg.sender, i);
            if (rewards == 0) continue;

            totalRewards += rewards;

            // Update last claim time
            userStake.lastClaimTime = block.timestamp;
            userStake.accumulatedRewards += rewards;

            // Update pool info
            StakingPool storage pool = stakingPools[userStake.poolId];
            pool.totalRewardsPaid += rewards;

            emit RewardsClaimed(msg.sender, userStake.poolId, rewards, i);
        }

        if (totalRewards == 0) revert NoRewardsToClaim();

        // Update user info
        userInfo[msg.sender].totalRewardsClaimed += totalRewards;
        totalRewardsPaid += totalRewards;

        // Transfer all rewards to user
        nekoToken.safeTransfer(msg.sender, totalRewards);
    }

    // =============================================================================
    // EMERGENCY FUNCTIONS
    // =============================================================================
    function emergencyUnstakeAll() external nonReentrant {
        if (!emergencyMode) revert("Emergency mode not active");

        uint256 totalAmount = 0;
        uint256 activeStakes = 0;
        uint256 stakesCount = userStakesCount[msg.sender];

        for (uint256 i = 0; i < stakesCount; i++) {
            UserStake storage userStake = userStakes[msg.sender][i];
            if (!userStake.isActive) continue;

            uint256 stakedAmount = userStake.amount;
            uint256 rewards = calculateRewards(msg.sender, i);

            // Update stake status
            userStake.isActive = false;
            userStake.accumulatedRewards += rewards;

            // Update pool info
            StakingPool storage pool = stakingPools[userStake.poolId];
            pool.totalStaked -= stakedAmount;
            pool.totalRewardsPaid += rewards;

            totalAmount += stakedAmount + rewards;
            activeStakes++;
        }

        if (totalAmount == 0) revert InsufficientBalance();

        // Update user info
        UserInfo storage user = userInfo[msg.sender];
        user.totalStaked = 0;
        user.activeStakesCount = 0;
        user.totalRewardsClaimed += (totalAmount - user.totalStaked);

        // Update global stats
        totalStakedAmount -= user.totalStaked;

        // Transfer all tokens back to user
        nekoToken.safeTransfer(msg.sender, totalAmount);

        emit EmergencyUnstaked(msg.sender, totalAmount, activeStakes);

        // Check and emit immortality status change
        checkImmortalityStatus(msg.sender);

        // Sync immortality in NFT contract (remove excess immortal NFTs if stake decreased)
        // Use try-catch to prevent unstake failure if NFT contract has issues
        if (nftContract != address(0)) {
            try INekoCatNFT(nftContract).syncImmortality(msg.sender) {
                // Success - immortality synced
            } catch {
                // Log error but don't revert unstake transaction
                // This ensures users can always unstake even if NFT contract has issues
                emit ImmortalitySyncFailed(msg.sender);
            }
        }
    }

    // =============================================================================
    // NFT IMMORTALITY FUNCTIONS
    // =============================================================================
    /**
     * @dev Check if user has staked enough NEKO for NFT immortality (with custom threshold)
     * @param user Address to check
     * @param threshold Minimum stake amount required
     * @return bool True if user has staked >= threshold
     */
    function hasImmortalityStakeWithThreshold(
        address user,
        uint256 threshold
    ) external view returns (bool) {
        return userInfo[user].totalStaked >= threshold;
    }

    /**
     * @dev Check if user has valid immortality stake (amount + duration)
     * @param user Address to check
     * @param threshold Minimum stake amount required
     * @return bool True if user has valid stake for immortality
     */
    function hasValidImmortalityStake(
        address user,
        uint256 threshold
    ) external view returns (bool) {
        if (userInfo[user].totalStaked < threshold) {
            return false;
        }

        // Check if user has at least one active stake that meets the threshold
        uint256 stakesCount = userStakesCount[user];
        uint256 totalValidStake = 0;

        for (uint256 i = 0; i < stakesCount; i++) {
            UserStake memory userStake = userStakes[user][i];
            if (!userStake.isActive) continue;

            StakingPool memory pool = stakingPools[userStake.poolId];

            // Check if stake is still within duration (not expired)
            // Include timestamp tolerance for miner protection
            bool isWithinDuration = block.timestamp + TIMESTAMP_TOLERANCE <
                userStake.startTime + pool.duration;

            if (isWithinDuration) {
                totalValidStake += userStake.amount;
            }
        }

        return totalValidStake >= threshold;
    }

    /**
     * @dev Get user's valid staked amount (only active stakes within duration)
     * @param user Address to check
     * @return uint256 Total valid staked amount
     */
    function getValidStakedAmount(
        address user
    ) external view returns (uint256) {
        uint256 stakesCount = userStakesCount[user];
        uint256 totalValidStake = 0;

        for (uint256 i = 0; i < stakesCount; i++) {
            UserStake memory userStake = userStakes[user][i];
            if (!userStake.isActive) continue;

            StakingPool memory pool = stakingPools[userStake.poolId];

            // Check if stake is still within duration (not expired)
            // Include timestamp tolerance for miner protection
            bool isWithinDuration = block.timestamp + TIMESTAMP_TOLERANCE <
                userStake.startTime + pool.duration;

            if (isWithinDuration) {
                totalValidStake += userStake.amount;
            }
        }

        return totalValidStake;
    }

    /**
     * @dev Get user's total staked amount across all pools
     * @param user Address to check
     * @return uint256 Total staked amount
     */
    function getStakedAmount(address user) external view returns (uint256) {
        return userInfo[user].totalStaked;
    }

    /**
     * @dev Check immortality status and notify NFT contract if status changed
     * @param user Address to check
     */
    function checkImmortalityStatus(address user) public {
        bool hasImmortality = userInfo[user].totalStaked >=
            immortalityThreshold;
        emit ImmortalityStatusChanged(
            user,
            hasImmortality,
            userInfo[user].totalStaked
        );
    }

    /**
     * @dev Batch check immortality status for multiple users
     * @param users Array of addresses to check
     */
    function batchCheckImmortalityStatus(address[] calldata users) external {
        for (uint256 i = 0; i < users.length; i++) {
            checkImmortalityStatus(users[i]);
        }
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================
    function calculateRewards(
        address user,
        uint256 stakeIndex
    ) public view returns (uint256) {
        if (stakeIndex >= userStakesCount[user]) return 0;

        UserStake storage userStake = userStakes[user][stakeIndex];
        if (!userStake.isActive) return 0;

        StakingPool storage pool = stakingPools[userStake.poolId];

        uint256 stakingTime = block.timestamp - userStake.lastClaimTime;
        uint256 baseReward = (userStake.amount *
            pool.rewardRate *
            stakingTime) / (365 days * NekoCoinConstants.BASIS_POINTS);

        return baseReward;
    }

    function getUserTotalRewards(address user) external view returns (uint256) {
        uint256 totalRewards = 0;
        uint256 stakesCount = userStakesCount[user];

        for (uint256 i = 0; i < stakesCount; i++) {
            totalRewards += calculateRewards(user, i);
        }

        return totalRewards;
    }

    function getUserTotalStakedInPool(
        address user,
        uint256 poolId
    ) public view returns (uint256) {
        uint256 totalStaked = 0;
        uint256 userStakesTotal = userStakesCount[user];

        for (uint256 i = 0; i < userStakesTotal; i++) {
            UserStake storage userStake = userStakes[user][i];
            if (userStake.isActive && userStake.poolId == poolId) {
                totalStaked += userStake.amount;
            }
        }

        return totalStaked;
    }

    function getUserStakes(
        address user
    ) external view returns (UserStake[] memory) {
        uint256 stakesCount = userStakesCount[user];
        UserStake[] memory stakes = new UserStake[](stakesCount);

        for (uint256 i = 0; i < stakesCount; i++) {
            stakes[i] = userStakes[user][i];
        }

        return stakes;
    }

    function getUserActiveStakes(
        address user
    ) external view returns (UserStake[] memory) {
        uint256 activeCount = userInfo[user].activeStakesCount;
        UserStake[] memory activeStakes = new UserStake[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < userStakesCount[user]; i++) {
            if (userStakes[user][i].isActive) {
                activeStakes[index] = userStakes[user][i];
                index++;
            }
        }

        return activeStakes;
    }

    function getPoolInfo(
        uint256 poolId
    ) external view returns (StakingPool memory) {
        if (poolId >= totalPoolsCount) revert InvalidPoolId();
        return stakingPools[poolId];
    }

    function getAllPools() external view returns (StakingPool[] memory) {
        StakingPool[] memory pools = new StakingPool[](totalPoolsCount);
        for (uint256 i = 0; i < totalPoolsCount; i++) {
            pools[i] = stakingPools[i];
        }
        return pools;
    }

    function getActivePools() external view returns (StakingPool[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < totalPoolsCount; i++) {
            if (stakingPools[i].isActive) activeCount++;
        }

        StakingPool[] memory activePools = new StakingPool[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < totalPoolsCount; i++) {
            if (stakingPools[i].isActive) {
                activePools[index] = stakingPools[i];
                index++;
            }
        }

        return activePools;
    }

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================
    function setMaxStakesPerUser(uint256 newMax) external onlyOwner {
        if (newMax == 0 || newMax > 1000) revert InvalidAmount();
        maxStakesPerUser = newMax;
    }

    function setStakingEnabled(bool enabled) external onlyOwner {
        stakingEnabled = enabled;
    }

    function setEmergencyMode(bool enabled) external onlyOwner {
        emergencyMode = enabled;
    }

    function setNFTContract(address _nftContract) external onlyOwner {
        if (_nftContract == address(0)) revert InvalidAddress();

        address oldContract = nftContract;
        nftContract = _nftContract;

        emit NFTContractUpdated(oldContract, _nftContract);
    }

    function setImmortalityThreshold(uint256 newThreshold) external onlyOwner {
        if (newThreshold == 0) revert InvalidAmount();
        immortalityThreshold = newThreshold;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyOwner {
        if (token == address(0)) {
            (bool success, ) = owner().call{value: amount}("");
            if (!success) revert("Transfer failed");
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    // =============================================================================
    // INTERNAL FUNCTIONS
    // =============================================================================

    function _createDefaultPools() internal {
        // Single Staking Pool - 4% APY
        stakingPools[0] = StakingPool({
            name: "NEKO Staking Pool",
            duration: 60 days, // 60 days duration
            rewardRate: 400, // 4% APY
            minStakeAmount: 1000000 * 10 ** 18, // 1,000,000 NEKO (1M)
            maxStakeAmount: 100000000 * 10 ** 18, // 100,000,000 NEKO (100M)
            poolCap: 0, // Unlimited
            totalStaked: 0,
            totalRewardsPaid: 0,
            isActive: true,
            allowEarlyUnstaking: true,
            earlyUnstakingPenalty: 200 // 2% penalty for early unstaking
        });

        totalPoolsCount = 1;
    }

    // =============================================================================
    // RECEIVE FUNCTION
    // =============================================================================
    receive() external payable {
        revert("Direct ETH not accepted");
    }
}
