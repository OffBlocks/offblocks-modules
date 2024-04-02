// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title MockToken
 * @author OffBlocks Team
 * @notice Simple mock ERC20 token with mint and burn functionality
 */
contract MockToken is ERC20Burnable {
  /// @notice The number of decimals used by the token
  uint8 private immutable _decimals;

  /// @notice An event emitted when tokens are minted
  event Mint(address indexed to, uint256 amount);

  /// @notice An event emitted when tokens are burned
  event Burn(address indexed from, uint256 amount);

  /// @notice An error thrown when the decimals passed in a constructor are invalid
  error InvalidDecimals();

  /// @notice An error thrown when the initial supply passed in a constructor is invalid
  error InvalidInitialSupply();

  /// @notice An error thrown when the zero address is passed as an argument
  error ZeroAddress();

  /// @notice An error thrown when the zero amount is passed as an argument
  error ZeroAmount();

  /**
   * @notice The constructor for the MockToken
   * @param _name string memory - Name of the token
   * @param _symbol string memory - Symbol of the token
   * @param decimals_ uint8 - Decimals of the token
   * @param _initialSupply uint256 - Initial supply of the token
   */
  constructor(
    string memory _name,
    string memory _symbol,
    uint8 decimals_,
    uint256 _initialSupply
  ) ERC20(_name, _symbol) {
    if (decimals_ < 0 || decimals_ > 18) revert InvalidDecimals();
    if (_initialSupply == 0) revert InvalidInitialSupply();

    _decimals = decimals_;
    _mint(msg.sender, _initialSupply * (10 ** uint256(decimals_)));
  }

  /**
   * @notice Mints `_amount` tokens to the specified address
   * @param _to address - Address to mint tokens to
   * @param _amount uint256 - Amount of tokens to mint
   * @dev The caller cannot mint to the zero address
   * @dev The caller cannot mint 0 tokens
   * @dev Since this is a mock token, ability to mint is not restricted
   * @dev Emits a {Mint} event
   */
  function mint(address _to, uint256 _amount) external {
    if (_to == address(0)) revert ZeroAddress();
    if (_amount == 0) revert ZeroAmount();

    _mint(_to, _amount);

    emit Mint(_to, _amount);
  }

  /**
   * @notice Returns the number of decimals used by the token
   * @return uint8 - Number of decimals
   */
  function decimals() public view virtual override returns (uint8) {
    return _decimals;
  }
}
