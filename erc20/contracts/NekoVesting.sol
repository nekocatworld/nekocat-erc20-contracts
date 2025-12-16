// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/INekoVesting.sol";
import "../lib/NekoCoinErrors.sol";

/**
 * @title NekoVesting
 * @dev Token vesting contract with linear and cliff vesting support
 *
 * Features:
 * - Linear vesting with cliff period
 * - Multiple vesting schedules per beneficiary
 * - Revocable vesting (admin can revoke)
 * - Emergency pause and recovery
 * - Batch vesting creation
 * - Vesting info queries
 *
 * Security:
 * - ReentrancyGuard on claim functions
 * - Pausable for emergency stops
 * - SafeERC20 for token transfers
 * - Overflow protection with Solidity 0.8+
 * - Access control for admin functions
 */
contract NekoVesting is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // =============================================================================
    // CUSTOM ERRORS
    // =============================================================================
    error InvalidAddress();
    error InvalidAmount();
    error InvalidDuration();
    error NoVestingSchedule();
    error NothingToClaim();
    error VestingAlreadyRevoked();
    error VestingNotRevocable();
    error InsufficientBalance();

    // =============================================================================
    // STRUCTS
    // =============================================================================
    struct VestingSchedule {
        uint256 totalAmount; // Total tokens to vest
        uint256 claimedAmount; // Tokens already claimed
        uint256 startTime; // Vesting start timestamp
        uint256 duration; // Vesting duration in seconds
        uint256 cliff; // Cliff period in seconds
        bool revocable; // Can admin revoke this vesting?
        bool revoked; // Has this vesting been revoked?
    }

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================
    IERC20 public immutable nekoToken;

    mapping(address => VestingSchedule[]) public vestingSchedules;
    mapping(address => uint256) public totalVested;
    mapping(address => uint256) public totalClaimed;

    uint256 public totalVestingAmount;
    uint256 public totalClaimedAmount;

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
    // CONSTRUCTOR
    // =============================================================================
    constructor(
        address _nekoToken,
        address initialOwner
    ) Ownable(initialOwner) {
        if (_nekoToken == address(0)) revert InvalidAddress();
        nekoToken = IERC20(_nekoToken);
    }

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
    ) external onlyOwner {
        if (beneficiary == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (duration == 0) revert InvalidDuration();
        if (cliff > duration) revert InvalidDuration();
        if (startTime == 0) startTime = block.timestamp;

        vestingSchedules[beneficiary].push(
            VestingSchedule({
                totalAmount: amount,
                claimedAmount: 0,
                startTime: startTime,
                duration: duration,
                cliff: cliff,
                revocable: revocable,
                revoked: false
            })
        );

        totalVested[beneficiary] += amount;
        totalVestingAmount += amount;

        emit VestingCreated(
            beneficiary,
            amount,
            startTime,
            duration,
            cliff,
            revocable
        );
    }

    function batchCreateVestingSchedules(
        address[] calldata beneficiaries,
        uint256[] calldata amounts,
        uint256[] calldata startTimes,
        uint256[] calldata durations,
        uint256[] calldata cliffs,
        bool[] calldata revocables
    ) external onlyOwner {
        if (beneficiaries.length != amounts.length) revert InvalidAmount();
        if (beneficiaries.length != startTimes.length) revert InvalidAmount();
        if (beneficiaries.length != durations.length) revert InvalidAmount();
        if (beneficiaries.length != cliffs.length) revert InvalidAmount();
        if (beneficiaries.length != revocables.length) revert InvalidAmount();

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            if (beneficiaries[i] == address(0)) revert InvalidAddress();
            if (amounts[i] == 0) revert InvalidAmount();
            if (durations[i] == 0) revert InvalidDuration();
            if (cliffs[i] > durations[i]) revert InvalidDuration();

            uint256 startTime = startTimes[i] == 0
                ? block.timestamp
                : startTimes[i];

            vestingSchedules[beneficiaries[i]].push(
                VestingSchedule({
                    totalAmount: amounts[i],
                    claimedAmount: 0,
                    startTime: startTime,
                    duration: durations[i],
                    cliff: cliffs[i],
                    revocable: revocables[i],
                    revoked: false
                })
            );

            totalVested[beneficiaries[i]] += amounts[i];
            totalVestingAmount += amounts[i];

            emit VestingCreated(
                beneficiaries[i],
                amounts[i],
                startTime,
                durations[i],
                cliffs[i],
                revocables[i]
            );
        }
    }

    function createVestingBatch(
        address[] calldata beneficiaries,
        uint256[] calldata amounts,
        uint256 startTime,
        uint256 duration,
        uint256 cliff,
        bool revocable
    ) external onlyOwner {
        if (beneficiaries.length != amounts.length) revert InvalidAmount();
        if (duration == 0) revert InvalidDuration();
        if (cliff > duration) revert InvalidDuration();
        if (startTime == 0) startTime = block.timestamp;

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            if (beneficiaries[i] == address(0)) revert InvalidAddress();
            if (amounts[i] == 0) revert InvalidAmount();

            vestingSchedules[beneficiaries[i]].push(
                VestingSchedule({
                    totalAmount: amounts[i],
                    claimedAmount: 0,
                    startTime: startTime,
                    duration: duration,
                    cliff: cliff,
                    revocable: revocable,
                    revoked: false
                })
            );

            totalVested[beneficiaries[i]] += amounts[i];
            totalVestingAmount += amounts[i];

            emit VestingCreated(
                beneficiaries[i],
                amounts[i],
                startTime,
                duration,
                cliff,
                revocable
            );
        }
    }

    // =============================================================================
    // CLAIM FUNCTIONS
    // =============================================================================
    function claim(uint256 scheduleIndex) external nonReentrant whenNotPaused {
        VestingSchedule[] storage schedules = vestingSchedules[msg.sender];
        if (scheduleIndex >= schedules.length) revert NoVestingSchedule();

        VestingSchedule storage schedule = schedules[scheduleIndex];
        if (schedule.revoked) revert VestingAlreadyRevoked();

        uint256 claimable = _calculateClaimable(schedule);
        if (claimable == 0) revert NothingToClaim();

        schedule.claimedAmount += claimable;
        totalClaimed[msg.sender] += claimable;
        totalClaimedAmount += claimable;

        nekoToken.safeTransfer(msg.sender, claimable);

        emit TokensClaimed(msg.sender, claimable, scheduleIndex);
    }

    function claimAll() external nonReentrant whenNotPaused {
        VestingSchedule[] storage schedules = vestingSchedules[msg.sender];
        if (schedules.length == 0) revert NoVestingSchedule();

        uint256 totalClaimable = 0;

        for (uint256 i = 0; i < schedules.length; i++) {
            VestingSchedule storage schedule = schedules[i];
            if (schedule.revoked) continue;

            uint256 claimable = _calculateClaimable(schedule);
            if (claimable > 0) {
                schedule.claimedAmount += claimable;
                totalClaimable += claimable;
                emit TokensClaimed(msg.sender, claimable, i);
            }
        }

        if (totalClaimable == 0) revert NothingToClaim();

        totalClaimed[msg.sender] += totalClaimable;
        totalClaimedAmount += totalClaimable;

        nekoToken.safeTransfer(msg.sender, totalClaimable);
    }

    function _calculateClaimable(
        VestingSchedule storage schedule
    ) internal view returns (uint256) {
        uint256 currentTime = block.timestamp;

        // Simplified timestamp protection - just use block.timestamp
        // The block-based calculation was causing overflow issues

        if (currentTime < schedule.startTime + schedule.cliff) {
            return 0;
        }

        uint256 elapsedTime = currentTime - schedule.startTime;

        if (elapsedTime >= schedule.duration) {
            return schedule.totalAmount - schedule.claimedAmount;
        }

        uint256 vestedAmount = (schedule.totalAmount * elapsedTime) /
            schedule.duration;
        return vestedAmount - schedule.claimedAmount;
    }

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================
    function revokeVesting(
        address beneficiary,
        uint256 scheduleIndex
    ) external onlyOwner nonReentrant {
        VestingSchedule[] storage schedules = vestingSchedules[beneficiary];
        if (scheduleIndex >= schedules.length) revert NoVestingSchedule();

        VestingSchedule storage schedule = schedules[scheduleIndex];
        if (!schedule.revocable) revert VestingNotRevocable();
        if (schedule.revoked) revert VestingAlreadyRevoked();

        uint256 claimable = _calculateClaimable(schedule);
        uint256 unvestedAmount = schedule.totalAmount -
            schedule.claimedAmount -
            claimable;

        schedule.revoked = true;

        if (claimable > 0) {
            schedule.claimedAmount += claimable;
            totalClaimed[beneficiary] += claimable;
            totalClaimedAmount += claimable;
            nekoToken.safeTransfer(beneficiary, claimable);
        }

        if (unvestedAmount > 0) {
            totalVested[beneficiary] -= unvestedAmount;
            totalVestingAmount -= unvestedAmount;
        }

        emit VestingRevoked(beneficiary, scheduleIndex, unvestedAmount);
    }

    function emergencyWithdraw(
        address tokenAddress,
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (tokenAddress == address(0)) {
            (bool success, ) = owner().call{value: amount}("");
            if (!success) revert InsufficientBalance();
        } else {
            IERC20(tokenAddress).safeTransfer(owner(), amount);
        }

        emit EmergencyWithdraw(tokenAddress, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================
    function token() external view returns (address) {
        return address(nekoToken);
    }

    function getVestingSchedules(
        address beneficiary
    ) external view returns (VestingSchedule[] memory) {
        return vestingSchedules[beneficiary];
    }

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
        )
    {
        VestingSchedule storage schedule = vestingSchedules[beneficiary][index];
        return (
            schedule.totalAmount,
            schedule.claimedAmount,
            schedule.startTime,
            schedule.duration,
            schedule.cliff,
            schedule.revocable,
            schedule.revoked
        );
    }

    function getVestingScheduleCount(
        address beneficiary
    ) external view returns (uint256) {
        return vestingSchedules[beneficiary].length;
    }

    function getTotalVestedAmount(
        address beneficiary
    ) external view returns (uint256) {
        return totalVested[beneficiary];
    }

    function getVestedAmount(
        address beneficiary,
        uint256 scheduleIndex
    ) external view returns (uint256) {
        VestingSchedule[] storage schedules = vestingSchedules[beneficiary];
        if (scheduleIndex >= schedules.length) return 0;

        VestingSchedule storage schedule = schedules[scheduleIndex];
        if (schedule.revoked) return 0;

        return _calculateClaimable(schedule);
    }

    function getClaimableAmount(
        address beneficiary,
        uint256 scheduleIndex
    ) external view returns (uint256) {
        VestingSchedule[] storage schedules = vestingSchedules[beneficiary];
        if (scheduleIndex >= schedules.length) return 0;

        VestingSchedule storage schedule = schedules[scheduleIndex];
        if (schedule.revoked) return 0;

        return _calculateClaimable(schedule);
    }

    function getTotalClaimableAmount(
        address beneficiary
    ) external view returns (uint256) {
        VestingSchedule[] storage schedules = vestingSchedules[beneficiary];
        uint256 totalClaimable = 0;

        for (uint256 i = 0; i < schedules.length; i++) {
            if (!schedules[i].revoked) {
                totalClaimable += _calculateClaimable(schedules[i]);
            }
        }

        return totalClaimable;
    }

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
        )
    {
        _totalVested = totalVested[beneficiary];
        _totalClaimed = totalClaimed[beneficiary];
        _totalClaimable = this.getTotalClaimableAmount(beneficiary);
        _totalLocked = _totalVested - _totalClaimed - _totalClaimable;
        scheduleCount = vestingSchedules[beneficiary].length;
    }

    function getContractStats()
        external
        view
        returns (
            uint256 _totalVestingAmount,
            uint256 _totalClaimedAmount,
            uint256 _totalLockedAmount,
            uint256 contractBalance
        )
    {
        _totalVestingAmount = totalVestingAmount;
        _totalClaimedAmount = totalClaimedAmount;
        _totalLockedAmount = _totalVestingAmount - _totalClaimedAmount;
        contractBalance = nekoToken.balanceOf(address(this));
    }

    receive() external payable {
        revert("Contract does not accept ETH");
    }
}
