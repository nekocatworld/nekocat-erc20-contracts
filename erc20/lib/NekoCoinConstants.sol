// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NekoCoinConstants
 * @dev Constants for NEKO Coin contract system
 */
library NekoCoinConstants {
    // =============================================================================
    // TOKEN CONSTANTS
    // =============================================================================
    uint256 public constant MAX_SUPPLY = 777_777_777_777 * 10 ** 18; // 777 billion tokens
    uint8 public constant DECIMALS = 18;
    string public constant NAME = "NEKO Coin";
    string public constant SYMBOL = "NEKO";

    // =============================================================================
    // ROLE CONSTANTS
    // =============================================================================
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant TAX_MANAGER_ROLE = keccak256("TAX_MANAGER_ROLE");

    // =============================================================================
    // TAX SYSTEM CONSTANTS
    // =============================================================================
    uint256 public constant MAX_TAX_RATE = 1000; // 10% maximum tax rate (in basis points)
    uint256 public constant DEFAULT_TAX_RATE = 300; // 3% default tax rate (in basis points)
    uint256 public constant BASIS_POINTS = 10000; // 100% in basis points

    // =============================================================================
    // ICO CONSTANTS
    // =============================================================================
    uint256 public constant MAX_BATCH_SIZE = 100;

    // =============================================================================
    // MEV PROTECTION CONSTANTS
    // =============================================================================
    uint256 public constant MEV_PROTECTION_BLOCKS = 3;
    uint256 public constant FRONT_RUN_PROTECTION_DELAY = 12; // blocks

    // =============================================================================
    // STAKING CONSTANTS
    // =============================================================================
    uint256 public constant MIN_STAKING_AMOUNT = 1000 * 10 ** 18; // 1,000 NEKO minimum
    uint256 public constant MAX_STAKING_AMOUNT = 1000000000 * 10 ** 18; // 1B NEKO maximum
    uint256 public constant MAX_REWARD_RATE = 50000; // 500% APY maximum
    uint256 public constant MAX_PENALTY_RATE = 5000; // 50% penalty maximum
    uint256 public constant STAKING_PRECISION = 10 ** 18; // Precision for calculations

    // Default staking pool durations
    uint256 public constant FLEXIBLE_DURATION = 30 days;
    uint256 public constant STANDARD_DURATION = 90 days;
    uint256 public constant PREMIUM_DURATION = 180 days;

    // Default reward rates (basis points) - Updated after staking changes
    uint256 public constant FLEXIBLE_REWARD_RATE = 500; // 5% APY
    uint256 public constant STANDARD_REWARD_RATE = 1200; // 12% APY
    uint256 public constant PREMIUM_REWARD_RATE = 1600; // 16% APY (reduced from 25%)
}
