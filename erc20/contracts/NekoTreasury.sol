// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title NekoTreasury
 * @dev Centralized treasury management for the entire Neko ecosystem
 * @notice Manages all treasury functions, reward pools, and fund distributions
 */
contract NekoTreasury is Ownable, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    // =============================================================================
    // ROLES
    // =============================================================================
    bytes32 public constant TREASURY_MANAGER_ROLE =
        keccak256("TREASURY_MANAGER_ROLE");
    bytes32 public constant REWARD_MANAGER_ROLE =
        keccak256("REWARD_MANAGER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================

    // Contract addresses
    address public nekoToken;
    address public stakingContract;
    address public icoContract;

    // Emergency controls
    bool public emergencyMode = false;
    bool public withdrawalsPaused = false;

    // Statistics
    uint256 public totalDeposits;
    uint256 public totalWithdrawals;
    uint256 public totalRewardsDistributed;

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
    // CUSTOM ERRORS
    // =============================================================================
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientBalance();
    error UnauthorizedAccess();
    error EmergencyModeActive();
    error WithdrawalsPausedError();
    error ContractNotSet();

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================
    constructor(address initialOwner) Ownable(initialOwner) {
        if (initialOwner == address(0)) revert InvalidAddress();

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(TREASURY_MANAGER_ROLE, initialOwner);
        _grantRole(REWARD_MANAGER_ROLE, initialOwner);
        _grantRole(EMERGENCY_ROLE, initialOwner);
    }

    // =============================================================================
    // MODIFIERS
    // =============================================================================
    modifier onlyTreasuryManager() {
        if (!hasRole(TREASURY_MANAGER_ROLE, msg.sender))
            revert UnauthorizedAccess();
        _;
    }

    modifier onlyRewardManager() {
        if (!hasRole(REWARD_MANAGER_ROLE, msg.sender))
            revert UnauthorizedAccess();
        _;
    }

    modifier onlyEmergencyRole() {
        if (!hasRole(EMERGENCY_ROLE, msg.sender)) revert UnauthorizedAccess();
        _;
    }

    modifier whenNotEmergency() {
        if (emergencyMode) revert EmergencyModeActive();
        _;
    }

    modifier whenWithdrawalsNotPaused() {
        if (withdrawalsPaused) revert WithdrawalsPausedError();
        _;
    }

    // =============================================================================
    // CONTRACT MANAGEMENT
    // =============================================================================

    /**
     * @dev Set NekoToken contract
     */
    function setNekoToken(address _nekoToken) external onlyOwner {
        if (_nekoToken == address(0)) revert InvalidAddress();

        address oldContract = nekoToken;
        nekoToken = _nekoToken;

        emit ContractUpdated("NEKO_TOKEN", oldContract, _nekoToken);
    }

    /**
     * @dev Set staking contract
     */
    function setStakingContract(address _stakingContract) external onlyOwner {
        if (_stakingContract == address(0)) revert InvalidAddress();

        address oldContract = stakingContract;
        stakingContract = _stakingContract;

        emit ContractUpdated("STAKING_CONTRACT", oldContract, _stakingContract);
    }

    /**
     * @dev Set ICO contract
     */
    function setICOContract(address _icoContract) external onlyOwner {
        if (_icoContract == address(0)) revert InvalidAddress();

        address oldContract = icoContract;
        icoContract = _icoContract;

        emit ContractUpdated("ICO_CONTRACT", oldContract, _icoContract);
    }

    // =============================================================================
    // FUND MANAGEMENT
    // =============================================================================

    /**
     * @dev Deposit funds to treasury
     */
    function depositFunds(
        address token,
        uint256 amount,
        string calldata source
    ) external payable nonReentrant whenNotEmergency {
        if (amount == 0) revert InvalidAmount();

        if (token == address(0)) {
            // ETH deposit
            if (msg.value != amount) revert InvalidAmount();
            totalDeposits += amount;
        } else {
            // ERC20 deposit
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            totalDeposits += amount;
        }

        emit FundsDeposited(token, amount, source);
    }

    /**
     * @dev Withdraw funds from treasury
     */
    function withdrawFunds(
        address token,
        uint256 amount,
        address to,
        string calldata purpose
    )
        external
        onlyTreasuryManager
        nonReentrant
        whenNotEmergency
        whenWithdrawalsNotPaused
    {
        if (amount == 0) revert InvalidAmount();
        if (to == address(0)) revert InvalidAddress();

        if (token == address(0)) {
            // ETH withdrawal
            if (address(this).balance < amount) revert InsufficientBalance();
            (bool success, ) = to.call{value: amount}("");
            if (!success) revert("ETH transfer failed");
        } else {
            // ERC20 withdrawal
            IERC20(token).safeTransfer(to, amount);
        }

        totalWithdrawals += amount;
        emit FundsWithdrawn(token, amount, to, purpose);
    }

    // =============================================================================
    // EMERGENCY FUNCTIONS
    // =============================================================================

    /**
     * @dev Toggle emergency mode
     */
    function toggleEmergencyMode() external onlyEmergencyRole {
        emergencyMode = !emergencyMode;
        emit EmergencyModeToggled(emergencyMode);
    }

    /**
     * @dev Pause/unpause withdrawals
     */
    function toggleWithdrawalsPause() external onlyEmergencyRole {
        withdrawalsPaused = !withdrawalsPaused;
        emit WithdrawalsPaused(withdrawalsPaused);
    }

    /**
     * @dev Emergency withdraw all funds
     */
    function emergencyWithdrawAll(address token) external onlyEmergencyRole {
        if (token == address(0)) {
            // ETH
            uint256 balance = address(this).balance;
            if (balance > 0) {
                (bool success, ) = owner().call{value: balance}("");
                if (!success) revert("ETH transfer failed");
            }
        } else {
            // ERC20
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                IERC20(token).safeTransfer(owner(), balance);
            }
        }
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================

    /**
     * @dev Get treasury balance
     */
    function getTreasuryBalance(address token) external view returns (uint256) {
        if (token == address(0)) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    /**
     * @dev Get all contract addresses
     */
    function getContractAddresses()
        external
        view
        returns (
            address _nekoToken,
            address _stakingContract,
            address _icoContract
        )
    {
        return (nekoToken, stakingContract, icoContract);
    }

    /**
     * @dev Get treasury statistics
     */
    function getTreasuryStats()
        external
        view
        returns (
            uint256 _totalDeposits,
            uint256 _totalWithdrawals,
            uint256 _totalRewardsDistributed,
            bool _emergencyMode,
            bool _withdrawalsPaused
        )
    {
        return (
            totalDeposits,
            totalWithdrawals,
            totalRewardsDistributed,
            emergencyMode,
            withdrawalsPaused
        );
    }

    // =============================================================================
    // RECEIVE FUNCTION
    // =============================================================================

    receive() external payable {
        totalDeposits += msg.value;
        emit FundsDeposited(address(0), msg.value, "RECEIVE");
    }
}
