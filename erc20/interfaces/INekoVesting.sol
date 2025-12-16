// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title INekoVesting
 * @dev Interface for NEKO Vesting Contract
 */
interface INekoVesting {
    // =============================================================================
    // STRUCTS
    // =============================================================================
    struct VestingSchedule {
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 startTime;
        uint256 duration;
        uint256 cliff;
        bool revocable;
        bool revoked;
    }

    // =============================================================================
    // EVENTS
    // =============================================================================
    event VestingCreated(
        address indexed beneficiary,
        uint256 amount,
        uint256 startTime,
        uint256 duration,
        uint256 cliff,
        bool revocable
    );
    event TokensClaimed(
        address indexed beneficiary,
        uint256 amount,
        uint256 scheduleIndex
    );
    event VestingRevoked(
        address indexed beneficiary,
        uint256 scheduleIndex,
        uint256 unvestedAmount
    );
    event EmergencyWithdraw(address indexed token, uint256 amount);

    // =============================================================================
    // VESTING CREATION
    // =============================================================================
    function createVesting(
        address beneficiary,
        uint256 amount,
        uint256 startTime,
        uint256 duration,
        uint256 cliff,
        bool revocable
    ) external;

    function batchCreateVestingSchedules(
        address[] calldata beneficiaries,
        uint256[] calldata amounts,
        uint256[] calldata startTimes,
        uint256[] calldata durations,
        uint256[] calldata cliffs,
        bool[] calldata revocables
    ) external;

    function createVestingBatch(
        address[] calldata beneficiaries,
        uint256[] calldata amounts,
        uint256 startTime,
        uint256 duration,
        uint256 cliff,
        bool revocable
    ) external;

    // =============================================================================
    // CLAIM FUNCTIONS
    // =============================================================================
    function claim(uint256 scheduleIndex) external;
    function claimAll() external;

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================
    function revokeVesting(address beneficiary, uint256 scheduleIndex) external;
    function emergencyWithdraw(address tokenAddress, uint256 amount) external;
    function pause() external;
    function unpause() external;

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================
    function token() external view returns (address);
    function getVestingSchedules(
        address beneficiary
    ) external view returns (VestingSchedule[] memory);
    function getVestingSchedule(
        address beneficiary,
        uint256 index
    )
        external
        view
        returns (
            uint256 totalAmount,
            uint256 claimedAmount,
            uint256 startTime,
            uint256 duration,
            uint256 cliff,
            bool revocable,
            bool revoked
        );

    function getVestingScheduleCount(
        address beneficiary
    ) external view returns (uint256);
    function getTotalVestedAmount(
        address beneficiary
    ) external view returns (uint256);
    function getVestedAmount(
        address beneficiary,
        uint256 scheduleIndex
    ) external view returns (uint256);
    function getClaimableAmount(
        address beneficiary,
        uint256 scheduleIndex
    ) external view returns (uint256);
    function getTotalClaimableAmount(
        address beneficiary
    ) external view returns (uint256);

    function getVestingInfo(
        address beneficiary
    )
        external
        view
        returns (
            uint256 _totalVested,
            uint256 _totalClaimed,
            uint256 _totalClaimable,
            uint256 _totalLocked,
            uint256 scheduleCount
        );

    function getContractStats()
        external
        view
        returns (
            uint256 _totalVestingAmount,
            uint256 _totalClaimedAmount,
            uint256 _totalLockedAmount,
            uint256 contractBalance
        );
}
