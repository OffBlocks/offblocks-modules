// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {IERC7579Account} from "modulekit/Accounts.sol";
import {ERC7579ExecutorBase} from "modulekit/modules/ERC7579ExecutorBase.sol";
import {SessionKeyBase} from "modulekit/modules/SessionKeyBase.sol";
import {ERC20Integration} from "modulekit/integrations/ERC20.sol";
import {ExecutionLib, Execution} from "erc7579/lib/ExecutionLib.sol";
import {ModeLib} from "erc7579/lib/ModeLib.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./SpendLimit.sol";

/**
 * @title FiatPayment
 * @author OffBlocks Team
 * @notice Fiat payment module and escrow contract for OffBlocks to handle token reservations and withdrawals based on the off-chain events and conditions (EVM version)
 */
contract FiatPayment is ERC7579ExecutorBase, SessionKeyBase, Ownable {
  using EnumerableSet for EnumerableSet.AddressSet;

  /**
   * @notice A struct representing a user reservation
   * @param reservationId uint256 - The id of the reservation
   * @param account address - The address of the account (must be a smart wallet)
   * @param token address - The address of the token (must be supported by the escrow)
   * @param amount uint256 - The amount of the token
   * @param splitAmounts uint256[] - The amounts to be sent to each corresponding split address if reservation is approved
   * @param splitAddresses address[] - The addresses to which the split amounts will be sent if reservation is approved
   * @param status ReservationStatus - The status of the reservation
   * @param createdAt uint256 - The timestamp of the reservation
   * @param updatedAt uint256 - The timestamp of the most recent reservation update
   */
  struct Reservation {
    uint256 reservationId;
    address account;
    address token;
    uint256 amount;
    uint256[] splitAmounts;
    address[] splitAddresses;
    ReservationStatus status;
    uint256 createdAt;
    uint256 updatedAt;
  }
  struct ScopedAccess {
    address signer;
    address token;
  }

  /// @notice An enum representing all possible reservation statuses
  enum ReservationStatus {
    Pending,
    Captured,
    Reverted
  }

  /// @notice Set to keep track of enabled smart accounts.
  EnumerableSet.AddressSet internal accounts;

  /// @notice The mapping of token addresses to whether or not they are supported by the escrow
  mapping(IERC20 => bool) public supportedTokens;

  /// @notice The mapping of user addresses to their reservations
  mapping(address => uint256[]) public reservations;

  /// @notice The mapping of reservation IDs to their reservations
  mapping(uint256 => Reservation) public reservationById;

  /// @notice The mapping of account addresses to their spend limits
  mapping(address => SpendLimit) public limits;

  /// @notice The id of the next reservation, starts at 1
  uint256 private _nextReservationId;

  /// @notice An event emitted when a reservation is made
  event Reserved(
    uint256 indexed reservationId,
    address indexed account,
    address indexed token,
    uint256 amount,
    uint256 createdAt
  );

  /// @notice An event emitted when a reservation is topped up
  event ReservationIncreased(
    uint256 indexed reservationId,
    address indexed account,
    address indexed token,
    uint256 amount,
    uint256 updatedAt
  );

  /// @notice An event emitted when a reservation is reduced
  event ReservationReduced(
    uint256 indexed reservationId,
    address indexed account,
    address indexed token,
    uint256 amount,
    uint256 updatedAt
  );

  /// @notice An event emitted when a reservation is approved or reverted
  event ReservationStatusUpdated(
    uint256 indexed reservationId,
    ReservationStatus status,
    uint256 updatedAt
  );

  /// @notice An event emitted when a reverted reservation is withdrawn from the escrow to the account
  event Reversal(
    uint256 indexed reservationId,
    address indexed account,
    address indexed token,
    uint256 amount,
    uint256 timestamp
  );

  /// @notice An event emitted when the reservationed tokens are transferred from the escrow to the settlement wallet
  event Capture(
    uint256 indexed reservationId,
    address indexed account,
    address indexed token,
    uint256 amount,
    uint256 timestamp
  );

  /// @notice An error thrown when the caller is not authorized to perform an operation
  error UnauthorizedAccess();

  /// @notice An event emitted when a token is added to the list of supported tokens
  event NewSupportedToken(address indexed token);

  /// @notice An event emitted when a token is removed from the list of supported tokens
  event RemovedSupportedToken(address indexed token);

  /// @notice An error thrown when the supplied module config is invalid
  error InvalidConfig();

  /// @notice An error thrown when the zero address is passed as an argument
  error ZeroAddress();

  /// @notice An error thrown when the amount is zero
  error ZeroAmount();

  /// @notice An error thrown when the ERC20 transfer amount is zero
  error ZeroTokens();

  /// @notice An error thrown when the account does not have enough balance of the token
  error InsufficientBalance();

  /// @notice An error thrown when the account has not approved the escrow to transfer the amount of the token
  error InsufficientAllowance();

  /// @notice An error thrown when the array length is zero
  error ArrayLengthOfZero();

  /// @notice An error thrown when the token is not supported by the escrow
  error UnsupportedToken(address token);

  /// @notice An error thrown when the status is not Pending, Captured or Reverted
  error InvalidStatus(uint256 status);

  /// @notice An error thrown when the reservation amount is unchanged when trying to change the reservation amount
  error ReservationUnchanged();

  /// @notice An error thrown when the new amount reservation is less than the old amount when trying to top up the reservation
  error NewAmountLessThanOldAmount();

  /// @notice An error thrown when the new amount reservation is greater than the old amount when trying to reduce the reservation
  error NewAmountGreaterThanOldAmount();

  /// @notice An error thrown when the reservation is not Pending
  error ReservationNotPending();

  /// @notice An error thrown when the reservation is not Captured
  error ReservationNotCaptured();

  /// @notice An error thrown when the reservation is not Reverted
  error ReservationNotReverted();

  /// @notice An error thrown when the reservation does not exist
  error InvalidReservationId(uint256 reservationId);

  /// @notice An error thrown when the ERC20 token transfer failed
  error ERC20TransferFailed();

  /// @notice An error thrown when the array lengths are not equal
  error ArrayLengthMismatch();

  /// @notice An error thrown when the split addresses array contains a zero address
  error InvalidSplitAddressIncluded();

  /**
   * @notice The constructor for the FiatPayment
   * @param _owner address - The address of the owner of the module
   * @param _initiallySupportedTokens address[] - The addresses of the tokens to be supported by the module
   * @dev The settlement wallet cannot be the zero address
   * @dev The array of initially supported tokens cannot have a length of zero
   * @dev Each token address in the array of initially supported tokens cannot be the zero address
   */
  constructor(
    address _owner,
    address[] memory _initiallySupportedTokens
  ) Ownable(_owner) {
    if (_initiallySupportedTokens.length == 0) revert ArrayLengthOfZero();

    for (uint256 i = 0; i < _initiallySupportedTokens.length; i++) {
      if (_initiallySupportedTokens[i] == address(0)) revert ZeroAddress();
      supportedTokens[IERC20(_initiallySupportedTokens[i])] = true;
      emit NewSupportedToken(_initiallySupportedTokens[i]);
    }

    _nextReservationId = 1;
  }

  /**
   * @notice Adds a token to the list of supported tokens
   * @param _token address - The address of the token to be supported by the escrow
   * @dev Only owner can call this function
   * @dev The token cannot be the zero address
   * @dev Emits a {NewSupportedToken} event
   */
  function addSupportedToken(address _token) external onlyOwner {
    if (_token == address(0)) revert ZeroAddress();
    supportedTokens[IERC20(_token)] = true;
    emit NewSupportedToken(_token);
  }

  /**
   * @notice Removes a token from the list of supported tokens
   * @param _token address - The address of the token to be removed from the list of supported tokens
   * @dev Only owner can call this function
   * @dev The token must be supported by the escrow
   * @dev Emits a {RemovedSupportedToken} event
   */
  function removeSupportedToken(address _token) external onlyOwner {
    if (supportedTokens[IERC20(_token)] == false)
      revert UnsupportedToken(_token);
    supportedTokens[IERC20(_token)] = false;
    emit RemovedSupportedToken(_token);
  }

  /*//////////////////////////////////////////////////////////////////////////
                                     CONFIG
    //////////////////////////////////////////////////////////////////////////*/

  function onInstall(bytes calldata _data) external override {
    limits[msg.sender] = new SpendLimit(msg.sender, address(this), _data);
    accounts.add(msg.sender);
  }

  function onUninstall(bytes calldata) external override {
    delete limits[msg.sender];
    accounts.remove(msg.sender);
  }

  /// @notice Returns whether the given account is initialized or not
  function isInitialized(address _account) external view returns (bool) {
    return accounts.contains(_account);
  }

  /// @notice Throws if called by any account other than a registered smart account.
  modifier onlySmartAccount() {
    if (!accounts.contains(msg.sender)) {
      revert UnauthorizedAccess();
    }
    _;
  }

  /*//////////////////////////////////////////////////////////////////////////
                                   EXECUTOR LOGIC
    //////////////////////////////////////////////////////////////////////////*/

  /**
   * @notice Reserve tokens into the escrow
   * @param _token address - The address of the token to be reservationed
   * @param _splitAmounts uint256[] memory - The amounts to be sent to each corresponding split address if reservation is approved
   * @param _splitAddresses address[] memory - The addresses to which the split amounts will be sent if reservation is approved
   * @dev The token must be supported by the escrow
   * @dev The amount must be greater than zero
   * @dev The transaction must be sent from a smart wallet
   * @dev The account must have enough balance of the token
   */
  function reserve(
    address _token,
    uint256[] memory _splitAmounts,
    address[] memory _splitAddresses
  ) external onlySmartAccount {
    if (_splitAmounts.length == 0) revert ArrayLengthOfZero();
    if (_splitAmounts.length != _splitAddresses.length)
      revert ArrayLengthMismatch();
    if (!_checkForInvalidAddress(_splitAddresses))
      revert InvalidSplitAddressIncluded();

    IERC20 token = IERC20(_token);
    uint256 _amount = _getSum(_splitAmounts);

    if (supportedTokens[token] == false) revert UnsupportedToken(_token);
    if (_amount == 0) revert ZeroAmount();

    SpendLimit _limit = limits[msg.sender];
    _limit.checkSpendingLimit(_token, _amount);

    if (token.balanceOf(msg.sender) < _amount) revert InsufficientBalance();

    Reservation memory userReservation = Reservation({
      reservationId: _nextReservationId,
      account: msg.sender,
      token: _token,
      amount: _amount,
      splitAmounts: _splitAmounts,
      splitAddresses: _splitAddresses,
      status: ReservationStatus.Pending,
      createdAt: block.timestamp,
      updatedAt: block.timestamp
    });

    reservations[msg.sender].push(_nextReservationId);
    reservationById[_nextReservationId] = userReservation;
    _nextReservationId++;

    Execution memory exec = ERC20Integration.transfer(
      token,
      address(this),
      _amount
    );

    IERC7579Account(msg.sender).executeFromExecutor(
      ModeLib.encodeSimpleSingle(),
      ExecutionLib.encodeSingle(exec.target, exec.value, exec.callData)
    );

    emit Reserved(
      userReservation.reservationId,
      userReservation.account,
      userReservation.token,
      userReservation.amount,
      userReservation.createdAt
    );
  }

  /**
   * @notice Update the amount of the reservation
   * @param _reservationId uint256 - The id of the reservation to be topped up
   * @param _splitAmounts uint256[] memory - The amounts to be sent to each corresponding split address if reservation is approved
   * @dev The amount must be greater than zero
   * @dev The amount must be greater than the old amount
   * @dev The reservation must be pending
   * @dev The account must have enough balance of the token
   * @dev Emits a {ReservationIncreased} event
   */
  function updateReservation(
    uint256 _reservationId,
    uint256[] memory _splitAmounts
  ) external onlySmartAccount {
    Reservation memory userReservation = getReservationById(_reservationId);

    if (msg.sender != userReservation.account) revert UnauthorizedAccess();

    uint256 oldAmount = userReservation.amount;
    uint256 newAmount = _getSum(_splitAmounts);

    if (_splitAmounts.length != userReservation.splitAddresses.length)
      revert ArrayLengthMismatch();
    if (newAmount == 0) revert ZeroAmount();
    if (oldAmount == newAmount) revert ReservationUnchanged();
    if (oldAmount > newAmount) revert NewAmountLessThanOldAmount();
    if (userReservation.status != ReservationStatus.Pending)
      revert ReservationNotPending();

    IERC20 token = IERC20(userReservation.token);
    uint256 amountToReserve = newAmount - oldAmount;

    SpendLimit _limit = limits[msg.sender];
    _limit.checkSpendingLimit(userReservation.token, amountToReserve);

    if (token.balanceOf(msg.sender) < amountToReserve)
      revert InsufficientBalance();

    userReservation.amount += amountToReserve;
    userReservation.splitAmounts = _splitAmounts;
    userReservation.updatedAt = block.timestamp;

    reservationById[_reservationId] = userReservation;

    Execution memory exec = ERC20Integration.transfer(
      token,
      address(this),
      amountToReserve
    );

    IERC7579Account(msg.sender).executeFromExecutor(
      ModeLib.encodeSimpleSingle(),
      ExecutionLib.encodeSingle(exec.target, exec.value, exec.callData)
    );

    emit ReservationIncreased(
      userReservation.reservationId,
      userReservation.account,
      userReservation.token,
      userReservation.amount,
      userReservation.updatedAt
    );
  }

  /**
   * @notice Reduces the amount of the reservation
   * @param _reservationId uint256 - The id of the reservation to be reduced
   * @param _splitAmounts uint256[] memory - The amounts to be sent to each corresponding split address if reservation is approved
   * @dev The amount must be greater than zero
   * @dev The amount must be less than the old amount
   * @dev The reservation must be pending
   * @dev The excess amount must be transferred back to the account
   * @dev Emits a {ReservationReduced} event
   */
  function reduceReservation(
    uint256 _reservationId,
    uint256[] memory _splitAmounts
  ) external onlyOwner {
    Reservation memory userReservation = getReservationById(_reservationId);

    uint256 oldAmount = userReservation.amount;
    uint256 newAmount = _getSum(_splitAmounts);

    if (_splitAmounts.length != userReservation.splitAddresses.length)
      revert ArrayLengthMismatch();
    if (newAmount == 0) revert ZeroAmount();
    if (oldAmount == newAmount) revert ReservationUnchanged();
    if (oldAmount < newAmount) revert NewAmountGreaterThanOldAmount();
    if (userReservation.status != ReservationStatus.Pending)
      revert ReservationNotPending();

    IERC20 token = IERC20(userReservation.token);
    uint256 amountToRevert = oldAmount - newAmount;

    SpendLimit _limit = limits[userReservation.account];
    _limit.revertSpendingLimit(
      userReservation.token,
      amountToRevert,
      userReservation.createdAt
    );

    userReservation.amount = userReservation.amount - amountToRevert;
    userReservation.splitAmounts = _splitAmounts;
    userReservation.updatedAt = block.timestamp;

    reservationById[_reservationId] = userReservation;

    bool success = token.transfer(userReservation.account, amountToRevert);
    if (!success) revert ERC20TransferFailed();

    emit ReservationReduced(
      userReservation.reservationId,
      userReservation.account,
      userReservation.token,
      userReservation.amount,
      userReservation.updatedAt
    );
  }

  /**
   * @notice Batch updates the statuses of the reservations
   * @param _reservationIds uint256[] calldata - The ids of the reservations to have their statuses updated
   * @param _status uint256 - The status to update the reservations to
   * @dev The status must be either Captured or Reverted
   * @dev Each reservation must exist
   * @dev Each reservation must be pending
   * @dev Only owner can call this function
   * @dev Emits a {ReservationStatusUpdated} event for each reservation
   */
  function batchUpdateReservationStatuses(
    uint256[] calldata _reservationIds,
    uint256 _status
  ) external onlyOwner {
    if (_reservationIds.length == 0) revert ArrayLengthOfZero();
    if (
      _status != uint256(ReservationStatus.Captured) &&
      _status != uint256(ReservationStatus.Reverted)
    ) revert InvalidStatus(_status);

    for (uint256 i = 0; i < _reservationIds.length; i++) {
      Reservation storage userReservation = reservationById[_reservationIds[i]];

      if (userReservation.status != ReservationStatus.Pending)
        revert ReservationNotPending();

      userReservation.status = ReservationStatus(_status);

      emit ReservationStatusUpdated(
        _reservationIds[i],
        ReservationStatus(_status),
        block.timestamp
      );
    }
  }

  /**
   * @notice Reverts the reverted reservation from the escrow to the account
   * @param _reservationId uint256 - The id of the reservation to be reverted
   * @dev Reservation must exist
   * @dev Reservation must be reverted
   * @dev Only owner can call this function
   * @dev Emits a {Reversal} event
   */
  function revertReservation(uint256 _reservationId) external onlyOwner {
    Reservation memory userReservation = getReservationById(_reservationId);

    if (userReservation.status != ReservationStatus.Reverted)
      revert ReservationNotReverted();

    SpendLimit _limit = limits[userReservation.account];
    _limit.revertSpendingLimit(
      userReservation.token,
      userReservation.amount,
      userReservation.createdAt
    );

    bool success = IERC20(userReservation.token).transfer(
      userReservation.account,
      userReservation.amount
    );
    if (!success) revert ERC20TransferFailed();

    emit Reversal(
      userReservation.reservationId,
      userReservation.account,
      userReservation.token,
      userReservation.amount,
      block.timestamp
    );
  }

  /**
   * @notice Transfers the approved reservation from the escrow to the settlement wallet
   * @param _reservationId uint256 - The id of the reservation to be settled
   * @dev Reservation must exist
   * @dev Reservation must be approved
   * @dev Only owner can call this function
   * @dev Emits a {Capture} event for each reservation
   */
  function captureReservation(uint256 _reservationId) external onlyOwner {
    Reservation memory userReservation = getReservationById(_reservationId);

    if (userReservation.status != ReservationStatus.Captured)
      revert ReservationNotCaptured();

    for (uint256 j = 0; j < userReservation.splitAddresses.length; j++) {
      bool success = IERC20(userReservation.token).transfer(
        userReservation.splitAddresses[j],
        userReservation.splitAmounts[j]
      );
      if (!success) revert ERC20TransferFailed();
    }

    emit Capture(
      userReservation.reservationId,
      userReservation.account,
      userReservation.token,
      userReservation.amount,
      block.timestamp
    );
  }

  /**
   * @notice Transfers the approved reservations from the escrow to the settlement wallets
   * @param _reservationIds uint256[] calldata - The ids of the reservations to be settled
   * @dev Each reservation must exist
   * @dev Each reservation must be approved
   * @dev Only owner can call this function
   * @dev Emits a {Capture} event for each reservation
   */
  function batchCapture(uint256[] calldata _reservationIds) external onlyOwner {
    if (_reservationIds.length == 0) revert ArrayLengthOfZero();

    for (uint256 i = 0; i < _reservationIds.length; i++) {
      Reservation memory userReservation = getReservationById(
        _reservationIds[i]
      );

      if (userReservation.status != ReservationStatus.Captured)
        revert ReservationNotCaptured();

      for (uint256 j = 0; j < userReservation.splitAddresses.length; j++) {
        bool success = IERC20(userReservation.token).transfer(
          userReservation.splitAddresses[j],
          userReservation.splitAmounts[j]
        );
        if (!success) revert ERC20TransferFailed();
      }

      emit Capture(
        userReservation.reservationId,
        userReservation.account,
        userReservation.token,
        userReservation.amount,
        block.timestamp
      );
    }
  }

  /**
   * @notice Gets the array of all reservations for the given account
   * @param _account address - The address of the account
   * @return uint256[] - The array of reservation ids for the given account
   * @dev The account cannot be the zero address
   */
  function getReservations(
    address _account
  ) external view returns (uint256[] memory) {
    if (_account == address(0)) revert ZeroAddress();
    return reservations[_account];
  }

  /**
   * @notice Gets the reservation with the given id
   * @param _reservationId uint256 - The id of the reservation
   * @return Reservation - The reservation with the given id
   * @dev The reservation must exist
   */
  function getReservationById(
    uint256 _reservationId
  ) public view returns (Reservation memory) {
    if (reservationById[_reservationId].reservationId == 0)
      revert InvalidReservationId(_reservationId);
    return reservationById[_reservationId];
  }

  /**
   * @notice Gets the next reservation id
   * @return uint256 - The next reservation id
   */
  function getNextReservationId() public view returns (uint256) {
    return _nextReservationId;
  }

  /**
   * @notice Returns whether the given array of addresses is a valid array of split addresses or not (i.e. it should not contain zero address)
   * @param _splitAddresses address[] memory
   * @return bool
   */
  function _checkForInvalidAddress(
    address[] memory _splitAddresses
  ) internal pure returns (bool) {
    bool valid = true;
    for (uint i = 0; i < _splitAddresses.length; i++) {
      if (_splitAddresses[i] == address(0)) {
        valid = false;
      }
    }
    return valid;
  }

  /**
   * @notice Returns sum of the given array of integer values
   * @param _values uint256[] memory
   * @return uint256
   */
  function _getSum(uint256[] memory _values) internal pure returns (uint256) {
    uint256 sum = 0;
    for (uint i = 0; i < _values.length; i++) {
      sum = sum + _values[i];
    }
    return sum;
  }

  /*//////////////////////////////////////////////////////////////////////////
                                VALIDATOR LOGIC
    //////////////////////////////////////////////////////////////////////////*/

  /// @notice validates that the call (destinationContract, callValue, funcCallData)
  /// complies with the Session Key permissions represented by sessionKeyData
  /// @param _target address of the contract to be called
  /// @param _callData the data for the call.
  /// @param _sessionKeyData SessionKey data, that describes sessionKey permissions
  /// @return signer SessionKey signer address
  function validateSessionParams(
    address _target,
    uint256 /*_value*/,
    bytes calldata _callData,
    bytes calldata _sessionKeyData,
    bytes calldata /*_callSpecificData*/
  ) public virtual override onlyThis(_target) returns (address signer) {
    bytes4 functionSig;

    if (_callData.length >= 4) {
      functionSig = bytes4(_callData[0:4]);
    }

    if (
      functionSig != this.reserve.selector &&
      functionSig != this.updateReservation.selector
    ) revert InvalidMethod(functionSig);

    ScopedAccess memory access = abi.decode(_sessionKeyData, (ScopedAccess));

    if (functionSig == this.reserve.selector) {
      address token = abi.decode(_callData[4:24], (address));
      if (token != access.token) revert UnauthorizedAccess();
    }

    return access.signer;
  }

  /*//////////////////////////////////////////////////////////////////////////
                                     METADATA
    //////////////////////////////////////////////////////////////////////////*/

  /** @notice Check if the module is of a certain type
   * @param _typeId The type ID to check
   * @return true if the module is of the given type, false otherwise
   */
  function isModuleType(uint256 _typeId) external pure override returns (bool) {
    return _typeId == TYPE_EXECUTOR;
  }

  /**
   * @notice The name of the module
   * @return name The name of the module
   */
  function name() external pure returns (string memory) {
    return "FiatPayment";
  }

  /**
   * @notice The version of the module
   * @return version The version of the module
   */
  function version() external pure returns (string memory) {
    return "0.0.1";
  }
}
