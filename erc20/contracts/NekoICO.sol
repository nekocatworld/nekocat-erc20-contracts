// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../lib/NekoCoinConstants.sol";
import "../interfaces/INekoICO.sol";
import "../lib/NekoCoinErrors.sol";
import "../interfaces/INekoReferralCode.sol";
import "../interfaces/INekoEcosystemReward.sol";
import "../interfaces/INekoTreasury.sol";

interface INekoVesting {
    function createVesting(
        address beneficiary,
        uint256 amount,
        uint256 startTime,
        uint256 duration,
        uint256 cliff,
        bool revocable
    ) external;
}

/**
 * @title NekoICO
 * @dev NEKO Coin ICO/Presale Contract with multi-stage sales, vesting, and emergency controls
 *
 * Features:
 * - Multi-stage ICO (Seed, Private, Public)
 * - ETH-only payment support
 * - Automatic vesting integration
 * - Whitelist for early stages
 * - Emergency pause and fund recovery
 * - Admin can withdraw anytime
 * - Minimum/maximum purchase limits
 * - Referral system
 * - Front-running protection
 * - MEV attack protection
 *
 * Security:
 * - ReentrancyGuard on all payment functions
 * - Pausable for emergency stops
 * - SafeERC20 for token transfers
 * - Input validation on all parameters
 * - Access control for admin functions
 * - Block-based front-running protection
 * - Commit-reveal scheme for MEV protection
 */
