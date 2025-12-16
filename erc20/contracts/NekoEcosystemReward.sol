// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/INekoReferralCode.sol";

/**
 * @title NekoEcosystemReward
 * @dev Centralized reward system for ecosystem activities
 * @notice Manages referral rewards and other ecosystem rewards (NOT staking - handled by NekoStaking)
 */
contract NekoEcosystemReward is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    // NEKO Token contract
    IERC20 public nekoToken;

    // Referral code contract
    address public referralCodeContract;

    // Authorized contracts that can call addReferralRewardByCode
    mapping(address => bool) public authorizedCallers;

    // Referral reward percentage (in basis points, e.g., 500 = 5%)
    uint256 public referralRewardPercentage = 500;

    // Mapping from user to referral rewards
    mapping(address => uint256) public referralRewards;

    // Mapping from user to other ecosystem rewards
    mapping(address => uint256) public ecosystemRewards;

    // Total rewards distributed
    uint256 public totalReferralRewards;
    uint256 public totalEcosystemRewards;

    // Reward pools
    uint256 public referralRewardPool;
    uint256 public ecosystemRewardPool;

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
    event AuthorizedCallerUpdated(address indexed caller, bool authorized);
    event PoolTransfer(address indexed to, uint256 amount, string reason, uint256 timestamp);

    // ============ Errors ============

    error InsufficientRewardPool(string poolType);
    error InvalidAddress();
    error InvalidAmount();
    error NoRewardsToClaim();
    error ReferralCodeContractNotSet();
    error InvalidReferralCode();
    error CannotReferSelf();
    error UnauthorizedCaller();
    error InsufficientPoolBalance();

    // ============ Constructor ============

    constructor(address _nekoToken) Ownable(msg.sender) {
        require(_nekoToken != address(0), "Invalid token address");
        nekoToken = IERC20(_nekoToken);
    }

    // ============ Referral Functions ============

    /**
     * @dev Add referral reward for a referrer
     * @param referrer The referrer address
     * @param buyer The buyer address
     * @param tokenAmount The amount of tokens bought
     */
    function addReferralReward(
        address referrer,
        address buyer,
        uint256 tokenAmount
    ) external onlyOwner nonReentrant whenNotPaused {
        require(referrer != address(0), "Invalid referrer");
        require(buyer != address(0), "Invalid buyer");
        require(tokenAmount > 0, "Invalid amount");
        require(referrer != buyer, "Cannot refer self");

        uint256 reward = (tokenAmount * referralRewardPercentage) / 10000;

        // Note: referralRewardPool is for tracking only, not a hard limit
        // Rewards are paid from contract's token balance when claimed
        // Pool check removed to allow rewards without pre-funding

        referralRewards[referrer] += reward;
        // Don't subtract from pool - pools are just for tracking
        // referralRewardPool -= reward;
        totalReferralRewards += reward;

        emit ReferralRewardAdded(referrer, buyer, reward, block.timestamp);
    }

    /**
     * @dev Add referral reward using referral code
     * @param referralCode The referral code
     * @param buyer The buyer address
     * @param tokenAmount The amount of tokens bought
     * @notice Can be called by owner or authorized contracts (like ICO)
     */
    function addReferralRewardByCode(
        string memory referralCode,
        address buyer,
        uint256 tokenAmount
    ) external nonReentrant whenNotPaused {
        require(
            msg.sender == owner() || authorizedCallers[msg.sender],
            "Unauthorized caller"
        );
        require(
            referralCodeContract != address(0),
            "Referral code contract not set"
        );
        require(buyer != address(0), "Invalid buyer");
        require(tokenAmount > 0, "Invalid amount");

        // Get referrer from referral code contract
        address referrer = _getReferrerFromCode(referralCode);
        require(referrer != address(0), "Invalid referral code");
        require(referrer != buyer, "Cannot refer self");

        uint256 reward = (tokenAmount * referralRewardPercentage) / 10000;

        // Note: referralRewardPool is for tracking only, not a hard limit
        // Rewards are paid from contract's token balance when claimed
        // Pool check removed to allow rewards without pre-funding

        referralRewards[referrer] += reward;
        // Don't subtract from pool - pools are just for tracking
        // referralRewardPool -= reward;
        totalReferralRewards += reward;

        emit ReferralRewardAdded(referrer, buyer, reward, block.timestamp);
    }

    // ============ Ecosystem Functions ============

    /**
     * @dev Add ecosystem reward for any activity
     * @param user The user address
     * @param amount The reward amount
     * @param reason The reason for the reward
     */
    function addEcosystemReward(
        address user,
        uint256 amount,
        string memory reason
    ) external nonReentrant whenNotPaused {
        // Allow owner or authorized callers (like NekoActivityReward)
        require(
            msg.sender == owner() || authorizedCallers[msg.sender],
            "Unauthorized caller"
        );
        require(user != address(0), "Invalid user");
        require(amount > 0, "Invalid amount");

        ecosystemRewards[user] += amount;
        totalEcosystemRewards += amount;

        emit EcosystemRewardAdded(user, amount, reason, block.timestamp);
    }

    /**
     * @dev Transfer NEKO tokens directly from ecosystem pool to user
     * @notice Only authorized callers (like NekoActivityReward) can call this
     * @param to Recipient address
     * @param amount Amount to transfer
     * @param reason Reason for transfer
     */
    function transferFromPool(
        address to,
        uint256 amount,
        string memory reason
    ) external nonReentrant whenNotPaused {
        // Allow owner or authorized callers
        require(
            msg.sender == owner() || authorizedCallers[msg.sender],
            "Unauthorized caller"
        );
        require(to != address(0), "Invalid address");
        require(amount > 0, "Invalid amount");
        require(ecosystemRewardPool >= amount, "Insufficient pool balance");

        // Deduct from pool
        ecosystemRewardPool -= amount;

        // Transfer tokens directly to user
        nekoToken.safeTransfer(to, amount);

        emit PoolTransfer(to, amount, reason, block.timestamp);
    }

    // ============ Claim Functions ============

    /**
     * @dev Claim all rewards for the caller
     */
    function claimAllRewards() external nonReentrant whenNotPaused {
        uint256 referralAmount = referralRewards[msg.sender];
        uint256 ecosystemAmount = ecosystemRewards[msg.sender];

        uint256 totalAmount = referralAmount + ecosystemAmount;

        if (totalAmount == 0) {
            revert NoRewardsToClaim();
        }

        // Reset rewards
        referralRewards[msg.sender] = 0;
        ecosystemRewards[msg.sender] = 0;

        // Transfer tokens
        nekoToken.safeTransfer(msg.sender, totalAmount);

        emit RewardsClaimed(
            msg.sender,
            referralAmount,
            ecosystemAmount,
            totalAmount,
            block.timestamp
        );
    }

    /**
     * @dev Claim specific type of rewards
     * @param rewardType The type of reward to claim (0: referral, 1: ecosystem)
     */
    function claimRewards(
        uint8 rewardType
    ) external nonReentrant whenNotPaused {
        uint256 amount = 0;

        if (rewardType == 0) {
            amount = referralRewards[msg.sender];
            referralRewards[msg.sender] = 0;
        } else if (rewardType == 1) {
            amount = ecosystemRewards[msg.sender];
            ecosystemRewards[msg.sender] = 0;
        } else {
            revert("Invalid reward type");
        }

        if (amount == 0) {
            revert NoRewardsToClaim();
        }

        nekoToken.safeTransfer(msg.sender, amount);

        emit RewardsClaimed(
            msg.sender,
            rewardType == 0 ? amount : 0,
            rewardType == 1 ? amount : 0,
            amount,
            block.timestamp
        );
    }

    // ============ View Functions ============

    /**
     * @dev Get total rewards for a user
     * @param user The user address
     * @return Total rewards available
     */
    function getTotalRewards(address user) external view returns (uint256) {
        return referralRewards[user] + ecosystemRewards[user];
    }

    /**
     * @dev Get referral rewards for a user
     * @param user The user address
     * @return Referral rewards available
     */
    function getReferralRewards(address user) external view returns (uint256) {
        return referralRewards[user];
    }

    /**
     * @dev Get ecosystem rewards for a user
     * @param user The user address
     * @return Ecosystem rewards available
     */
    function getEcosystemRewards(address user) external view returns (uint256) {
        return ecosystemRewards[user];
    }

    /**
     * @dev Get reward pool balances
     * @return referralPool Referral reward pool balance
     * @return ecosystemPool Ecosystem reward pool balance
     */
    function getRewardPoolBalances()
        external
        view
        returns (uint256 referralPool, uint256 ecosystemPool)
    {
        return (referralRewardPool, ecosystemRewardPool);
    }

    // ============ Admin Functions ============

    /**
     * @dev Fund reward pools
     * @param referralAmount Amount for referral pool
     * @param ecosystemAmount Amount for ecosystem pool
     */
    function fundRewardPools(
        uint256 referralAmount,
        uint256 ecosystemAmount
    ) external onlyOwner nonReentrant {
        uint256 totalAmount = referralAmount + ecosystemAmount;

        if (totalAmount > 0) {
            nekoToken.safeTransferFrom(msg.sender, address(this), totalAmount);

            referralRewardPool += referralAmount;
            ecosystemRewardPool += ecosystemAmount;

            emit RewardPoolFunded("all", totalAmount, block.timestamp);
        }
    }

    /**
     * @dev Set referral reward percentage
     * @param newPercentage New percentage in basis points
     */
    function setReferralRewardPercentage(
        uint256 newPercentage
    ) external onlyOwner {
        require(newPercentage <= 2000, "Percentage too high"); // Max 20%

        uint256 oldPercentage = referralRewardPercentage;
        referralRewardPercentage = newPercentage;

        emit ReferralRewardPercentageUpdated(oldPercentage, newPercentage);
    }

    /**
     * @dev Set referral code contract address
     * @param _referralCodeContract The referral code contract address
     */
    function setReferralCodeContract(
        address _referralCodeContract
    ) external onlyOwner {
        require(_referralCodeContract != address(0), "Invalid address");
        referralCodeContract = _referralCodeContract;
        emit ReferralCodeContractUpdated(_referralCodeContract);
    }

    /**
     * @dev Set authorized caller (e.g., ICO contract)
     * @param caller The contract address to authorize
     * @param authorized Whether to authorize or revoke
     */
    function setAuthorizedCaller(
        address caller,
        bool authorized
    ) external onlyOwner {
        require(caller != address(0), "Invalid address");
        authorizedCallers[caller] = authorized;
        emit AuthorizedCallerUpdated(caller, authorized);
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Emergency withdraw tokens
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Invalid amount");
        nekoToken.safeTransfer(msg.sender, amount);
    }

    // ============ Internal Functions ============

    /**
     * @dev Get referrer address from referral code
     * @param referralCode The referral code
     * @return The referrer address
     */
    function _getReferrerFromCode(
        string memory referralCode
    ) internal view returns (address) {
        require(
            referralCodeContract != address(0),
            "Referral code contract not set"
        );
        return
            INekoReferralCode(referralCodeContract).getAddressFromCode(
                referralCode
            );
    }
}
