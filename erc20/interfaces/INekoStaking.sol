// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title INekoStaking
 * @dev Interface for NEKO Staking Contract
 */
interface INekoStaking {
    // =============================================================================
    // STRUCTS
    // =============================================================================
    struct StakingPool {
        string name;
        uint256 duration;
        uint256 rewardRate;
        uint256 minStakeAmount;
        uint256 maxStakeAmount;
        uint256 poolCap;
        uint256 totalStaked;
        uint256 totalRewardsPaid;
        bool isActive;
        bool allowEarlyUnstaking;
        uint256 earlyUnstakingPenalty;
        uint256 compoundBonus;
    }

    struct UserStake {
        uint256 amount;
        uint256 poolId;
        uint256 startTime;
        uint256 lastClaimTime;
        uint256 accumulatedRewards;
        bool isActive;
        bool isCompounding;
        address referrer;
    }

    struct UserInfo {
        uint256 totalStaked;
        uint256 totalRewardsClaimed;
        uint256 activeStakesCount;
        uint256 referralRewards;
    }

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
        uint256 stakeIndex,
        address referrer
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
    event RewardsCompounded(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount,
        uint256 stakeIndex
    );
    event ReferralRewarded(
        address indexed referrer,
        address indexed referee,
        uint256 amount
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
        uint256 earlyUnstakingPenalty,
        uint256 compoundBonus
    ) external;

    function updatePool(
        uint256 poolId,
        uint256 rewardRate,
        uint256 minStakeAmount,
        uint256 maxStakeAmount,
        uint256 poolCap,
        bool isActive,
        bool allowEarlyUnstaking,
        uint256 earlyUnstakingPenalty,
        uint256 compoundBonus
    ) external;

    // =============================================================================
    // STAKING FUNCTIONS
    // =============================================================================
    function stake(
        uint256 poolId,
        uint256 amount,
        bool autoCompound,
        address referrer
    ) external;

    function unstake(uint256 stakeIndex) external;
    function claimRewards(uint256 stakeIndex) external;
    function claimAllRewards() external;

    // =============================================================================
    // EMERGENCY FUNCTIONS
    // =============================================================================
    function emergencyUnstakeAll() external;

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================
    function calculateRewards(
        address user,
        uint256 stakeIndex
    ) external view returns (uint256);
    function getUserTotalRewards(address user) external view returns (uint256);
    function getUserTotalStakedInPool(
        address user,
        uint256 poolId
    ) external view returns (uint256);
    function getUserStakes(
        address user
    ) external view returns (UserStake[] memory);
    function getUserActiveStakes(
        address user
    ) external view returns (UserStake[] memory);
    function getPoolInfo(
        uint256 poolId
    ) external view returns (StakingPool memory);
    function getAllPools() external view returns (StakingPool[] memory);
    function getActivePools() external view returns (StakingPool[] memory);

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================
    function setReferralRewardRate(uint256 newRate) external;
    function setMaxStakesPerUser(uint256 newMax) external;
    function setStakingEnabled(bool enabled) external;
    function setEmergencyMode(bool enabled) external;
    function pause() external;
    function unpause() external;
    function emergencyWithdraw(address token, uint256 amount) external;

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================
    function nekoToken() external view returns (address);
    function rewardTreasury() external view returns (address);
    function totalPoolsCount() external view returns (uint256);
    function totalStakersCount() external view returns (uint256);
    function totalStakedAmount() external view returns (uint256);
    function totalRewardsPaid() external view returns (uint256);
    function referralRewardRate() external view returns (uint256);
    function maxStakesPerUser() external view returns (uint256);
    function stakingEnabled() external view returns (bool);
    function emergencyMode() external view returns (bool);
    function userInfo(address user) external view returns (UserInfo memory);
    function referrers(address user) external view returns (address);
    function referralCounts(address referrer) external view returns (uint256);
}
