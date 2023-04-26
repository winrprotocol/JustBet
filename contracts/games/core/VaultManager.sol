// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./VaultManagerSettings.sol";

/// @dev This contract designed to easing token transfers broadcasting information between contracts
contract VaultManager is VaultManagerSettings {
  using SafeERC20 for IERC20;
  /*==================================================== Events ===========================================================*/

  event Escrow(address sender, address token, uint256 amount);
  event Payback(address recipient, address token, uint256 amount);
  event Withdraw(address token, uint256 amount);
  event Refunded(address game, address player, address token, uint256 amount);

  /*==================================================== State ===========================================================*/

  uint32 public constant BASIS_POINTS = 1e4;
  mapping(address => uint256) public totalEscrowTokens;

  /*==================================================== Internal ===========================================================*/

  function _increaseEscrow(address _token, uint256 _amount) internal {
    totalEscrowTokens[_token] += _amount;
  }

  function _decreaseEscrow(address _token, uint256 _amount) internal {
    totalEscrowTokens[_token] -= _amount;
  }

  /*==================================================== External ===========================================================*/

  /// @notice escrow tokens into the manager
  /// @param _token one of the whitelisted tokens which is collected in settings
  /// @param _sender holder of tokens
  /// @param _amount the amount of token
  function escrow(
    address _token,
    address _sender,
    uint256 _amount
  ) public onlyGame onlyWhitelistedToken(_token) {
    _increaseEscrow(_token, _amount);
    tokenManager.increaseVolume(_token, _amount);
    transferIn(_token, _sender, _amount);

    emit Escrow(_sender, _token, _amount);
  }

  /// @notice function that assign reward of referral
  /// @param _token one of the whitelisted tokens which is collected in settings
  /// @param _player holder of tokens
  /// @param _amount the amount of token
  /// @param _houseEdge edge percent of game eg. 1000 = 10.00
  function setReferralReward(
    address _token,
    address _player,
    uint256 _amount,
    uint64 _houseEdge
  ) public onlyGame onlyWhitelistedToken(_token) {
    if (_amount > 0) {
      referralStorage.setReward(_player, _token, ((_amount * _houseEdge) / BASIS_POINTS));
    }
  }

  function removeReferralReward(
    address _token,
    address _player,
    uint256 _amount,
    uint64 _houseEdge
  ) public onlyGame onlyWhitelistedToken(_token) {
    referralStorage.removeReward(_player, _token, ((_amount * _houseEdge) / BASIS_POINTS));
  }

  function refund(address _token, uint256 _amount, address _player) public onlyGame {
    _decreaseEscrow(_token, _amount);
    tokenManager.decreaseVolume(_token, _amount);

    transferOut(_token, _player, _amount);

    emit Refunded(_msgSender(), _player, _token, _amount);
  }

  /// @notice release some amount of escrowed tokens
  /// @param _token one of the whitelisted tokens which is collected in settings
  /// @param _recipient holder of tokens
  /// @param _amount the amount of token
  function payback(address _token, address _recipient, uint256 _amount) public onlyGame {
    _decreaseEscrow(_token, _amount);
    transferOut(_token, _recipient, _amount);

    emit Payback(_recipient, _token, _amount);
  }

  /// @notice lets vault get wager amount from escrowed tokens
  /// @param _token one of the whitelisted tokens which is collected in settings
  /// @param _amount the amount of token
  function getEscrowedTokens(
    address _token,
    uint256 _amount
  ) public onlyVault onlyWhitelistedToken(_token) {
    _decreaseEscrow(_token, _amount);
    IERC20(_token).safeTransfer(address(vault), _amount);

    emit Withdraw(_token, _amount);
  }

  /// @notice lets vault get wager amount from escrowed tokens
  function payout(
    address[2] memory _tokens,
    address _recipient,
    uint256 _escrowAmount,
    uint256 _totalAmount
  ) public onlyGame {
    vault.payout(_tokens, address(this), _escrowAmount, _recipient, _totalAmount);
  }

  /// @notice lets vault get wager amount from escrowed tokens
  function payin(
    address _token,
    uint256 _escrowAmount
  ) public onlyGame onlyWhitelistedToken(_token) {
    vault.payin(_token, address(this), _escrowAmount);
  }

  /// @notice transfers any whitelisted token into here
  /// @param _token one of the whitelisted tokens which is collected in settings
  /// @param _sender holder of tokens
  /// @param _amount the amount of token
  function transferIn(
    address _token,
    address _sender,
    uint256 _amount
  ) public onlyGame onlyWhitelistedToken(_token) {
    IERC20(_token).safeTransferFrom(_sender, address(this), _amount);
  }

  /// @notice transfers any whitelisted token to recipient
  /// @param _token one of the whitelisted tokens which is collected in settings
  /// @param _recipient of tokens
  /// @param _amount the amount of token
  function transferOut(
    address _token,
    address _recipient,
    uint256 _amount
  ) public onlyGame onlyWhitelistedToken(_token) {
    IERC20(_token).safeTransfer(_recipient, _amount);
  }

  /// @notice used to mint vWINR to recipient
  /// @param _input currency of payment
  /// @param _amount of wager
  /// @param _recipient recipient of vWINR
  function mintVestedWINR(address _input, uint256 _amount, address _recipient) public onlyGame {
    tokenManager.mintVestedWINR(_input, _amount, _recipient);
  }

  function getPrice(address _token) public view returns (uint256 price_) {
    price_ = vault.getDollarValue(_token);
  }

  function getEscrowedValue() public view returns (uint256 pendingWagerValue_) {
    address[] memory tokenList_ = whitelistedTokenList;

    for (uint256 i = 0; i < tokenList_.length; i++) {
      pendingWagerValue_ +=
        (IERC20(tokenList_[i]).balanceOf(address(this)) * getPrice(tokenList_[i])) /
        (10 ** IERC20Metadata(tokenList_[i]).decimals());
    }
  }

  function getMaxWager() external view returns (uint256 maxWager_) {
    maxWager_ = (vault.getReserve() * maxWagerPercent) / PRECISION;
    uint256 pending_ = getEscrowedValue();

    if (maxWager_ > pending_) {
      maxWager_ -= pending_;
    } else {
      maxWager_ = 0;
    }
  }

  function getMinWager(address _game) external view returns (uint256) {
    return minWagers[_game];
  }

  function setMinWagers(
    address[] calldata _games,
    uint256[] calldata _minWagers
  ) external onlyGovernance {
    require(_games.length == _minWagers.length, "Lengths must be equal");

    for (uint256 i = 0; i < _games.length; i++) {
      minWagers[_games[i]] = _minWagers[i];
    }
  }
}
