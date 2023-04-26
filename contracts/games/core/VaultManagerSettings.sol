// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../../interfaces/vault/IFeeCollector.sol";
import "../../interfaces/vault/IPriceFeed.sol";
import "../../interfaces/vault/ITokenManager.sol";
import "../../interfaces/vault/IReferralStorage.sol";
import "../../interfaces/vault/IVault.sol";

/// @dev Additional settings of vault manager
contract VaultManagerSettings is Pausable, AccessControl {
  /*==================================================== Events =============================================================*/

  event TokensUpdated(address[] tokens);
  event GameAdded(address game);
  event GameRemoved(address game);
  event MaxWagerPercentChanged(uint256 percent);

  /*==================================================== Modifiers ===========================================================*/

  modifier onlyWhitelistedToken(address _token) {
    require(whitelistedTokens[_token], "VM: unknown token");
    _;
  }

  modifier onlyWhitelistedTokens(address[2] memory _tokens) {
    require(whitelistedTokens[_tokens[0]], "VM: unknown input token");
    require(whitelistedTokens[_tokens[1]], "VM: unknown output token");
    _;
  }

  modifier onlyGovernance() {
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "VM: Not governance");
    _;
  }

  modifier onlyGame() {
    require(hasRole(GAME_ROLE, _msgSender()), "VM: Not game");
    _;
  }

  modifier onlyVault() {
    require(hasRole(VAULT_ROLE, _msgSender()), "VM: Not vault");
    _;
  }

  /*==================================================== State Variables ====================================================*/

  /// @notice WLP token address
  IERC20 public wlp;
  /// @notice Vault address
  IVault public vault;
  /// @notice Price feed address
  IPriceFeed public priceFeed;
  /// @notice Fee collector address
  IFeeCollector public feeCollector;
  /// @notice Token manager address
  ITokenManager public tokenManager;
  /// @notice Whitelisted token list
  address[] public whitelistedTokenList;
  /// @notice Referral storage address
  IReferralStorage public referralStorage;
  /// @notice The percent of token is max wager
  uint256 public maxWagerPercent = 1e15;
  /// @notice used to calculate precise decimals
  uint256 public constant PRECISION = 1e18;
  /// @notice Whitelisted games
  mapping(address => bool) public whitelistedGames;
  /// @notice Whitelisted tokens
  mapping(address => bool) public whitelistedTokens;
  /// @notice stores minimum wager in dollar for whitelisted games
  mapping(address => uint256) public minWagers;
  /// @notice GAME ROLE seed
  bytes32 public constant GAME_ROLE = bytes32(keccak256("GAME"));
  /// @notice VAULT ROLE seed
  bytes32 public constant VAULT_ROLE = bytes32(keccak256("VAULT"));

  /*====================================================  Functions ===========================================================*/

  constructor() {
    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
  }

  function setWlp(IERC20 _wlp) external onlyGovernance {
    wlp = _wlp;
  }

  function setVault(IVault _vault) external onlyGovernance {
    if (address(vault) != address(0)) {
      revokeRole(VAULT_ROLE, address(vault));
    }

    vault = _vault;
    grantRole(VAULT_ROLE, address(_vault));
  }

  function setReferralStorage(IReferralStorage _referralStorage) external onlyGovernance {
    referralStorage = _referralStorage;
  }

  function setPriceFeed(IPriceFeed _priceFeed) external onlyGovernance {
    priceFeed = _priceFeed;
  }

  function setFeeCollector(IFeeCollector _feeCollector) external onlyGovernance {
    feeCollector = _feeCollector;
  }

  function setTokenManager(ITokenManager _tokenManager) external onlyGovernance {
    tokenManager = _tokenManager;
  }

  function setMaxWagerPercent(uint256 _maxWagerPercent) external onlyGovernance {
    maxWagerPercent = _maxWagerPercent;

    emit MaxWagerPercentChanged(_maxWagerPercent);
  }

  /// @notice sets whitelisted tokens to storage
  /// @param _nextTokens address list
  function setWhitelistedTokens(address[] memory _nextTokens) external onlyGovernance {
    address[] memory currentList_ = whitelistedTokenList;

    delete whitelistedTokenList;
    for(uint256 i = 0; i < currentList_.length; i++) {
      delete whitelistedTokens[currentList_[i]];
    }

    whitelistedTokenList = _nextTokens;
    for(uint256 i = 0; i < _nextTokens.length; i++) {
      whitelistedTokens[whitelistedTokenList[i]] = true;
    }

    emit TokensUpdated(whitelistedTokenList);
  }

  /// @notice fetches whitelisted tokens
  function getWhitelistedTokens() public view returns (address[] memory whitelistedTokenList_) {
    whitelistedTokenList_ = whitelistedTokenList;
  }

  /// @notice adds game to the whitelist
  /// @param _game address
  function setWhitelistedGame(address _game) external onlyGovernance {
    grantRole(GAME_ROLE, _game);
    whitelistedGames[_game] = true;

    emit GameAdded(_game);
  }

  /// @notice removes game to from the whitelist
  /// @param _game address
  function unsetWhitelistedGame(address _game) external onlyGovernance {
    revokeRole(GAME_ROLE, _game);
    delete whitelistedGames[_game];

    emit GameRemoved(_game);
  }

  function pause() external onlyGovernance {
    _pause();
  }

  function unpause() external onlyGovernance {
    _unpause();
  }
}
