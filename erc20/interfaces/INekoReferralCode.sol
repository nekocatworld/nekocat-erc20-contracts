// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title INekoReferralCode
 * @dev Interface for NekoReferralCode contract
 */
interface INekoReferralCode {
    // ============ Events ============
    event ReferralCodeSet(
        address indexed user,
        string indexed code,
        uint256 timestamp
    );

    event ReferralCodeUpdated(
        address indexed user,
        string indexed oldCode,
        string indexed newCode,
        uint256 timestamp
    );

    event CodeCounterUpdated(uint256 newCounter);

    // ============ Errors ============
    error CodeAlreadyExists(string code);
    error CodeTooShort();
    error CodeTooLong();
    error InvalidCodeFormat();
    error AddressAlreadyHasCode();
    error CodeNotFound();
    error MaxCodesReached();
    error InvalidCode();

    // ============ Functions ============
    function setReferralCode(string memory code) external;
    function generateReferralCode() external;
    function updateReferralCode(address user, string memory newCode) external;
    function getAddressFromCode(
        string memory code
    ) external view returns (address);
    function getCodeFromAddress(
        address user
    ) external view returns (string memory);
    function codeExists(string memory code) external view returns (bool);
    function addressHasCode(address user) external view returns (bool);
    function getCodeCounter() external view returns (uint256);
    function getTotalCodesGenerated() external view returns (uint256);
    function setCodeCounter(uint256 newCounter) external;
    function pause() external;
    function unpause() external;

    // ============ State Variables ============
    function codeToAddress(string memory code) external view returns (address);
    function addressToCode(address user) external view returns (string memory);
    function hasReferralCode(address user) external view returns (bool);
    function isCodeTaken(string memory code) external view returns (bool);
    function MAX_CODES() external view returns (uint256);
}
