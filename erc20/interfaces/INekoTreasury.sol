// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title INekoTreasury
 * @dev Interface for NekoTreasury contract
 * @notice Centralized treasury management interface
 */
interface INekoTreasury {
    // =============================================================================
    // EVENTS
    // =============================================================================
    event TreasuryUpdated(
        string indexed walletType,
        address indexed oldAddress,
        address indexed newAddress
    );
    event ContractUpdated(
        string indexed contractType,
        address indexed oldAddress,
        address indexed newAddress
    );
    event FundsDeposited(
        address indexed token,
        uint256 amount,
        string indexed source
    );
    event FundsWithdrawn(
        address indexed token,
        uint256 amount,
        address indexed to,
        string indexed purpose
    );
    event RewardsDistributed(
        address indexed token,
        uint256 amount,
        address indexed to,
        string indexed rewardType
    );
    event EmergencyModeToggled(bool enabled);
    event WithdrawalsPaused(bool paused);

    // =============================================================================
    // REWARD POOL MANAGEMENT
    // =============================================================================
    function setFeedingRewardPool(address newPool) external;
    function setEcosystemRewardPool(address newPool) external;

    // =============================================================================
    // CONTRACT MANAGEMENT
    // =============================================================================
    function setNekoToken(address _nekoToken) external;
    function setStakingContract(address _stakingContract) external;
    function setNFTContract(address _nftContract) external;
    function setFoodContract(address _foodContract) external;
    function setICOContract(address _icoContract) external;
    function setEcosystemRewardContract(
        address _ecosystemRewardContract
    ) external;

    // =============================================================================
    // FUND MANAGEMENT
    // =============================================================================
    function depositFunds(
        address token,
        uint256 amount,
        string calldata source
    ) external payable;
    function withdrawFunds(
        address token,
        uint256 amount,
        address to,
        string calldata purpose
    ) external;
    function distributeRewards(
        address token,
        uint256 amount,
        string calldata rewardType
    ) external;

    // =============================================================================
    // EMERGENCY FUNCTIONS
    // =============================================================================
    function toggleEmergencyMode() external;
    function toggleWithdrawalsPause() external;
    function emergencyWithdrawAll(address token) external;

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================
    function getTreasuryBalance(address token) external view returns (uint256);
    function getRewardPoolAddresses()
        external
        view
        returns (address _feedingRewardPool, address _ecosystemRewardPool);
    function getContractAddresses()
        external
        view
        returns (
            address _nekoToken,
            address _stakingContract,
            address _nftContract,
            address _foodContract,
            address _icoContract,
            address _ecosystemRewardContract
        );
    function getTreasuryStats()
        external
        view
        returns (
            uint256 _totalDeposits,
            uint256 _totalWithdrawals,
            uint256 _totalRewardsDistributed,
            bool _emergencyMode,
            bool _withdrawalsPaused
        );

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================
    function feedingRewardPool() external view returns (address);
    function ecosystemRewardPool() external view returns (address);
    function nekoToken() external view returns (address);
    function stakingContract() external view returns (address);
    function nftContract() external view returns (address);
    function foodContract() external view returns (address);
    function icoContract() external view returns (address);
    function ecosystemRewardContract() external view returns (address);
    function emergencyMode() external view returns (bool);
    function withdrawalsPaused() external view returns (bool);
}
