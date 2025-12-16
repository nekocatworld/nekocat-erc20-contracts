// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NekoCoinErrors
 * @dev Custom errors for NEKO Coin contract system
 */
library NekoCoinErrors {
    // =============================================================================
    // GENERAL ERRORS
    // =============================================================================
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientBalance();
    error TransferNotAllowed();
    error MaxSupplyExceeded();
    error InvalidRole();
    error TransferFailed();

    // =============================================================================
    // FEATURE ERRORS
    // =============================================================================
    error BurningDisabled();
    error PausingDisabled();

    // =============================================================================
    // TAX SYSTEM ERRORS
    // =============================================================================
    error TaxRateExceeded();
    error InvalidTaxRate();

    // =============================================================================
    // TIMELOCK ERRORS
    // =============================================================================
    error TimelockActive();

    // =============================================================================
    // ICO ERRORS
    // =============================================================================
    error InvalidStage();
    error StageNotActive();
    error StageSoldOut();
    error BelowMinPurchase();
    error AboveMaxPurchase();
    error NotWhitelisted();
    error StageAlreadyStarted();
    error NoTokensToWithdraw();
    error NothingToClaim();

    // =============================================================================
    // VESTING ERRORS
    // =============================================================================
    error NoVestingSchedule();
    error VestingAlreadyRevoked();
    error VestingNotRevocable();
    error InvalidDuration();

    // =============================================================================
    // MEV PROTECTION ERRORS
    // =============================================================================
    error FrontRunProtectionActive();
    error MEVProtectionActive();
    error BlockDelayRequired();
}