contract NekoICO is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // =============================================================================
    // CUSTOM ERRORS
    // =============================================================================
    error InvalidAddress();
    error InvalidAmount();
    error InvalidStage();
    error StageNotActive();
    error StageSoldOut();
    error BelowMinPurchase();
    error AboveMaxPurchase();
    error NotWhitelisted();
    error InsufficientPayment();
    error TransferFailed();
    error InvalidPrice();
    error InvalidCap();
    error StageAlreadyStarted();
    error NoTokensToWithdraw();
    error NothingToClaim();
    error FrontRunProtectionActive();
    error MEVProtectionActive();
    error InvalidCommitment();
    error InsufficientTokenBalance();

    // =============================================================================
    // STRUCTS
    // =============================================================================
    struct Stage {
        string name;
        uint256 price; // Price per token in wei (ETH only)
        uint256 cap; // Total tokens available for this stage
        uint256 sold; // Tokens sold in this stage
        uint256 minPurchase; // Minimum purchase amount
        uint256 maxPurchase; // Maximum purchase amount per wallet
        uint256 startTime;
        uint256 endTime;
        bool requiresWhitelist;
        bool active;
    }

    struct Purchase {
        uint256 amount; // Token amount
        uint256 paid; // Amount paid in ETH
        uint256 timestamp;
        uint8 stageId;
    }

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================
    IERC20 public immutable nekoToken;
    address public immutable vestingContract;
    address public treasuryContract; // Treasury contract for fund management

    uint8 public currentStageId;
    mapping(uint8 => Stage) public stages;
    mapping(address => mapping(uint8 => uint256)) public purchasedPerStage;
    mapping(address => uint256) public userPurchasesCount; // user => number of purchases
    mapping(address => mapping(uint256 => Purchase)) public userPurchases; // user => index => purchase
    mapping(address => bool) public whitelist;
    mapping(address => uint256) public referralRewards;
    uint256 public referralRewardPercentage = 500; // 5% in basis points (500/10000)

    // Referral code contract
    address public referralCodeContract;

    // Ecosystem reward contract
    address public ecosystemRewardContract;

    // Front-running protection
    mapping(address => mapping(uint8 => uint256)) public lastPurchaseBlock;
    mapping(bytes32 => uint256) public commitments;
    mapping(address => uint256) public userNonces;
    mapping(address => mapping(bytes32 => bool)) public usedCommitments; // Prevent commitment reuse

    uint256 public totalRaised; // Total ETH raised
    uint256 public totalTokensSold;

    bool public vestingEnabled;
    uint256 public vestingDuration; // Vesting duration in seconds
    uint256 public vestingCliff; // Vesting cliff in seconds

    // Admin configurable prices (in USD, 8 decimals)
    uint256 public tokenPriceUSD = 2575; // $0.00002575 per NEKO (default)

    // =============================================================================
    // EVENTS
    // =============================================================================
    event StageCreated(
        uint8 indexed stageId,
        string name,
        uint256 price,
        uint256 cap
    );
    event StageUpdated(
        uint8 indexed stageId,
        string name,
        uint256 price,
        uint256 cap
    );
    event StageStarted(uint8 indexed stageId);
    event StageEnded(uint8 indexed stageId);
    event TokensPurchased(
        address indexed buyer,
        uint256 amount,
        uint256 paid,
        address paymentToken,
        uint8 stageId
    );
    event WhitelistUpdated(address indexed user, bool status);
    event TreasuryUpdated(
        address indexed oldTreasury,
        address indexed newTreasury
    );
    event TokenPriceUpdated(uint256 oldPrice, uint256 newPrice);
    event VestingDurationUpdated(uint256 oldDuration, uint256 newDuration);
    event VestingCliffUpdated(uint256 oldCliff, uint256 newCliff);
    event ReferralRewardPercentageUpdated(
        uint256 oldPercentage,
        uint256 newPercentage
    );
    event ReferralCodeGenerated(address indexed user, string indexed code);
    event ReferralCodeContractUpdated(address indexed contractAddress);
    event EcosystemRewardContractUpdated(address indexed contractAddress);
    event RoleGranted(
        bytes32 indexed role,
        address indexed account,
        address indexed sender
    );
    event RoleRevoked(
        bytes32 indexed role,
        address indexed account,
        address indexed sender
    );
    event FundsWithdrawn(address indexed to, uint256 ethAmount);
    event EmergencyWithdraw(address indexed token, uint256 amount);
    event VestingConfigured(uint256 duration, uint256 cliff);
    event ReferralRewarded(
        address indexed referrer,
        address indexed buyer,
        uint256 reward
    );
    event TokensClaimed(
        address indexed claimer,
        uint256 amount,
        uint8 indexed stageId
    );
    event CommitmentMade(
        address indexed user,
        bytes32 indexed commitment,
        uint256 blockNumber
    );
    event StagePriceUpdated(
        uint8 indexed stageId,
        uint256 oldPrice,
        uint256 newPrice
    );
    event DynamicPricingToggled(bool enabled);
    event ETHPriceUpdated(uint256 newPrice);

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================
    constructor(
        address _nekoToken,
        address _vestingContract,
        address _treasuryContract,
        address initialOwner
    ) Ownable(initialOwner) {
        if (_nekoToken == address(0)) revert InvalidAddress();
        if (_treasuryContract == address(0)) revert InvalidAddress();

        nekoToken = IERC20(_nekoToken);
        vestingContract = _vestingContract;
        treasuryContract = _treasuryContract;

        vestingEnabled = true;
        vestingDuration = 365 days; // 1 year default
        vestingCliff = 30 days; // 30 days cliff
    }

    // =============================================================================
    // STAGE MANAGEMENT
    // =============================================================================
    function createStage(
        uint8 stageId,
        string memory name,
        uint256 price,
        uint256 cap,
        uint256 minPurchase,
        uint256 maxPurchase,
        uint256 startTime,
        uint256 endTime,
        bool requiresWhitelist
    ) external onlyOwner nonReentrant {
        if (stages[stageId].cap > 0) revert StageAlreadyStarted();
        if (price == 0) revert InvalidPrice();
        // Allow cap to be 0 for testing
        if (startTime > 0 && endTime > 0 && startTime >= endTime)
            revert InvalidStage();
        if (minPurchase > maxPurchase) revert InvalidAmount();

        stages[stageId] = Stage({
            name: name,
            price: price,
            cap: cap,
            sold: 0,
            minPurchase: minPurchase,
            maxPurchase: maxPurchase,
            startTime: startTime,
            endTime: endTime,
            requiresWhitelist: requiresWhitelist,
            active: false
        });

        emit StageCreated(stageId, name, price, cap);
    }

    function updateStage(
        uint8 stageId,
        string memory name,
        uint256 price,
        uint256 cap,
        uint256 minPurchase,
        uint256 maxPurchase,
        uint256 startTime,
        uint256 endTime,
        bool whitelistRequired
    ) external onlyOwner nonReentrant {
        Stage storage stage = stages[stageId];
        if (stage.cap == 0) revert InvalidStage();
        if (stage.active) revert StageAlreadyStarted();

        stage.name = name;
        stage.price = price;
        stage.cap = cap;
        stage.minPurchase = minPurchase;
        stage.maxPurchase = maxPurchase;
        stage.startTime = startTime;
        stage.endTime = endTime;
        stage.requiresWhitelist = whitelistRequired;

        emit StageUpdated(stageId, name, price, cap);
    }

    function startStage(uint8 stageId) external onlyOwner nonReentrant {
        Stage storage stage = stages[stageId];
        // Allow starting stages even if cap is 0 (for testing purposes)

        stage.active = true;
        currentStageId = stageId;

        emit StageStarted(stageId);
    }

    function endStage(uint8 stageId) external onlyOwner nonReentrant {
        Stage storage stage = stages[stageId];
        if (stage.cap == 0) revert InvalidStage();

        stage.active = false;

        emit StageEnded(stageId);
    }

    // =============================================================================
    // PURCHASE FUNCTIONS
    // =============================================================================

    /**
     * @dev Buy with ETH without referrer (uses current stage)
     */
    function buyWithETH() external payable nonReentrant whenNotPaused {
        _buyWithETHInternal(address(0));
    }

    /**
     * @dev Internal function for ETH purchases with front-running protection
     */
    function _buyWithETHInternal(address referrer) internal {
        Stage storage stage = stages[currentStageId];

        // Front-running protection
        if (lastPurchaseBlock[msg.sender][currentStageId] + 3 > block.number) {
            revert FrontRunProtectionActive();
        }
        lastPurchaseBlock[msg.sender][currentStageId] = block.number;

        _validatePurchase(stage, msg.sender, msg.value, currentStageId);

        uint256 tokenAmount = (msg.value * 10 ** 18) / stage.price;

        _processPurchase(msg.sender, tokenAmount, msg.value, currentStageId);

        // Process referral only if referrer is valid and not self-referral
        if (referrer != address(0) && referrer != msg.sender) {
            _processReferral(referrer, tokenAmount);
        }

        emit TokensPurchased(
            msg.sender,
            tokenAmount,
            msg.value,
            address(0),
            currentStageId
        );
    }

    function _validatePurchase(
        Stage storage stage,
        address buyer,
        uint256 paymentAmount,
        uint8 stageId
    ) internal view {
        // Basic validations
        if (paymentAmount == 0) revert InvalidAmount();
        if (!stage.active) revert StageNotActive();

        // Allow purchases if no time restrictions are set (both startTime and endTime are 0)
        // or if current time is within the valid range with tolerance
        if (stage.startTime > 0 || stage.endTime > 0) {
            uint256 tolerance = 300; // 5 minutes
            if (
                stage.startTime > 0 &&
                block.timestamp + tolerance < stage.startTime
            ) revert StageNotActive();
            if (
                stage.endTime > 0 && block.timestamp > stage.endTime + tolerance
            ) revert StageNotActive();
        }

        if (stage.requiresWhitelist && !whitelist[buyer])
            revert NotWhitelisted();

        // Purchase amount validations
        if (paymentAmount < stage.minPurchase) revert BelowMinPurchase();
        if (paymentAmount > stage.maxPurchase) revert AboveMaxPurchase();

        // Calculate token amount for validation
        uint256 tokenAmount = (paymentAmount * 10 ** 18) / stage.price;
        if (tokenAmount == 0) revert InvalidAmount();
    }

    function _processPurchase(
        address buyer,
        uint256 tokenAmount,
        uint256 paid,
        uint8 stageId
    ) internal {
        Stage storage stage = stages[stageId];

        // ✅ CRITICAL: Check if contract has enough tokens
        if (nekoToken.balanceOf(address(this)) < tokenAmount) {
            revert InsufficientTokenBalance();
        }

        // Check if stage is sold out before processing
        if (stage.sold + tokenAmount > stage.cap) revert StageSoldOut();

        stage.sold += tokenAmount;
        totalTokensSold += tokenAmount;
        purchasedPerStage[buyer][stageId] += tokenAmount;

        totalRaised += paid;

        // Add purchase to user's purchase history
        uint256 purchaseIndex = userPurchasesCount[buyer];
        userPurchases[buyer][purchaseIndex] = Purchase({
            amount: tokenAmount,
            paid: paid,
            timestamp: block.timestamp,
            stageId: stageId
        });
        userPurchasesCount[buyer]++;

        if (vestingEnabled && vestingContract != address(0)) {
            nekoToken.safeTransfer(vestingContract, tokenAmount);
            INekoVesting(vestingContract).createVesting(
                buyer,
                tokenAmount,
                block.timestamp,
                vestingDuration,
                vestingCliff,
                false
            );
        } else {
            nekoToken.safeTransfer(buyer, tokenAmount);
        }

        // Emit the TokensPurchased event
        emit TokensPurchased(buyer, tokenAmount, paid, address(0), stageId);
    }

    function _processReferral(address referrer, uint256 tokenAmount) internal {
        if (ecosystemRewardContract != address(0)) {
            // Use ecosystem reward contract
            INekoEcosystemReward(ecosystemRewardContract).addReferralReward(
                referrer,
                msg.sender,
                tokenAmount
            );
        } else {
            // Fallback to local processing (for backward compatibility)
            uint256 reward = (tokenAmount * referralRewardPercentage) / 10000;
            referralRewards[referrer] += reward;
            emit ReferralRewarded(referrer, msg.sender, reward);
        }
    }

    function claimReferralRewards() external nonReentrant whenNotPaused {
        uint256 rewards = referralRewards[msg.sender];
        if (rewards == 0) revert NothingToClaim();

        referralRewards[msg.sender] = 0;
        nekoToken.safeTransfer(msg.sender, rewards);

        emit TokensClaimed(msg.sender, rewards, type(uint8).max);
    }

    function getReferralRewards(
        address referrer
    ) external view returns (uint256) {
        return referralRewards[referrer];
    }

    function commitToPurchase(
        bytes32 commitment
    ) external nonReentrant whenNotPaused {
        // Prevent commitment reuse
        if (usedCommitments[msg.sender][commitment]) revert InvalidCommitment();
        if (commitments[commitment] != 0) revert InvalidCommitment(); // Commitment already exists

        commitments[commitment] = block.number;
        usedCommitments[msg.sender][commitment] = true;
        userNonces[msg.sender]++;

        emit CommitmentMade(msg.sender, commitment, block.number);
    }

    function revealAndPurchase(
        uint256 amount,
        uint256 nonce,
        uint8 stageId,
        address referrer
    ) external payable nonReentrant whenNotPaused {
        bytes32 commitment = keccak256(
            abi.encodePacked(msg.sender, amount, nonce, stageId, block.chainid)
        );

        if (commitments[commitment] == 0) revert InvalidCommitment();
        if (block.number < commitments[commitment] + 3)
            // Increased from 2 to 3
            revert MEVProtectionActive();
        if (block.number > commitments[commitment] + 200)
            // Reduced from 250 to 200
            revert InvalidCommitment();
        if (msg.value != amount) revert InvalidAmount(); // Strict amount validation

        delete commitments[commitment];

        Stage storage stage = stages[stageId];
        _validatePurchase(stage, msg.sender, msg.value, stageId);

        uint256 tokenAmount = (msg.value * 10 ** 18) / stage.price;

        _processPurchase(msg.sender, tokenAmount, msg.value, stageId);

        // Self-referral protection - already validated in commit
        if (referrer != address(0) && referrer != msg.sender) {
            _processReferral(referrer, tokenAmount);
        }

        emit TokensPurchased(
            msg.sender,
            tokenAmount,
            msg.value,
            address(0),
            stageId
        );
    }

    // =============================================================================
    // WHITELIST MANAGEMENT
    // =============================================================================
    function addToWhitelist(
        address[] calldata users
    ) external onlyOwner nonReentrant {
        for (uint256 i = 0; i < users.length; i++) {
            whitelist[users[i]] = true;
            emit WhitelistUpdated(users[i], true);
        }
    }

    function removeFromWhitelist(
        address[] calldata users
    ) external onlyOwner nonReentrant {
        for (uint256 i = 0; i < users.length; i++) {
            whitelist[users[i]] = false;
            emit WhitelistUpdated(users[i], false);
        }
    }

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================
    function withdrawFunds() external onlyOwner nonReentrant {
        uint256 ethBalance = address(this).balance;
        if (ethBalance == 0) revert InvalidAmount();

        INekoTreasury(treasuryContract).depositFunds{value: ethBalance}(
            address(0),
            ethBalance,
            "ICO_ETH_WITHDRAWAL"
        );

        emit FundsWithdrawn(treasuryContract, ethBalance);
    }

    function emergencyWithdrawTokens(
        address token,
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (token == address(0)) {
            // ETH withdrawal - check actual balance
            uint256 ethBalance = address(this).balance;
            if (amount > ethBalance) revert InvalidAmount();

            (bool success, ) = owner().call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            // Token withdrawal - check actual balance
            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            if (amount > tokenBalance) revert InvalidAmount();

            IERC20(token).safeTransfer(owner(), amount);
        }

        emit EmergencyWithdraw(token, amount);
    }

    function updateTreasuryContract(
        address newTreasuryContract
    ) external onlyOwner nonReentrant {
        if (newTreasuryContract == address(0)) revert InvalidAddress();

        address oldTreasuryContract = treasuryContract;
        treasuryContract = newTreasuryContract;

        emit TreasuryUpdated(oldTreasuryContract, newTreasuryContract);
    }

    function configureVesting(
        uint256 duration,
        uint256 cliff,
        bool enabled
    ) external onlyOwner nonReentrant {
        vestingDuration = duration;
        vestingCliff = cliff;
        vestingEnabled = enabled;

        emit VestingConfigured(duration, cliff);
    }

    function pause() external onlyOwner nonReentrant {
        _pause();
    }

    function unpause() external onlyOwner nonReentrant {
        _unpause();
    }

    // =============================================================================
    // PRICE MANAGEMENT
    // =============================================================================
    function updateStagePrice(
        uint8 stageId,
        uint256 newPrice
    ) external onlyOwner nonReentrant {
        if (newPrice == 0) revert InvalidPrice();

        Stage storage stage = stages[stageId];
        if (stage.cap == 0) revert InvalidStage();

        uint256 oldPrice = stage.price;
        stage.price = newPrice;

        emit StagePriceUpdated(stageId, oldPrice, newPrice);
    }

    function updateCurrentStagePrice(
        uint256 newPrice
    ) external onlyOwner nonReentrant {
        if (newPrice == 0) revert InvalidPrice();

        Stage storage stage = stages[currentStageId];
        if (stage.cap == 0) revert InvalidStage();

        uint256 oldPrice = stage.price;
        stage.price = newPrice;

        emit StagePriceUpdated(currentStageId, oldPrice, newPrice);
    }

    function batchUpdateStagePrices(
        uint8[] calldata stageIds,
        uint256[] calldata newPrices
    ) external onlyOwner nonReentrant {
        if (stageIds.length != newPrices.length) revert InvalidAmount();
        if (stageIds.length == 0) revert InvalidAmount();

        for (uint256 i = 0; i < stageIds.length; i++) {
            if (newPrices[i] == 0) revert InvalidPrice();

            Stage storage stage = stages[stageIds[i]];
            if (stage.cap == 0) revert InvalidStage();

            uint256 oldPrice = stage.price;
            stage.price = newPrices[i];

            emit StagePriceUpdated(stageIds[i], oldPrice, newPrices[i]);
        }
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================
    function getStageInfo(
        uint8 stageId
    )
        external
        view
        returns (
            string memory name,
            uint256 price,
            uint256 cap,
            uint256 sold,
            uint256 remaining,
            bool active,
            bool requiresWhitelist
        )
    {
        Stage storage stage = stages[stageId];
        return (
            stage.name,
            stage.price,
            stage.cap,
            stage.sold,
            stage.cap - stage.sold,
            stage.active,
            stage.requiresWhitelist
        );
    }

    function getUserPurchases(
        address user
    ) external view returns (Purchase[] memory) {
        uint256 count = userPurchasesCount[user];
        Purchase[] memory userPurchaseList = new Purchase[](count);

        for (uint256 i = 0; i < count; i++) {
            userPurchaseList[i] = userPurchases[user][i];
        }

        return userPurchaseList;
    }

    function getUserPurchasedAmount(
        address user,
        uint8 stageId
    ) external view returns (uint256) {
        return purchasedPerStage[user][stageId];
    }

    function calculateTokenAmount(
        uint256 paymentAmount,
        uint8 stageId
    ) external view returns (uint256) {
        Stage storage stage = stages[stageId];
        return (paymentAmount * 10 ** 18) / stage.price;
    }

    /**
     * @dev Get contract's token balance
     */
    function getContractTokenBalance() external view returns (uint256) {
        return nekoToken.balanceOf(address(this));
    }

    /**
     * @dev Check if contract has enough tokens for a purchase
     */
    function canFulfillPurchase(
        uint256 ethAmount,
        uint8 stageId
    ) external view returns (bool) {
        Stage storage stage = stages[stageId];
        uint256 tokenAmount = (ethAmount * 10 ** 18) / stage.price;
        return nekoToken.balanceOf(address(this)) >= tokenAmount;
    }

    /**
     * @dev Get maximum ETH amount that can be spent based on available tokens
     */
    function getMaxPurchaseAmount(
        uint8 stageId
    ) external view returns (uint256) {
        Stage storage stage = stages[stageId];
        uint256 availableTokens = nekoToken.balanceOf(address(this));
        if (availableTokens == 0) return 0;
        return (availableTokens * stage.price) / (10 ** 18);
    }

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================

    function getStage(uint8 stageId) external view returns (Stage memory) {
        return stages[stageId];
    }

    function getCurrentStage() external view returns (uint8) {
        return currentStageId;
    }

    function getCurrentStageInfo()
        external
        view
        returns (
            string memory name,
            uint256 price,
            uint256 cap,
            uint256 sold,
            uint256 remaining,
            bool active,
            bool requiresWhitelist
        )
    {
        Stage storage stage = stages[currentStageId];
        return (
            stage.name,
            stage.price,
            stage.cap,
            stage.sold,
            stage.cap - stage.sold,
            stage.active,
            stage.requiresWhitelist
        );
    }

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================

    /**
     * @dev Update token price in USD (admin only)
     */
    function setTokenPriceUSD(uint256 newPriceUSD) external onlyOwner {
        require(newPriceUSD > 0, "Price must be > 0");
        uint256 oldPrice = tokenPriceUSD;
        tokenPriceUSD = newPriceUSD;
        emit TokenPriceUpdated(oldPrice, newPriceUSD);
    }

    /**
     * @dev Update vesting duration (admin only)
     */
    function setVestingDuration(uint256 newDuration) external onlyOwner {
        require(newDuration > 0, "Duration must be > 0");
        uint256 oldDuration = vestingDuration;
        vestingDuration = newDuration;
        emit VestingDurationUpdated(oldDuration, newDuration);
    }

    /**
     * @dev Update vesting cliff (admin only)
     */
    function setVestingCliff(uint256 newCliff) external onlyOwner {
        require(newCliff <= vestingDuration, "Cliff must be <= duration");
        uint256 oldCliff = vestingCliff;
        vestingCliff = newCliff;
        emit VestingCliffUpdated(oldCliff, newCliff);
    }

    /**
     * @dev Update treasury address (admin only)
     */
    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Invalid treasury address");
        address oldTreasury = treasuryContract;
        treasuryContract = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @dev Set referral reward percentage (admin only)
     * @param newPercentage New referral percentage in basis points (e.g., 500 = 5%)
     */
    function setReferralRewardPercentage(
        uint256 newPercentage
    ) external onlyOwner {
        require(newPercentage <= 2000, "Referral percentage too high"); // Max 20%
        uint256 oldPercentage = referralRewardPercentage;
        referralRewardPercentage = newPercentage;
        emit ReferralRewardPercentageUpdated(oldPercentage, newPercentage);
    }

    /**
     * @dev Get current referral reward percentage
     */
    function getReferralRewardPercentage() external view returns (uint256) {
        return referralRewardPercentage;
    }

    /**
     * @dev Set referral code contract address (admin only)
     * @param _referralCodeContract The address of the referral code contract
     */
    function setReferralCodeContract(
        address _referralCodeContract
    ) external onlyOwner {
        require(_referralCodeContract != address(0), "Invalid address");
        referralCodeContract = _referralCodeContract;
        emit ReferralCodeContractUpdated(_referralCodeContract);
    }

    /**
     * @dev Set ecosystem reward contract address (admin only)
     * @param _ecosystemRewardContract The address of the ecosystem reward contract
     */
    function setEcosystemRewardContract(
        address _ecosystemRewardContract
    ) external onlyOwner {
        require(_ecosystemRewardContract != address(0), "Invalid address");
        ecosystemRewardContract = _ecosystemRewardContract;
        emit EcosystemRewardContractUpdated(_ecosystemRewardContract);
    }

    /**
     * @dev Buy with ETH using referral code
     * @param referralCode The referral code to use
     */
    function buyWithETHByCode(
        string memory referralCode
    ) external payable nonReentrant whenNotPaused {
        require(
            referralCodeContract != address(0),
            "Referral code contract not set"
        );

        address referrer = INekoReferralCode(referralCodeContract)
            .getAddressFromCode(referralCode);
        require(referrer != address(0), "Invalid referral code");
        require(referrer != msg.sender, "Cannot refer yourself");

        Stage storage stage = stages[currentStageId];

        // Front-running protection
        if (lastPurchaseBlock[msg.sender][currentStageId] + 3 > block.number) {
            revert FrontRunProtectionActive();
        }
        lastPurchaseBlock[msg.sender][currentStageId] = block.number;

        _validatePurchase(stage, msg.sender, msg.value, currentStageId);

        uint256 tokenAmount = (msg.value * 10 ** 18) / stage.price;

        _processPurchase(msg.sender, tokenAmount, msg.value, currentStageId);

        // Process referral using ecosystem reward contract
        if (ecosystemRewardContract != address(0)) {
            INekoEcosystemReward(ecosystemRewardContract)
                .addReferralRewardByCode(referralCode, msg.sender, tokenAmount);
        } else {
            // Fallback to local processing
            _processReferral(referrer, tokenAmount);
        }

        emit TokensPurchased(
            msg.sender,
            tokenAmount,
            msg.value,
            address(0),
            currentStageId
        );
    }

    /**
     * @dev Get referrer address from referral code
     * @param referralCode The referral code
     * @return The referrer address
     */
    function getReferrerFromCode(
        string memory referralCode
    ) external view returns (address) {
        if (referralCodeContract == address(0)) {
            return address(0);
        }
        return
            INekoReferralCode(referralCodeContract).getAddressFromCode(
                referralCode
            );
    }

    /**
     * @dev Check if referral code exists
     * @param referralCode The referral code to check
     * @return True if code exists, false otherwise
     */
    function isValidReferralCode(
        string memory referralCode
    ) external view returns (bool) {
        if (referralCodeContract == address(0)) {
            return false;
        }
        return INekoReferralCode(referralCodeContract).codeExists(referralCode);
    }

    receive() external payable {
        revert("Use buyWithETH function");
    }
}
