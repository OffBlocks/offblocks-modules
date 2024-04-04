// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC7579HookDestruct} from "modulekit/modules/ERC7579HookDestruct.sol";
import {IERC7579Account} from "modulekit/Accounts.sol";
import {ERC7579ExecutorBase} from "modulekit/modules/ERC7579ExecutorBase.sol";
import {ExecutionLib, Execution} from "erc7579/lib/ExecutionLib.sol";
import {ModeLib} from "erc7579/lib/ModeLib.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title DelayedExecution
 * @author OffBlocks Team
 * @notice Delayed execution module that allows for the initiation of transactions with a cooldown period
 */
contract DelayedExecution is ERC7579HookDestruct, ERC7579ExecutorBase, Ownable {
  using EnumerableMap for EnumerableMap.Bytes32ToUintMap;
  using EnumerableSet for EnumerableSet.AddressSet;

  bytes32 internal constant PASS = keccak256("pass");

  /**
   * @notice A struct representing module configuration for the account
   * @param cooldown uint256 - The cooldown period in seconds
   * @param whitelist EnumerableSet.AddressSet - The set of whitelisted executor addresses
   */
  struct DelayConfig {
    uint256 cooldown;
    EnumerableSet.AddressSet whitelist;
  }

  /// @notice An event emitted when an execution is initiated
  event ExecutionInitiated(
    address indexed smartAccount,
    address indexed target,
    uint256 value,
    bytes callData,
    uint256 createdAt,
    uint256 nonce
  );

  /// @notice An event emitted when an execution is skipped
  event ExecutionSkipped(
    address indexed smartAccount,
    address indexed target,
    uint256 value,
    bytes callData,
    uint256 nonce
  );

  /// @notice An event emitted when an execution is submitted
  event ExecutionSubmitted(
    address indexed smartAccount,
    address indexed target,
    uint256 value,
    bytes callData,
    uint256 nonce
  );

  /// @notice An error thrown when the execution is not supported
  error UnsupportedExecution();

  /// @notice An error thrown when the caller is not authorized to perform an operation
  error UnauthorizedAccess();

  /// @notice An error thrown when the execution is not authorized
  error ExecutionNotAuthorized();

  /// @notice An error thrown when the supplied module configuration is invalid
  error InvalidConfig();

  /// @notice An error thrown when the execution hash is not found
  error ExecutionHashNotFound(bytes32 executionHash);

  /// @notice The minimum cooldown period required before the transaction can be executed
  uint256 public minExecCooldown;

  /// @notice Mapping to keep track of smart account config.
  mapping(address smartAccount => DelayConfig config) internal configs;

  /// @notice Set to keep track of enabled smart accounts.
  EnumerableSet.AddressSet internal accounts;

  /// @notice Mapping to keep track of executions.
  mapping(address smartAccount => EnumerableMap.Bytes32ToUintMap exec)
    internal executions;

  /// @notice Mapping to keep track of account nonces.
  mapping(address smartAccount => uint256 nonce) internal nonces;

  /// @notice Mapping to keep track of account execution queue nonces.
  mapping(address smartAccount => uint256 queueNonce) internal queueNonces;

  /// @notice Mapping to keep track of execution nonces.
  mapping(bytes32 execHash => uint256 nonce) internal execNonces;

  constructor(address _owner, uint256 _minExecCooldown) Ownable(_owner) {
    minExecCooldown = _minExecCooldown;
  }

  /// @notice Sets the minimum cooldown period.
  /// @param _minExecCooldown Minimum cooldown in seconds that should be required before the transaction can be executed
  /// @notice This can only be called by the owner
  function setMinExecCooldown(uint256 _minExecCooldown) external onlyOwner {
    minExecCooldown = _minExecCooldown;
  }

  /*//////////////////////////////////////////////////////////////////////////
                                     CONFIG
    //////////////////////////////////////////////////////////////////////////*/

  function onInstall(bytes calldata data) external override {
    DelayConfig storage _config = configs[msg.sender];
    (uint256 _cooldown, address[] memory _whitelist) = abi.decode(
      data,
      (uint256, address[])
    );

    // Check if the config is valid
    if (_cooldown < minExecCooldown) {
      revert InvalidConfig();
    }

    _config.cooldown = _cooldown;

    for (uint256 i = 0; i < _whitelist.length; i++) {
      _config.whitelist.add(_whitelist[i]);
    }

    accounts.add(msg.sender);
  }

  function onUninstall(bytes calldata) external override {
    delete configs[msg.sender];
    accounts.remove(msg.sender);
  }

  /// @notice Checks if the module has been initialized for the account.
  /// @param _account The account address
  /// @return true if the module has been initialized, false otherwise
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

  /// @notice Checks if the target has been whitelisted for the account.
  /// @param _account The account address
  /// @param _target The target address
  /// @return true if the target has been whitelisted, false otherwise
  function isWhitelisted(
    address _account,
    address _target
  ) external view returns (bool) {
    return configs[_account].whitelist.contains(_target);
  }

  /*//////////////////////////////////////////////////////////////////////////
                                     HOOK LOGIC
    //////////////////////////////////////////////////////////////////////////*/

  /// @notice Initiates an execution.
  /// @param _target The target address to call
  /// @param _value The value to send
  /// @param _callData The call data
  function initExecution(
    address _target,
    uint256 _value,
    bytes calldata _callData
  ) external onlySmartAccount {
    bytes32 executionHash = _execDigest(_target, _value, _callData);
    uint256 createdAt = block.timestamp;

    uint256 accountNonce = nonces[msg.sender];
    uint256 execNonce = execNonces[executionHash];

    if (execNonce != 0 && execNonce > accountNonce) {
      revert ExecutionNotAuthorized();
    }

    // write executionHash to storage
    executions[msg.sender].set(executionHash, createdAt);

    execNonce = ++queueNonces[msg.sender];
    execNonces[executionHash] = execNonce;

    emit ExecutionInitiated(
      msg.sender,
      _target,
      _value,
      _callData,
      createdAt,
      execNonce
    );
  }

  /// @notice Skips an execution by advancing account nonce.
  /// @param _target The target address to call
  /// @param _value The value to send
  /// @param _callData The call data
  function skipExecution(
    address _target,
    uint256 _value,
    bytes calldata _callData
  ) external onlySmartAccount {
    bytes32 executionHash = _execDigest(_target, _value, _callData);
    uint256 nonce = execNonces[executionHash];

    if (nonce == 0) {
      revert ExecutionHashNotFound(executionHash);
    }

    uint256 accountNonce = ++nonces[msg.sender];

    if (nonce != accountNonce) {
      revert ExecutionNotAuthorized();
    }

    emit ExecutionSkipped(msg.sender, _target, _value, _callData, nonce);
  }

  /// @notice Checks if an account has pending executions.
  /// @param _account The account address
  /// @return true if the account has pending executions, false otherwise
  function hasPendingExecution(address _account) external view returns (bool) {
    return queueNonces[_account] > nonces[_account];
  }

  function onExecute(
    address,
    address _target,
    uint256,
    bytes calldata _callData
  ) internal virtual override returns (bytes memory hookData) {
    if (!this.isInitialized(msg.sender)) {
      revert UnauthorizedAccess();
    }

    bytes4 functionSig;

    if (_callData.length >= 4) {
      functionSig = bytes4(_callData[0:4]);
    }

    if (_target == address(this) && functionSig == this.execute.selector) {
      return abi.encode(PASS);
    }

    DelayConfig storage _config = configs[msg.sender];
    if (_config.whitelist.contains(_target)) {
      return abi.encode(PASS);
    }

    revert ExecutionNotAuthorized();
  }

  function onExecuteBatch(
    address,
    Execution[] calldata
  ) internal virtual override returns (bytes memory) {
    revert UnsupportedExecution();
  }

  function onExecuteFromExecutor(
    address _executor,
    address _target,
    uint256 _value,
    bytes calldata _callData
  ) internal virtual override returns (bytes memory hookData) {
    if (!this.isInitialized(msg.sender)) {
      revert UnauthorizedAccess();
    }

    bytes4 functionSig;

    if (_callData.length >= 4) {
      functionSig = bytes4(_callData[0:4]);
    }

    DelayConfig storage _config = configs[msg.sender];

    // check if call is a initExecution or skipExecution
    if (
      _target == address(this) &&
      (functionSig == this.initExecution.selector ||
        functionSig == this.skipExecution.selector)
    ) {
      return abi.encode(PASS);
    } else if (_config.whitelist.contains(_executor)) {
      return abi.encode(PASS);
    } else {
      bytes32 executionHash = _execDigestMemory(_target, _value, _callData);
      (bool success, uint256 createdAt) = executions[msg.sender].tryGet(
        executionHash
      );

      if (!success) revert ExecutionHashNotFound(executionHash);

      uint256 accountNonce = ++nonces[msg.sender];
      uint256 nonce = execNonces[executionHash];
      if (nonce != accountNonce) revert ExecutionNotAuthorized();

      uint256 executeAfter = createdAt + _config.cooldown;
      if (executeAfter > block.timestamp) revert ExecutionNotAuthorized();

      emit ExecutionSubmitted(msg.sender, _target, _value, _callData, nonce);

      return abi.encode(PASS);
    }
  }

  function onExecuteBatchFromExecutor(
    address,
    Execution[] calldata
  ) internal virtual override returns (bytes memory) {
    revert UnsupportedExecution();
  }

  function onInstallModule(
    address,
    uint256,
    address,
    bytes calldata
  ) internal virtual override returns (bytes memory) {
    return abi.encode(PASS);
  }

  function onUninstallModule(
    address,
    uint256,
    address,
    bytes calldata
  ) internal virtual override returns (bytes memory) {
    return abi.encode(PASS);
  }

  /*//////////////////////////////////////////////////////////////////////////
                                   EXECUTOR LOGIC
    //////////////////////////////////////////////////////////////////////////*/

  /// @notice Executes a single call.
  /// @param _account The account address
  /// @param _target The target address to call
  /// @param _value The value to send
  /// @param _callData The call data
  function execute(
    address _account,
    address _target,
    uint256 _value,
    bytes calldata _callData
  ) external {
    IERC7579Account(_account).executeFromExecutor(
      ModeLib.encodeSimpleSingle(),
      ExecutionLib.encodeSingle(_target, _value, _callData)
    );
  }

  /*//////////////////////////////////////////////////////////////////////////
                                     CHECKS
    //////////////////////////////////////////////////////////////////////////*/

  function onPostCheck(
    bytes calldata hookData
  ) internal virtual override returns (bool success) {
    if (keccak256(hookData) == keccak256(abi.encode(PASS))) {
      return true;
    }

    return false;
  }

  /*//////////////////////////////////////////////////////////////////////////
                                     METADATA
    //////////////////////////////////////////////////////////////////////////*/

  /// @notice The name of the module
  /// @return name The name of the module
  function name() external pure returns (string memory) {
    return "DelayedExecution";
  }

  /// @notice The version of the module
  /// @return version The version of the module
  function version() external pure returns (string memory) {
    return "0.0.1";
  }

  /// @notice Check if the module is of a certain type
  /// @param typeID The type ID to check
  /// @return true if the module is of the given type, false otherwise
  function isModuleType(uint256 typeID) external pure override returns (bool) {
    return typeID == TYPE_HOOK || typeID == TYPE_EXECUTOR;
  }

  function _execDigest(
    address to,
    uint256 value,
    bytes calldata callData
  ) internal pure returns (bytes32) {
    bytes memory _callData = callData;
    return _execDigestMemory(to, value, _callData);
  }

  function _execDigestMemory(
    address to,
    uint256 value,
    bytes memory callData
  ) internal pure returns (bytes32 digest) {
    digest = keccak256(abi.encodePacked(to, value, callData));
  }
}
