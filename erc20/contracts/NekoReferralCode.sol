// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title NekoReferralCode
 * @dev Simple, secure, and scalable referral code generator
 * @notice Users can set their own referral codes for free (only gas fee)
 * Format: NEKO + 9-digit unique code (e.g., NEKO123456789)
 */
contract NekoReferralCode is Ownable, ReentrancyGuard, Pausable {
    // ============ State Variables ============

    // Mapping from referral code to wallet address
    mapping(string => address) public codeToAddress;

    // Mapping from wallet address to referral code
    mapping(address => string) public addressToCode;

    // Mapping to check if address has a referral code
    mapping(address => bool) public hasReferralCode;

    // Mapping to check if code is already taken
    mapping(string => bool) public isCodeTaken;

    // Counter for generating unique codes
    uint256 private _codeCounter = 100000000; // Start from 100000000 (9 digits)

    // Maximum number of codes that can be generated
    uint256 public constant MAX_CODES = 999999999; // Up to 999999999 (9 digits)

    // Random seed for code generation
    uint256 private _randomSeed = 0;

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

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ Public Functions ============

    /**
     * @dev Set a custom referral code for the caller
     * @param code The referral code to set (must start with NEKO and be 9 digits)
     */
    function setReferralCode(
        string memory code
    ) external nonReentrant whenNotPaused {
        _validateCode(code);

        if (hasReferralCode[msg.sender]) {
            revert AddressAlreadyHasCode();
        }

        if (isCodeTaken[code]) {
            revert CodeAlreadyExists(code);
        }

        // Set the mappings
        codeToAddress[code] = msg.sender;
        addressToCode[msg.sender] = code;
        hasReferralCode[msg.sender] = true;
        isCodeTaken[code] = true;

        emit ReferralCodeSet(msg.sender, code, block.timestamp);
    }

    /**
     * @dev Generate a unique referral code automatically for the caller
     */
    function generateReferralCode() external nonReentrant whenNotPaused {
        if (hasReferralCode[msg.sender]) {
            revert AddressAlreadyHasCode();
        }

        if (_codeCounter > MAX_CODES) {
            revert MaxCodesReached();
        }

        // Generate random 9-digit code
        string memory code = _generateRandomCode();

        // Ensure code is unique
        uint256 attempts = 0;
        while (isCodeTaken[code]) {
            code = _generateRandomCode();
            attempts++;
            if (attempts > 100) {
                // Prevent infinite loop
                revert MaxCodesReached();
            }
        }

        // Set the mappings
        codeToAddress[code] = msg.sender;
        addressToCode[msg.sender] = code;
        hasReferralCode[msg.sender] = true;
        isCodeTaken[code] = true;

        emit ReferralCodeSet(msg.sender, code, block.timestamp);

        // Increment counter for tracking
        _codeCounter++;
    }

    /**
     * @dev Update existing referral code (admin only for security)
     * @param user The user whose code to update
     * @param newCode The new referral code
     */
    function updateReferralCode(
        address user,
        string memory newCode
    ) external onlyOwner {
        if (!hasReferralCode[user]) {
            revert CodeNotFound();
        }

        _validateCode(newCode);

        if (isCodeTaken[newCode]) {
            revert CodeAlreadyExists(newCode);
        }

        string memory oldCode = addressToCode[user];

        // Remove old code
        delete codeToAddress[oldCode];
        isCodeTaken[oldCode] = false;

        // Set new code
        codeToAddress[newCode] = user;
        addressToCode[user] = newCode;
        isCodeTaken[newCode] = true;

        emit ReferralCodeUpdated(user, oldCode, newCode, block.timestamp);
    }

    // ============ View Functions ============

    /**
     * @dev Get wallet address from referral code
     * @param code The referral code
     * @return The wallet address associated with the code
     */
    function getAddressFromCode(
        string memory code
    ) external view returns (address) {
        return codeToAddress[code];
    }

    /**
     * @dev Get referral code from wallet address
     * @param user The wallet address
     * @return The referral code associated with the address
     */
    function getCodeFromAddress(
        address user
    ) external view returns (string memory) {
        return addressToCode[user];
    }

    /**
     * @dev Check if a referral code exists
     * @param code The referral code to check
     * @return True if code exists, false otherwise
     */
    function codeExists(string memory code) external view returns (bool) {
        return codeToAddress[code] != address(0);
    }

    /**
     * @dev Check if an address has a referral code
     * @param user The wallet address to check
     * @return True if address has a code, false otherwise
     */
    function addressHasCode(address user) external view returns (bool) {
        return hasReferralCode[user];
    }

    /**
     * @dev Get current code counter
     * @return The current counter value
     */
    function getCodeCounter() external view returns (uint256) {
        return _codeCounter;
    }

    /**
     * @dev Get total number of codes generated
     * @return The total number of codes generated
     */
    function getTotalCodesGenerated() external view returns (uint256) {
        return _codeCounter - 100000000;
    }

    // ============ Admin Functions ============

    /**
     * @dev Set code counter (admin only)
     * @param newCounter The new counter value
     */
    function setCodeCounter(uint256 newCounter) external onlyOwner {
        require(
            newCounter >= 100000000 && newCounter <= MAX_CODES,
            "Invalid counter"
        );
        _codeCounter = newCounter;
        emit CodeCounterUpdated(newCounter);
    }

    /**
     * @dev Pause the contract (admin only)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract (admin only)
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ Internal Functions ============

    /**
     * @dev Validate referral code format
     * @param code The code to validate
     */
    function _validateCode(string memory code) internal pure {
        bytes memory codeBytes = bytes(code);

        // Check minimum length (NEKO + 9 digits = 13 characters)
        if (codeBytes.length < 13) {
            revert CodeTooShort();
        }

        // Check maximum length
        if (codeBytes.length > 13) {
            revert CodeTooLong();
        }

        // Check if starts with NEKO
        if (codeBytes.length >= 4) {
            if (
                codeBytes[0] != "N" ||
                codeBytes[1] != "E" ||
                codeBytes[2] != "K" ||
                codeBytes[3] != "O"
            ) {
                revert InvalidCodeFormat();
            }
        }

        // Check if remaining characters are digits
        for (uint256 i = 4; i < codeBytes.length; i++) {
            if (codeBytes[i] < "0" || codeBytes[i] > "9") {
                revert InvalidCode();
            }
        }
    }

    /**
     * @dev Convert uint256 to string
     * @param value The value to convert
     * @return The string representation
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits;

        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);

        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }

    /**
     * @dev Generate a random 9-digit code
     * @return The random code string
     */
    function _generateRandomCode() internal returns (string memory) {
        // Update random seed using block data
        _randomSeed = uint256(
            keccak256(
                abi.encodePacked(
                    _randomSeed,
                    block.timestamp,
                    block.prevrandao,
                    msg.sender,
                    block.number
                )
            )
        );

        // Generate random 9-digit number (100000000 - 999999999)
        uint256 randomNumber = 100000000 + (_randomSeed % 900000000);

        return string(abi.encodePacked("NEKO", _toString(randomNumber)));
    }
}
