// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title INekoICO
 * @dev Interface for NEKO ICO Contract (ETH-only)
 */
interface INekoICO {
    // =============================================================================
    // STRUCTS
    // =============================================================================
    struct Stage {
        string name;
        uint256 price;
        uint256 cap;
        uint256 sold;
        uint256 minPurchase;
        uint256 maxPurchase;
        uint256 startTime;
        uint256 endTime;
        bool requiresWhitelist;
        bool active;
    }

    struct Purchase {
        uint256 amount;
        uint256 paid;
        uint256 timestamp;
        uint8 stageId;
    }

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
    event ReferralRewardPercentageUpdated(
        uint256 oldPercentage,
        uint256 newPercentage
    );
    event ReferralCodeGenerated(address indexed user, string indexed code);
    event ReferralCodeContractUpdated(address indexed contractAddress);
    event EcosystemRewardContractUpdated(address indexed contractAddress);

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
    ) external;

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
    ) external;

    function startStage(uint8 stageId) external;
    function endStage(uint8 stageId) external;

    // =============================================================================
    // PURCHASE FUNCTIONS
    // =============================================================================
    function buyTokens(uint8 stageId) external payable;
    function buyTokensWithReferral(
        uint8 stageId,
        address referrer
    ) external payable;
    function buyWithETH(address referrer) external payable;

    // MEV Protection Functions
    function commitToPurchase(bytes32 commitment) external;
    function revealAndPurchase(
        uint256 amount,
        uint256 nonce,
        uint8 stageId,
        address referrer
    ) external payable;

    // =============================================================================
    // REFERRAL FUNCTIONS
    // =============================================================================
    function claimReferralRewards() external;
    function getReferralRewards(
        address referrer
    ) external view returns (uint256);
    function setReferralRewardPercentage(uint256 newPercentage) external;
    function getReferralRewardPercentage() external view returns (uint256);
    function setReferralCodeContract(address _referralCodeContract) external;
    function setEcosystemRewardContract(
        address _ecosystemRewardContract
    ) external;
    function buyWithETHByCode(string memory referralCode) external payable;
    function getReferrerFromCode(
        string memory referralCode
    ) external view returns (address);
    function isValidReferralCode(
        string memory referralCode
    ) external view returns (bool);

    // =============================================================================
    // WHITELIST MANAGEMENT
    // =============================================================================
    function addToWhitelist(address[] calldata users) external;
    function removeFromWhitelist(address[] calldata users) external;

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================
    function withdrawFunds() external;
    function emergencyWithdrawTokens(address token, uint256 amount) external;
    function updateTreasuryContract(address newTreasuryContract) external;
    function configureVesting(
        uint256 duration,
        uint256 cliff,
        bool enabled
    ) external;
    function pause() external;
    function unpause() external;

    // =============================================================================
    // PRICE MANAGEMENT
    // =============================================================================
    function updateStagePrice(uint8 stageId, uint256 newPrice) external;
    function updateCurrentStagePrice(uint256 newPrice) external;
    function batchUpdateStagePrices(
        uint8[] calldata stageIds,
        uint256[] calldata newPrices
    ) external;

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
        );

    function getUserPurchases(
        address user
    ) external view returns (Purchase[] memory);
    function getUserPurchasedAmount(
        address user,
        uint8 stageId
    ) external view returns (uint256);
    function calculateTokenAmount(
        uint256 paymentAmount,
        uint8 stageId
    ) external view returns (uint256);
    function getStage(uint8 stageId) external view returns (Stage memory);
    function getCurrentStage() external view returns (uint8);
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
        );

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================
    function nekoToken() external view returns (address);
    function vestingContract() external view returns (address);
    function treasuryContract() external view returns (address);
    function currentStageId() external view returns (uint8);
    function totalRaised() external view returns (uint256);
    function totalTokensSold() external view returns (uint256);
    function vestingEnabled() external view returns (bool);
    function vestingDuration() external view returns (uint256);
    function vestingCliff() external view returns (uint256);
}
