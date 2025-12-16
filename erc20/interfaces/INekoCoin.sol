// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title INekoCoin
 * @dev Interface for NEKO Coin ERC20 Token with DEX Transfer Tax
 */
interface INekoCoin is IERC20, IERC20Metadata, IAccessControl {
    // =============================================================================
    // EVENTS
    // =============================================================================
    event TokensBurned(address indexed from, uint256 amount);
    event EmergencyWithdraw(address indexed token, uint256 amount);
    event TaxRateUpdated(uint256 oldRate, uint256 newRate);
    event TaxCollectorUpdated(
        address indexed oldCollector,
        address indexed newCollector
    );
    event TaxToggled(bool enabled);
    event TaxCollected(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 taxAmount
    );
    event TimelockScheduled(bytes32 indexed requestId, uint256 executeTime);
    event TimelockExecuted(bytes32 indexed requestId);

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================
    function burningEnabled() external view returns (bool);
    function pausingEnabled() external view returns (bool);
    function maxTransactionAmount() external view returns (uint256);
    function taxRate() external view returns (uint256);
    function taxCollector() external view returns (address);
    function taxEnabled() external view returns (bool);
    function taxWhitelist(address account) external view returns (bool);
    function treasury() external view returns (address);
    function marketing() external view returns (address);
    function team() external view returns (address);
    function dev() external view returns (address);

    // =============================================================================
    // BURNING FUNCTIONS
    // =============================================================================
    function burnFrom(address from, uint256 amount) external;
    function batchBurnFrom(
        address[] calldata froms,
        uint256[] calldata amounts
    ) external;

    // =============================================================================
    // PAUSING FUNCTIONS
    // =============================================================================
    function pause() external;
    function unpause() external;

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================
    function emergencyWithdraw(address token, uint256 amount) external;

    // =============================================================================
    // TAX MANAGEMENT FUNCTIONS
    // =============================================================================
    function updateTaxRate(uint256 newRate) external;
    function updateTaxCollector(address newCollector) external;
    function toggleTax() external;
    function setTaxParameters(
        uint256 newRate,
        address newCollector,
        bool enabled
    ) external;
    function addToTaxWhitelist(address[] calldata accounts) external;
    function removeFromTaxWhitelist(address[] calldata accounts) external;
    function isWhitelistedFromTax(address account) external view returns (bool);

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================
    function getContractConfig()
        external
        view
        returns (
            bool _burningEnabled,
            bool _pausingEnabled,
            uint256 _maxTransactionAmount,
            uint256 _maxSupply
        );

    function getTaxConfig()
        external
        view
        returns (
            uint256 _taxRate,
            address _taxCollector,
            bool _taxEnabled,
            uint256 _maxTaxRate,
            uint256 _basisPoints
        );

    function calculateTax(
        uint256 amount
    ) external view returns (uint256 taxAmount, uint256 netAmount);
}
