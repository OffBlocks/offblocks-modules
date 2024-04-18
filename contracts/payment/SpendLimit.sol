// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SpendLimit
 * @author OffBlocks Team
 * @notice This utility contract implements daily and monthly spending limits for OffBlocks users
 */
contract SpendLimit is Ownable {
  /// @notice The constant for one day in seconds
  uint256 public constant ONE_DAY = 24 hours;

  /// @notice The constant for one month in seconds
  uint256 public constant ONE_MONTH = 30 days;

  /**
   * @notice The struct for the daily and monthly spending limits
   * @param dailyLimit uint256 - The amount of a daily spending limit
   * @param monthlyLimit uint256 - The amount of a monthly spending limit
   * @param dailyAvailable uint256 - The available amount that can be spent in a day
   * @param monthlyAvailable uint256 - The available amount that can be spent in a month
   * @param nextDailyReset uint256 - The block.timestamp at which the daily available amount is restored
   * @param nextMonthlyReset uint256 - The block.timestamp at which the monthly available amount is restored
   */
  struct Limit {
    uint256 dailyLimit;
    uint256 monthlyLimit;
    uint256 dailyAvailable;
    uint256 monthlyAvailable;
    uint256 nextDailyReset;
    uint256 nextMonthlyReset;
  }

  /// @notice Mapping of tokens to their spending limits
  mapping(address => Limit) public limits;

  /// @notice The address of the spender contract
  address private spender;

  /// @notice An event emitted when spending limits are updated
  event SpendingLimitUpdated(
    address indexed token,
    uint256 dailyLimit,
    uint256 monthlyLimit
  );

  /// @notice An event emitted when spending limits are removed
  event SpendingLimitRemoved(address indexed token);

  /// @notice An error thrown when the initial configuration is invalid
  error InvalidConfig();

  /// @notice An error thrown when the account is not authorized to perform an operation
  error UnauthorizedAccount(address account);

  /// @notice An error thrown when the amount is zero
  error ZeroAmount();

  /// @notice An error thrown when the update of a spending limit is invalid
  error InvalidUpdate();

  /// @notice An error thrown when the amount exceeds the remaining daily available amount
  error ExceedsDailyLimit();

  /// @notice An error thrown when the amount exceeds the remaining monthly available amount
  error ExceedsMonthlyLimit();

  /**
   * @notice The constructor for the SpendLimit contract
   * @param _owner address - The address of the owner account
   * @param _spender address - The address of the spender contract
   * @param _initConfig bytes - The initial configuration for the SpendLimit contract
   */
  constructor(
    address _owner,
    address _spender,
    bytes memory _initConfig
  ) Ownable(_owner) {
    spender = _spender;

    (
      address[] memory tokens,
      uint256[] memory dailyLimits,
      uint256[] memory monthlyLimits
    ) = abi.decode(_initConfig, (address[], uint256[], uint256[]));

    if (
      tokens.length != dailyLimits.length ||
      tokens.length != monthlyLimits.length
    ) {
      revert InvalidConfig();
    }

    for (uint256 i = 0; i < tokens.length; i++) {
      _setLimit(tokens[i], dailyLimits[i], monthlyLimits[i]);
    }
  }

  /// @notice Throws if called by any account other than the spender
  modifier onlySpender() {
    if (spender != msg.sender) {
      revert UnauthorizedAccount(msg.sender);
    }
    _;
  }

  /**
   * @notice This function enables a daily and monthly spending limit for a specific tokens
   * @param _token address - ERC20 token address that a given spending limit is applied
   * @param _dailyAmount uint256 - The amount of a daily spending limit in wei or token units (non-zero)
   * @param _monthlyAmount uint256 - The amount of a monthly spending limit in wei or token units (non-zero)
   * @dev Only the owner account can call this function
   * @dev Emits a {SpendingLimitUpdated} event
   */
  function setSpendingLimit(
    address _token,
    uint256 _dailyAmount,
    uint256 _monthlyAmount
  ) public onlyOwner {
    _setLimit(_token, _dailyAmount, _monthlyAmount);
  }

  /**
   * @notice This function disables an active spending limit for a specific token
   * @param _token address - ERC20 token address that a given spending limit is applied on
   * @dev Only owner account can call this function
   * @dev Emits a {SpendingLimitRemoved} event
   */
  function removeSpendingLimit(address _token) public onlyOwner {
    if (!isValidUpdate(_token)) revert InvalidUpdate();
    _updateLimit(_token, 0, 0, 0, 0, 0, 0);
    emit SpendingLimitRemoved(_token);
  }

  /**
   * @notice This function verifies if the update to a Limit struct is valid
   * @param _token address - ERC20 token address that a given spending limit is applied
   * @dev Reverts if the update to a Limit struct is invalid
   * @dev Actively enforces a min 24 hour waiting period between updates for the daily limit or a min 30 day waiting period between updates for the monthly limit
   * @return bool - True if the update to a Limit struct is valid
   */
  function isValidUpdate(address _token) internal view returns (bool) {
    Limit memory limit = limits[_token];

    if (
      (limit.dailyLimit != limit.dailyAvailable ||
        block.timestamp < limit.nextDailyReset) &&
      (limit.monthlyLimit != limit.monthlyAvailable ||
        block.timestamp < limit.nextMonthlyReset)
    ) revert InvalidUpdate();

    return true;
  }

  /**
   * @notice This function checks if the amount exceeds the remaining available amount
   * @param _token address - ERC20 token address that a given spending limit is applied on
   * @param _amount uint256 - The amount of tokens to be spent
   * @dev Only spender account can call this function
   * @dev Reverts if the amount exceeds the remaining available amount for either the daily limit or the monthly spending limit
   */
  function checkSpendingLimit(
    address _token,
    uint256 _amount
  ) public onlySpender {
    Limit storage limit = limits[_token];

    uint256 timestamp = block.timestamp;

    if (timestamp > limit.nextDailyReset) {
      limit.nextDailyReset = timestamp + ONE_DAY;
      limit.dailyAvailable = limit.dailyLimit;
    }

    if (timestamp > limit.nextMonthlyReset) {
      limit.nextMonthlyReset = timestamp + ONE_MONTH;
      limit.monthlyAvailable = limit.monthlyLimit;
    }

    if (limit.dailyAvailable < _amount) revert ExceedsDailyLimit();
    if (limit.monthlyAvailable < _amount) revert ExceedsMonthlyLimit();

    limit.dailyAvailable -= _amount;
    limit.monthlyAvailable -= _amount;
  }

  /**
   * @notice This function adjusts remaining available amount on payment reversal
   * @param _token address - ERC20 token address that a given spending limit is applied on
   * @param _amount uint256 - The amount of tokens to be reverted
   * @param _timestamp uint256 - The block.timestamp at which the payment was made
   * @dev Only spender account can call this function
   * @dev Updates the daily and monthly available amount based on the amount to be reverted if the payment was made on the same day or month
   */
  function revertSpendingLimit(
    address _token,
    uint256 _amount,
    uint256 _timestamp
  ) public onlySpender {
    Limit storage limit = limits[_token];

    uint256 timestamp = block.timestamp;

    if (_timestamp >= timestamp - ONE_DAY) {
      limit.dailyAvailable += _amount;
    }

    if (_timestamp >= timestamp - ONE_MONTH) {
      limit.monthlyAvailable += _amount;
    }
  }

  /**
   * @notice This function enables a daily and monthly spending limit for a specific token
   * @param _token address - ERC20 token address that a given spending limit is applied
   * @param _dailyAmount uint256 - The amount of a daily spending limit in wei or token units (non-zero)
   * @param _monthlyAmount uint256 - The amount of a monthly spending limit in wei or token units (non-zero)
   * @dev Emits a {SpendingLimitUpdated} event
   */
  function _setLimit(
    address _token,
    uint256 _dailyAmount,
    uint256 _monthlyAmount
  ) private {
    if (_dailyAmount == 0 || _monthlyAmount == 0) revert ZeroAmount();

    uint256 dailyResetTime;
    uint256 monthlyResetTime;
    uint256 resetTime = block.timestamp;

    if (isValidUpdate(_token)) {
      dailyResetTime = resetTime + ONE_DAY;
      monthlyResetTime = resetTime + ONE_MONTH;
    } else {
      dailyResetTime = resetTime;
      monthlyResetTime = resetTime;
    }

    _updateLimit(
      _token,
      _dailyAmount,
      _monthlyAmount,
      _dailyAmount,
      _monthlyAmount,
      dailyResetTime,
      monthlyResetTime
    );

    emit SpendingLimitUpdated(_token, _dailyAmount, _monthlyAmount);
  }

  /**
   * @notice This function updates a Limit struct
   * @param _token address - ERC20 token address that a given spending limit is applied
   * @param _dailyLimit uint256 - The amount of a daily spending limit
   * @param _monthlyLimit uint256 - The amount of a monthly spending limit
   * @param _dailyAvailable uint256 - The available amount that can be spent in a day
   * @param _monthlyAvailable uint256 - The available amount that can be spent in a month
   * @param _nextDailyReset uint256 - The block.timestamp at which the daily available amount is restored
   * @param _nextMonthlyReset uint256 - The block.timestamp at which the monthly available amount is restored
   */
  function _updateLimit(
    address _token,
    uint256 _dailyLimit,
    uint256 _monthlyLimit,
    uint256 _dailyAvailable,
    uint256 _monthlyAvailable,
    uint256 _nextDailyReset,
    uint256 _nextMonthlyReset
  ) private {
    Limit storage limit = limits[_token];

    limit.dailyLimit = _dailyLimit;
    limit.monthlyLimit = _monthlyLimit;
    limit.dailyAvailable = _dailyAvailable;
    limit.monthlyAvailable = _monthlyAvailable;
    limit.nextDailyReset = _nextDailyReset;
    limit.nextMonthlyReset = _nextMonthlyReset;
  }
}
