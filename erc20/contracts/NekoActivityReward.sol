// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/INekoEcosystemReward.sol";

/**
 * @title NekoActivityReward
 * @dev On-chain reward system for Japanese cultural activities (Haiku, Onsen, Zen Garden)
 * @notice Manages paw (paw print) rewards for activities, similar to GMeow calendar system
 */
contract NekoActivityReward is Ownable, ReentrancyGuard, Pausable {
    // ============ State Variables ============

    // Paw (paw print) balances per user
    mapping(address => uint256) public pawBalance;

    // Total paw distributed
    uint256 public totalPawDistributed;

    // Activity types
    enum ActivityType {
        Haiku,
        Onsen,
        ZenGarden,
        GMeow
    }

    // Activity rewards (in paw)
    mapping(ActivityType => uint256) public activityRewards;

    // Daily limits per activity type
    mapping(ActivityType => uint256) public dailyLimits;

    // Daily activity count per user (user => activityType => day => count)
    // day = block.timestamp / 1 days
    mapping(address => mapping(ActivityType => mapping(uint256 => uint256))) public dailyActivityCount;

    // Haiku storage (user => haiku text)
    mapping(address => string[]) public userHaikus;

    // Zen Garden meditation count per user
    mapping(address => uint256) public zenGardenMeditationCount;

    // GMeow daily sign tracking
    mapping(address => mapping(uint256 => bool)) public gmeowSignedDates; // user => dayNumber => signed
    mapping(address => uint256) public gmeowFirstSignDate; // user => first sign timestamp
    mapping(address => uint256) public gmeowCurrentStreak; // user => current streak
    mapping(address => uint256) public gmeowTotalSigned; // user => total signed days
    mapping(address => uint256) public gmeowTotalPaw; // user => total paw from GMeow

    // GMeow surprise days (day number => bonus paw)
    mapping(uint256 => uint256) public gmeowSurpriseDays;

    // Ecosystem Reward contract for claiming NEKO tokens
    INekoEcosystemReward public ecosystemRewardContract;

    // Paw to NEKO conversion rate (e.g., 100 paw = 1 NEKO, so rate = 100)
    // Admin can update this rate
    uint256 public pawToNekoRate = 100; // 100 paw = 1 NEKO (with 18 decimals)

    // Message length limits (in bytes)
    uint256 public constant MAX_HAIKU_LENGTH = 250; // Max 250 characters for haiku
    uint256 public constant MAX_GMEOW_MESSAGE_LENGTH = 100; // Max 100 characters for GMeow message

    // ============ Events ============

    event PawRewarded(
        address indexed user,
        ActivityType indexed activityType,
        uint256 pawAmount,
        uint256 timestamp
    );

    event HaikuSubmitted(
        address indexed user,
        string haiku,
        uint256 pawReward,
        uint256 timestamp
    );

    event OnsenEntered(
        address indexed user,
        uint256 pawReward,
        uint256 xpBonusUntil,
        uint256 timestamp
    );

    event ZenGardenMeditated(
        address indexed user,
        uint256 pawReward,
        uint256 meditationCount,
        uint256 timestamp
    );

    event GMeowSigned(
        address indexed user,
        string message,
        uint256 dayNumber,
        uint256 pawReward,
        uint256 streakBonus,
        uint256 surpriseBonus,
        uint256 currentStreak,
        uint256 timestamp
    );

    event ActivityRewardUpdated(
        ActivityType indexed activityType,
        uint256 oldReward,
        uint256 newReward
    );

    event DailyLimitUpdated(
        ActivityType indexed activityType,
        uint256 oldLimit,
        uint256 newLimit
    );

    event PawConsumed(
        address indexed user,
        uint256 pawAmount,
        uint256 nekoAmount,
        uint256 timestamp
    );

    event EcosystemRewardContractUpdated(address indexed contractAddress);
    event PawToNekoRateUpdated(uint256 oldRate, uint256 newRate);

    // ============ Errors ============

    error InvalidActivity();
    error DailyLimitReached(uint256 limit, uint256 current);
    error InvalidHaiku();
    error InvalidAddress();
    error AlreadySignedToday();
    error InvalidDayNumber();
    error EcosystemRewardContractNotSet();
    error InsufficientPoolBalance(uint256 required, uint256 available);
    error InsufficientPaw(uint256 required, uint256 available);
    error InvalidPawAmount();
    error MessageTooLong(uint256 maxLength, uint256 providedLength);

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {
        // Set default rewards (in paw)
        activityRewards[ActivityType.Haiku] = 5; // 5 paw for haiku
        activityRewards[ActivityType.Onsen] = 3; // 3 paw for onsen
        activityRewards[ActivityType.ZenGarden] = 2; // 2 paw for zen garden
        activityRewards[ActivityType.GMeow] = 1; // 1 base paw for GMeow

        // Set daily limits
        dailyLimits[ActivityType.Haiku] = 1; // 1 per day
        dailyLimits[ActivityType.Onsen] = 3; // 3 per day
        dailyLimits[ActivityType.ZenGarden] = 3; // 3 per day
        dailyLimits[ActivityType.GMeow] = 1; // 1 per day

        // Set GMeow surprise days (day number => bonus paw)
        gmeowSurpriseDays[3] = 2; // Day 3: +2 bonus paw
        gmeowSurpriseDays[7] = 3; // Day 7: +3 bonus paw
        gmeowSurpriseDays[10] = 2; // Day 10: +2 bonus paw
        gmeowSurpriseDays[14] = 5; // Day 14: +5 bonus paw
        gmeowSurpriseDays[17] = 2; // Day 17: +2 bonus paw
        gmeowSurpriseDays[21] = 4; // Day 21: +4 bonus paw
        gmeowSurpriseDays[25] = 5; // Day 25: +5 bonus paw
        gmeowSurpriseDays[30] = 10; // Day 30: +10 bonus paw
    }

    // ============ Paw Claim Functions ============

    /**
     * @dev Consume paw to exchange for NEKO tokens from ecosystem reward pool
     * @param pawAmount Amount of paw to consume (user specifies how much to spend)
     * @notice Directly transfers NEKO tokens from ecosystem pool to user
     * @notice Paw are consumed (deducted from balance) in exchange for tokens
     */
    function consumePawForReward(uint256 pawAmount) external nonReentrant whenNotPaused {
        if (ecosystemRewardContract == INekoEcosystemReward(address(0))) {
            revert EcosystemRewardContractNotSet();
        }

        if (pawAmount == 0) {
            revert InvalidPawAmount();
        }

        uint256 userPaw = pawBalance[msg.sender];
        
        if (userPaw < pawAmount) {
            revert InsufficientPaw(pawAmount, userPaw);
        }

        // Calculate NEKO amount (with 18 decimals)
        // Example: 100 paw * 10^18 / 100 = 1 * 10^18 NEKO
        uint256 nekoAmount = (pawAmount * 1e18) / pawToNekoRate;

        // Check if ecosystem pool has enough balance
        (, uint256 ecosystemPool) = ecosystemRewardContract.getRewardPoolBalances();
        if (ecosystemPool < nekoAmount) {
            revert InsufficientPoolBalance(nekoAmount, ecosystemPool);
        }

        // Deduct paw from user's balance (consume)
        pawBalance[msg.sender] -= pawAmount;

        // Transfer NEKO tokens directly from ecosystem reward pool to user
        ecosystemRewardContract.transferFromPool(
            msg.sender,
            nekoAmount,
            "Paw Consumed"
        );
        
        emit PawConsumed(msg.sender, pawAmount, nekoAmount, block.timestamp);
    }

    /**
     * @dev Get NEKO amount for specified paw amount
     * @param pawAmount Amount of paw to check
     * @return NEKO amount that would be received
     */
    function getNekoForPaw(uint256 pawAmount) external view returns (uint256) {
        if (pawAmount == 0) {
            return 0;
        }
        return (pawAmount * 1e18) / pawToNekoRate;
    }

    /**
     * @dev Get maximum claimable NEKO for user (limited by paw balance and pool balance)
     */
    function getMaxClaimableNeko(address user) external view returns (uint256) {
        uint256 userPaw = pawBalance[user];
        if (userPaw == 0) {
            return 0;
        }
        
        uint256 maxNekoFromPaw = (userPaw * 1e18) / pawToNekoRate;
        
        // Check if ecosystem pool has enough balance
        if (ecosystemRewardContract == INekoEcosystemReward(address(0))) {
            return 0;
        }
        
        (, uint256 ecosystemPool) = ecosystemRewardContract.getRewardPoolBalances();
        
        // Return minimum of what user can claim and what pool has
        return ecosystemPool < maxNekoFromPaw ? ecosystemPool : maxNekoFromPaw;
    }

    // ============ Activity Functions ============

    /**
     * @dev Submit a haiku and earn paw
     * @param haiku The haiku text (3 lines, 5-7-5 syllables)
     * @notice Maximum 250 characters allowed
     */
    function submitHaiku(string memory haiku) external nonReentrant whenNotPaused {
        uint256 haikuLength = bytes(haiku).length;
        if (haikuLength == 0) revert InvalidHaiku();
        if (haikuLength > MAX_HAIKU_LENGTH) {
            revert MessageTooLong(MAX_HAIKU_LENGTH, haikuLength);
        }

        ActivityType activityType = ActivityType.Haiku;
        uint256 today = block.timestamp / 1 days;
        uint256 limit = dailyLimits[activityType];
        uint256 currentCount = dailyActivityCount[msg.sender][activityType][today];
        
        // Check daily limit
        if (currentCount >= limit) {
            revert DailyLimitReached(limit, currentCount);
        }

        uint256 reward = activityRewards[activityType];
        
        // Update state
        userHaikus[msg.sender].push(haiku);
        dailyActivityCount[msg.sender][activityType][today]++;
        pawBalance[msg.sender] += reward;
        totalPawDistributed += reward;

        emit HaikuSubmitted(msg.sender, haiku, reward, block.timestamp);
        emit PawRewarded(msg.sender, activityType, reward, block.timestamp);
    }

    /**
     * @dev Enter onsen and earn paw
     */
    function enterOnsen() external nonReentrant whenNotPaused {
        ActivityType activityType = ActivityType.Onsen;
        uint256 today = block.timestamp / 1 days;
        uint256 limit = dailyLimits[activityType];
        uint256 currentCount = dailyActivityCount[msg.sender][activityType][today];
        
        // Check daily limit
        if (currentCount >= limit) {
            revert DailyLimitReached(limit, currentCount);
        }

        uint256 reward = activityRewards[activityType];
        
        // Update state
        dailyActivityCount[msg.sender][activityType][today]++;
        pawBalance[msg.sender] += reward;
        totalPawDistributed += reward;

        emit OnsenEntered(msg.sender, reward, 0, block.timestamp);
        emit PawRewarded(msg.sender, activityType, reward, block.timestamp);
    }

    /**
     * @dev Meditate in zen garden and earn paw based on streak
     * @param streakBonus The streak bonus percentage (0-30)
     */
    function meditateZenGarden(uint256 streakBonus) external nonReentrant whenNotPaused {
        ActivityType activityType = ActivityType.ZenGarden;
        uint256 today = block.timestamp / 1 days;
        uint256 limit = dailyLimits[activityType];
        uint256 currentCount = dailyActivityCount[msg.sender][activityType][today];
        
        // Check daily limit
        if (currentCount >= limit) {
            revert DailyLimitReached(limit, currentCount);
        }

        // Cap streak bonus at 30%
        if (streakBonus > 30) streakBonus = 30;

        uint256 baseReward = activityRewards[activityType];
        uint256 bonusReward = (baseReward * streakBonus) / 100;
        uint256 totalReward = baseReward + bonusReward;
        
        // Update state
        dailyActivityCount[msg.sender][activityType][today]++;
        zenGardenMeditationCount[msg.sender]++;
        pawBalance[msg.sender] += totalReward;
        totalPawDistributed += totalReward;

        emit ZenGardenMeditated(msg.sender, totalReward, zenGardenMeditationCount[msg.sender], block.timestamp);
        emit PawRewarded(msg.sender, activityType, totalReward, block.timestamp);
    }

    /**
     * @dev Sign GMeow (Daily GM) and earn paw with streak bonus
     * @param message The GM message (max 100 characters)
     * @param dayNumber The day number in the 30-day cycle (1-30)
     * @param currentStreak The current streak count (frontend calculates)
     * @notice Can only sign once per day (24 hours)
     */
    function signGMeow(string memory message, uint256 dayNumber, uint256 currentStreak) external nonReentrant whenNotPaused {
        if (dayNumber == 0 || dayNumber > 30) revert InvalidDayNumber();
        uint256 messageLength = bytes(message).length;
        if (messageLength == 0) revert InvalidHaiku();
        if (messageLength > MAX_GMEOW_MESSAGE_LENGTH) {
            revert MessageTooLong(MAX_GMEOW_MESSAGE_LENGTH, messageLength);
        }

        ActivityType activityType = ActivityType.GMeow;
        
        // Check if already signed today
        uint256 today = block.timestamp / 1 days;
        uint256 limit = dailyLimits[activityType];
        uint256 currentCount = dailyActivityCount[msg.sender][activityType][today];
        
        // Check daily limit
        if (currentCount >= limit) {
            revert DailyLimitReached(limit, currentCount);
        }

        // Calculate streak (frontend passes current streak, we increment it)
        uint256 newStreak = currentStreak + 1;
        bool hasStreak = currentStreak > 0;

        // Calculate rewards
        uint256 baseReward = activityRewards[activityType]; // 1 paw base
        
        // Streak bonus (max 30% bonus)
        uint256 streakBonusPercent = newStreak > 30 ? 30 : newStreak;
        uint256 streakBonus = (baseReward * streakBonusPercent) / 100;
        
        // Surprise bonus (if applicable and has streak)
        uint256 surpriseBonus = 0;
        if (hasStreak && gmeowSurpriseDays[dayNumber] > 0) {
            surpriseBonus = gmeowSurpriseDays[dayNumber];
        }
        
        uint256 totalReward = baseReward + streakBonus + surpriseBonus;

        // Update state
        if (gmeowFirstSignDate[msg.sender] == 0) {
            gmeowFirstSignDate[msg.sender] = block.timestamp;
        }
        
        // Mark this day as signed (using day number as key)
        gmeowSignedDates[msg.sender][dayNumber] = true;
        dailyActivityCount[msg.sender][activityType][today]++;
        gmeowCurrentStreak[msg.sender] = newStreak;
        gmeowTotalSigned[msg.sender]++;
        gmeowTotalPaw[msg.sender] += totalReward;
        pawBalance[msg.sender] += totalReward;
        totalPawDistributed += totalReward;

        emit GMeowSigned(
            msg.sender,
            message,
            dayNumber,
            totalReward,
            streakBonus,
            surpriseBonus,
            newStreak,
            block.timestamp
        );
        emit PawRewarded(msg.sender, activityType, totalReward, block.timestamp);
    }

    // ============ View Functions ============

    /**
     * @dev Get user's paw balance
     */
    function getPawBalance(address user) external view returns (uint256) {
        return pawBalance[user];
    }

    /**
     * @dev Get user's haikus
     */
    function getUserHaikus(address user) external view returns (string[] memory) {
        return userHaikus[user];
    }

    /**
     * @dev Check if user can perform activity (daily limit check)
     */
    function canPerformActivity(address user, ActivityType activityType) external view returns (bool, uint256) {
        uint256 today = block.timestamp / 1 days;
        uint256 limit = dailyLimits[activityType];
        uint256 currentCount = dailyActivityCount[user][activityType][today];
        
        if (currentCount < limit) {
            return (true, limit - currentCount);
        }
        
        return (false, 0);
    }

    /**
     * @dev Get daily activity count for user
     */
    function getDailyActivityCount(address user, ActivityType activityType) external view returns (uint256) {
        uint256 today = block.timestamp / 1 days;
        return dailyActivityCount[user][activityType][today];
    }

    /**
     * @dev Get GMeow stats for a user
     */
    function getGMeowStats(address user) external view returns (
        uint256 currentStreak,
        uint256 totalSigned,
        uint256 totalPaw,
        uint256 firstSignDate,
        bool canSignToday
    ) {
        currentStreak = gmeowCurrentStreak[user];
        totalSigned = gmeowTotalSigned[user];
        totalPaw = gmeowTotalPaw[user];
        firstSignDate = gmeowFirstSignDate[user];
        
        uint256 today = block.timestamp / 1 days;
        uint256 limit = dailyLimits[ActivityType.GMeow];
        uint256 currentCount = dailyActivityCount[user][ActivityType.GMeow][today];
        canSignToday = currentCount < limit;
    }

    /**
     * @dev Check if user signed a specific day
     */
    function hasSignedGMeowDay(address user, uint256 dayNumber) external view returns (bool) {
        return gmeowSignedDates[user][dayNumber];
    }

    // ============ Admin Functions ============

    /**
     * @dev Update activity reward
     */
    function setActivityReward(ActivityType activityType, uint256 reward) external onlyOwner {
        uint256 oldReward = activityRewards[activityType];
        activityRewards[activityType] = reward;
        emit ActivityRewardUpdated(activityType, oldReward, reward);
    }

    /**
     * @dev Update daily limit
     */
    function setDailyLimit(ActivityType activityType, uint256 limit) external onlyOwner {
        require(limit > 0, "Limit must be greater than 0");
        uint256 oldLimit = dailyLimits[activityType];
        dailyLimits[activityType] = limit;
        emit DailyLimitUpdated(activityType, oldLimit, limit);
    }

    /**
     * @dev Set ecosystem reward contract address
     */
    function setEcosystemRewardContract(address _ecosystemRewardContract) external onlyOwner {
        require(_ecosystemRewardContract != address(0), "Invalid address");
        ecosystemRewardContract = INekoEcosystemReward(_ecosystemRewardContract);
        emit EcosystemRewardContractUpdated(_ecosystemRewardContract);
    }

    /**
     * @dev Update paw to NEKO conversion rate
     */
    function setPawToNekoRate(uint256 _rate) external onlyOwner {
        require(_rate > 0, "Rate must be greater than 0");
        uint256 oldRate = pawToNekoRate;
        pawToNekoRate = _rate;
        emit PawToNekoRateUpdated(oldRate, _rate);
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
     * @dev Emergency withdraw tokens (if any are accidentally sent)
     * @param tokenAddress Token address to withdraw (0x0 for native ETH)
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address tokenAddress, uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Invalid amount");
        if (tokenAddress == address(0)) {
            // Withdraw native ETH
            (bool success, ) = payable(owner()).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // Withdraw ERC20 tokens
            IERC20(tokenAddress).transfer(owner(), amount);
        }
    }
}

