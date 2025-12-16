// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/INekoCoin.sol";
import "../lib/NekoCoinErrors.sol";
import "../interfaces/INekoTreasury.sol";

/**
 * @title NekoCoin
 * @dev NEKO Coin ERC20 Token with RBAC, Pausable, Burnable, ReentrancyGuard, and DEX Transfer Tax
 *
 * Features:
 * - ERC20 standard compliance
 * - Role-based access control (RBAC)
 * - Pausable functionality
 * - Burnable tokens
 * - Reentrancy protection
 * - DEX transfer tax system (3% default, max 10%)
 * - Custom errors for gas efficiency
 * - Packed storage optimization
 * - Immutable references
 * - Fixed supply (no minting after deployment)
 *
 * Roles:
 * - DEFAULT_ADMIN_ROLE: Full administrative control
 * - PAUSER_ROLE: Can pause/unpause the contract
 * - TAX_MANAGER_ROLE: Can manage tax settings
 *
 * Security:
 * - ReentrancyGuard prevents reentrancy attacks
 * - Pausable allows emergency stops
 * - AccessControl provides granular permissions
 * - Custom errors reduce gas costs
 * - Packed storage optimizes gas usage
 * - Tax system with configurable rates and limits
 * - No minting capability after deployment
 */
contract NekoCoin is
    ERC20,
    ERC20Pausable,
    ERC20Burnable,
    AccessControl,
    Ownable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    // =============================================================================
    // CUSTOM ERRORS (Gas Efficient)
    // =============================================================================
    error InvalidAmount();
    error InsufficientBalance();
    error TransferNotAllowed();
    error BurningDisabled();
    error PausingDisabled();
    error MaxSupplyExceeded();
    error InvalidRole();
    error TaxRateExceeded();
    error InvalidTaxRate();
    error TransferFailed();
    error TimelockActive();

    // =============================================================================
    // CONSTANTS & IMMUTABLES
    // =============================================================================
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant TAX_MANAGER_ROLE = keccak256("TAX_MANAGER_ROLE");

    uint256 public constant MAX_SUPPLY = 777_777_777_777 * 10 ** 18; // 777 billion tokens
    uint256 public constant MAX_TAX_RATE = 1000; // 10% maximum tax rate (in basis points)
    uint256 public constant DEFAULT_TAX_RATE = 300; // 3% default tax rate (in basis points)
    uint256 public constant BASIS_POINTS = 10000; // 100% in basis points

    // =============================================================================
    // STATE VARIABLES (Packed for Gas Optimization)
    // =============================================================================
    bool public immutable burningEnabled;
    bool public immutable pausingEnabled;

    uint256 public immutable maxTransactionAmount;

    // Tax system variables
    uint256 public taxRate; // Tax rate in basis points (300 = 3%)
    address public taxCollector; // Address that receives tax fees
    bool public taxEnabled; // Whether tax is enabled
    mapping(address => bool) public taxWhitelist; // Addresses exempt from tax

    // Timelock system
    mapping(bytes32 => uint256) public timelockRequests;

    // =============================================================================
    // EVENTS
    // =============================================================================
    event TokensMinted(address indexed to, uint256 amount);
    event MaxTransactionAmountUpdated(uint256 newAmount);
    event EmergencyWithdraw(address indexed token, uint256 amount);
    event TaxRateUpdated(uint256 oldRate, uint256 newRate);
    event TaxCollectorUpdated(
        address indexed oldCollector,
        address indexed newCollector
    );
    event TaxToggled(bool enabled);
    event TaxWhitelistUpdated(address indexed account, bool indexed status);
    event TaxCollected(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 taxAmount
    );
    event TimelockScheduled(bytes32 indexed requestId, uint256 executeTime);
    event TimelockExecuted(bytes32 indexed requestId);
    event TimelockCancelled(bytes32 indexed requestId);
    event TokensBurned(address indexed account, uint256 amount);
    event AdminTokensBurned(
        address indexed account,
        uint256 amount,
        address indexed admin
    );

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================
    constructor(
        string memory name,
        string memory symbol,
        uint8 /* decimals */, // ERC20 uses fixed 18 decimals
        uint256 totalSupply,
        address initialOwner
    ) ERC20(name, symbol) Ownable(initialOwner) {
        if (initialOwner == address(0)) revert NekoCoinErrors.InvalidAddress();
        if (totalSupply > MAX_SUPPLY) revert MaxSupplyExceeded();

        // Set immutable values
        burningEnabled = true;
        pausingEnabled = true;
        maxTransactionAmount = type(uint256).max; // No transfer limit

        // Initialize tax system
        taxRate = DEFAULT_TAX_RATE; // 3% default tax
        taxCollector = initialOwner; // Admin receives tax fees
        taxEnabled = true; // Tax enabled by default

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(PAUSER_ROLE, initialOwner);
        _grantRole(TAX_MANAGER_ROLE, initialOwner);

        // Mint initial supply to owner
        _mint(initialOwner, totalSupply);
    }

    // =============================================================================
    // MODIFIERS
    // =============================================================================
    modifier onlyValidAddress(address account) {
        if (account == address(0)) revert NekoCoinErrors.InvalidAddress();
        _;
    }

    modifier onlyValidAmount(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
        _;
    }

    modifier onlyBurningEnabled() {
        if (!burningEnabled) revert BurningDisabled();
        _;
    }

    modifier onlyPausingEnabled() {
        if (!pausingEnabled) revert PausingDisabled();
        _;
    }

    modifier onlyWithinLimits(uint256 amount) {
        if (amount > maxTransactionAmount) revert InvalidAmount();
        _;
    }

    // =============================================================================
    // ERC20 OVERRIDES
    // =============================================================================
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable) nonReentrant {
        bool shouldTax = from != address(0) &&
            to != address(0) &&
            taxEnabled &&
            taxRate > 0 &&
            !taxWhitelist[from] &&
            !taxWhitelist[to];

        if (shouldTax) {
            uint256 taxAmount = (value * taxRate) / BASIS_POINTS;
            uint256 transferAmount = value - taxAmount;

            super._update(from, to, transferAmount);

            if (taxAmount > 0) {
                super._update(from, taxCollector, taxAmount);
                emit TaxCollected(from, to, value, taxAmount);
            }
        } else {
            super._update(from, to, value);
        }
    }

    // =============================================================================
    // BURNING FUNCTIONS
    // =============================================================================
    function burnFrom(
        address from,
        uint256 amount
    )
        public
        override
        onlyBurningEnabled
        onlyValidAddress(from)
        onlyValidAmount(amount)
        nonReentrant
    {
        if (msg.sender == from) {
            if (balanceOf(from) < amount) revert InsufficientBalance();
            _burn(from, amount);
            emit TokensBurned(from, amount);
        } else {
            revert InvalidRole();
        }
    }

    // =============================================================================
    // PAUSING FUNCTIONS
    // =============================================================================
    /**
     * @dev Pause the contract with timelock protection
     */
    function pause()
        external
        onlyRole(PAUSER_ROLE)
        onlyPausingEnabled
        nonReentrant
    {
        bytes32 requestId = keccak256(abi.encodePacked("pause", msg.sender));

        if (timelockRequests[requestId] == 0) {
            timelockRequests[requestId] = block.timestamp + 24 hours;
            emit TimelockScheduled(requestId, timelockRequests[requestId]);
            return;
        }

        if (block.timestamp < timelockRequests[requestId])
            revert TimelockActive();

        _pause();
        delete timelockRequests[requestId];
        emit TimelockExecuted(requestId);
    }

    /**
     * @dev Unpause the contract
     */
    function unpause()
        external
        onlyRole(PAUSER_ROLE)
        onlyPausingEnabled
        nonReentrant
    {
        _unpause();
    }

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================
    /**
     * @dev Emergency withdraw function for stuck tokens
     * @param token Token address to withdraw (address(0) for ETH)
     * @param amount Amount to withdraw
     * @notice Requires 24-hour timelock for security
     */
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        // Create unique timelock ID
        bytes32 timelockId = keccak256(
            abi.encodePacked(
                "emergencyWithdraw",
                token,
                amount,
                block.timestamp
            )
        );

        // Check if timelock exists
        if (timelockRequests[timelockId] == 0) {
            // Schedule timelock
            timelockRequests[timelockId] = block.timestamp + 24 hours;
            emit TimelockScheduled(timelockId, timelockRequests[timelockId]);
            return;
        }

        // Verify timelock has passed
        require(
            block.timestamp >= timelockRequests[timelockId],
            "Timelock not expired"
        );

        // Clear timelock
        delete timelockRequests[timelockId];
        if (token == address(0)) {
            if (address(this).balance < amount) revert InsufficientBalance();
            (bool success, ) = owner().call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }

        emit EmergencyWithdraw(token, amount);
    }

    // =============================================================================
    // TAX MANAGEMENT FUNCTIONS
    // =============================================================================
    /**
     * @dev Update tax rate
     * @param newRate New tax rate in basis points (300 = 3%)
     */
    function updateTaxRate(
        uint256 newRate
    ) external onlyRole(TAX_MANAGER_ROLE) nonReentrant {
        if (newRate > MAX_TAX_RATE) revert TaxRateExceeded();

        bytes32 requestId = keccak256(
            abi.encodePacked("updateTaxRate", newRate, msg.sender)
        );

        if (timelockRequests[requestId] == 0) {
            timelockRequests[requestId] = block.timestamp + 24 hours;
            emit TimelockScheduled(requestId, timelockRequests[requestId]);
            return;
        }

        if (block.timestamp < timelockRequests[requestId])
            revert TimelockActive();

        uint256 oldRate = taxRate;
        taxRate = newRate;
        delete timelockRequests[requestId];

        emit TimelockExecuted(requestId);
        emit TaxRateUpdated(oldRate, newRate);
    }

    /**
     * @dev Update tax collector address
     * @param newCollector New address to receive tax fees
     */
    function updateTaxCollector(
        address newCollector
    )
        external
        onlyRole(TAX_MANAGER_ROLE)
        onlyValidAddress(newCollector)
        nonReentrant
    {
        address oldCollector = taxCollector;
        taxCollector = newCollector;

        emit TaxCollectorUpdated(oldCollector, newCollector);
    }

    /**
     * @dev Toggle tax on/off (no parameters - toggles current state)
     */
    function toggleTax() external onlyRole(TAX_MANAGER_ROLE) nonReentrant {
        taxEnabled = !taxEnabled;
        emit TaxToggled(taxEnabled);
    }

    /**
     * @dev Set tax parameters in one transaction
     * @param newRate New tax rate in basis points
     * @param newCollector New tax collector address
     * @param enabled Whether tax is enabled
     */
    function setTaxParameters(
        uint256 newRate,
        address newCollector,
        bool enabled
    )
        external
        onlyRole(TAX_MANAGER_ROLE)
        onlyValidAddress(newCollector)
        nonReentrant
    {
        if (newRate > MAX_TAX_RATE) revert TaxRateExceeded();

        uint256 oldRate = taxRate;
        address oldCollector = taxCollector;

        taxRate = newRate;
        taxCollector = newCollector;
        taxEnabled = enabled;

        emit TaxRateUpdated(oldRate, newRate);
        emit TaxCollectorUpdated(oldCollector, newCollector);
        emit TaxToggled(enabled);
    }

    /**
     * @dev Add addresses to tax whitelist
     * @param accounts Array of addresses to whitelist
     */
    function addToTaxWhitelist(
        address[] calldata accounts
    ) external onlyRole(TAX_MANAGER_ROLE) nonReentrant {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == address(0))
                revert NekoCoinErrors.InvalidAddress();
            taxWhitelist[accounts[i]] = true;
            emit TaxWhitelistUpdated(accounts[i], true);
        }
    }

    /**
     * @dev Remove addresses from tax whitelist
     * @param accounts Array of addresses to remove from whitelist
     */
    function removeFromTaxWhitelist(
        address[] calldata accounts
    ) external onlyRole(TAX_MANAGER_ROLE) nonReentrant {
        for (uint256 i = 0; i < accounts.length; i++) {
            taxWhitelist[accounts[i]] = false;
            emit TaxWhitelistUpdated(accounts[i], false);
        }
    }

    /**
     * @dev Check if address is whitelisted from tax
     * @param account Address to check
     */
    function isWhitelistedFromTax(
        address account
    ) external view returns (bool) {
        return taxWhitelist[account];
    }

    // =============================================================================
    // ROLE MANAGEMENT FUNCTIONS
    // =============================================================================

    /**
     * @dev Grant role to address (admin only)
     */
    function grantRole(
        bytes32 role,
        address account
    ) public override onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(role, account);
        emit RoleGranted(role, account, msg.sender);
    }

    /**
     * @dev Revoke role from address (admin only)
     */
    function revokeRole(
        bytes32 role,
        address account
    ) public override onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(role, account);
        emit RoleRevoked(role, account, msg.sender);
    }

    /**
     * @dev Renounce role (user can renounce their own roles)
     */
    function renounceRole(
        bytes32 role,
        address callerConfirmation
    ) public override {
        require(
            callerConfirmation == msg.sender,
            "Can only renounce own roles"
        );
        _revokeRole(role, callerConfirmation);
        emit RoleRevoked(role, callerConfirmation, msg.sender);
    }

    // =============================================================================
    // BURNING FUNCTIONS
    // =============================================================================

    /**
     * @dev Allow users to burn their own tokens
     */
    function burn(uint256 amount) public override {
        require(amount > 0, "Amount must be > 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _burn(msg.sender, amount);
        emit TokensBurned(msg.sender, amount);
    }

    /**
     * @dev Admin can burn any amount of tokens from any address
     */
    function adminBurn(
        address account,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount > 0, "Amount must be > 0");
        require(balanceOf(account) >= amount, "Insufficient balance");

        _burn(account, amount);
        emit AdminTokensBurned(account, amount, msg.sender);
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================
    /**
     * @dev Get contract configuration
     */
    function getContractConfig()
        external
        view
        returns (
            bool _burningEnabled,
            bool _pausingEnabled,
            uint256 _maxTransactionAmount,
            uint256 _maxSupply
        )
    {
        return (
            burningEnabled,
            pausingEnabled,
            maxTransactionAmount,
            MAX_SUPPLY
        );
    }

    /**
     * @dev Get tax configuration
     */
    function getTaxConfig()
        external
        view
        returns (
            uint256 _taxRate,
            address _taxCollector,
            bool _taxEnabled,
            uint256 _maxTaxRate,
            uint256 _basisPoints
        )
    {
        return (taxRate, taxCollector, taxEnabled, MAX_TAX_RATE, BASIS_POINTS);
    }

    /**
     * @dev Calculate tax amount for a given transfer amount
     * @param amount Transfer amount
     * @return taxAmount Tax amount to be deducted
     * @return netAmount Net amount after tax
     */
    function calculateTax(
        uint256 amount
    ) external view returns (uint256 taxAmount, uint256 netAmount) {
        if (!taxEnabled || taxRate == 0) {
            return (0, amount);
        }

        taxAmount = (amount * taxRate) / BASIS_POINTS;
        netAmount = amount - taxAmount;
    }

    /**
     * @dev Check if address has specific role
     */
    function hasRole(
        bytes32 role,
        address account
    ) public view override returns (bool) {
        return super.hasRole(role, account);
    }

    // =============================================================================
    // INTERFACE SUPPORT
    // =============================================================================
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // =============================================================================
    // FALLBACK FUNCTIONS
    // =============================================================================
    /**
     * @dev Reject direct ETH transfers
     */
    receive() external payable {
        revert("Direct ETH not accepted");
    }

    /**
     * @dev Reject calls to non-existent functions
     */
    fallback() external payable {
        revert("Function does not exist");
    }
}
