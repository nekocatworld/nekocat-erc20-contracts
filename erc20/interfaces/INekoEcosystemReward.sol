// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title INekoEcosystemReward
 * @dev Interface for NekoEcosystemReward contract
 * @notice Manages referral rewards and other ecosystem rewards (NOT staking - handled by NekoStaking)
 */
interface INekoEcosystemReward {
    // ============ Events ============
    event ReferralRewardAdded(
        address indexed referrer,
        address indexed buyer,
        uint256 amount,
        uint256 timestamp
    );

    event EcosystemRewardAdded(
        address indexed user,
        uint256 amount,
        string reason,
        uint256 timestamp
    );

    event RewardsClaimed(
        address indexed user,
        uint256 referralAmount,
        uint256 ecosystemAmount,
        uint256 totalAmount,
        uint256 timestamp
    );

    event RewardPoolFunded(string poolType, uint256 amount, uint256 timestamp);

    event ReferralRewardPercentageUpdated(
        uint256 oldPercentage,
        uint256 newPercentage
    );

    event ReferralCodeContractUpdated(address indexed contractAddress);

    // ============ Errors ============
    error InsufficientRewardPool(string poolType);
    error InvalidAddress();
    error InvalidAmount();
    error NoRewardsToClaim();
    error ReferralCodeContractNotSet();
    error InvalidReferralCode();
    error CannotReferSelf();

    // ============ Referral Functions ============
    function addReferralReward(
        address referrer,
        address buyer,
        uint256 tokenAmount
    ) external;

    function addReferralRewardByCode(
        string memory referralCode,
        address buyer,
        uint256 tokenAmount
    ) external;

    // ============ Ecosystem Functions ============
    function addEcosystemReward(
        address user,
        uint256 amount,
        string memory reason
    ) external;

    function transferFromPool(
        address to,
        uint256 amount,
        string memory reason
    ) external;

    // ============ Claim Functions ============
    function claimAllRewards() external;
    function claimRewards(uint8 rewardType) external;

    // ============ View Functions ============
    function getTotalRewards(address user) external view returns (uint256);
    function getReferralRewards(address user) external view returns (uint256);
    function getEcosystemRewards(address user) external view returns (uint256);
    function getRewardPoolBalances()
        external
        view
        returns (uint256 referralPool, uint256 ecosystemPool);

    // ============ Admin Functions ============
    function fundRewardPools(
        uint256 referralAmount,
        uint256 ecosystemAmount
    ) external;

    function setReferralRewardPercentage(uint256 newPercentage) external;
    function setReferralCodeContract(address _referralCodeContract) external;
    function pause() external;
    function unpause() external;
    function emergencyWithdraw(uint256 amount) external;

    // ============ State Variables ============
    function nekoToken() external view returns (address);
    function referralCodeContract() external view returns (address);
    function referralRewardPercentage() external view returns (uint256);
    function referralRewards(address user) external view returns (uint256);
    function ecosystemRewards(address user) external view returns (uint256);
    function totalReferralRewards() external view returns (uint256);
    function totalEcosystemRewards() external view returns (uint256);
    function referralRewardPool() external view returns (uint256);
    function ecosystemRewardPool() external view returns (uint256);
}
