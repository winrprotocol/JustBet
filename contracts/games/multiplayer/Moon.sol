// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../core/Core.sol";

contract Moon is Core {
  /*==================================================== Events =============================================================*/

  event Created(uint256 indexed gameId, uint256 startTime);

  event Participated(
    uint256 indexed gameId,
    address player,
    uint256 amount,
    uint256 multiplier,
    address[2] tokens
  );

  event Claimed(address indexed player, uint256 gameId);

  event ClaimedBatch(uint256 indexed gameId, address[] players);

  event Settled(uint256 indexed gameId, uint256 multiplier);

  event UpdateHouseEdge(uint64 houseEdge);

  /*==================================================== Modifiers ==========================================================*/

  modifier whenNotClosed() {
    _createGame();

    uint256 spinStartTime = games[currentGameId].startTime + config.duration;
    require(block.timestamp < spinStartTime, "MOO: Game closed");

    _;
  }

  modifier isChoiceInLimits(uint256 _multiplier) {
    require(_multiplier > config.minMultiplier, "MOO: Choice out-range");
    require(_multiplier <= config.maxMultiplier, "MOO: Choice out-range");
    _;
  }

  /*==================================================== State Variables ====================================================*/

  enum Status {
    IDLE,
    STARTED,
    READY,
    FINISHED
  }

  struct Configuration {
    uint16 minMultiplier;
    uint16 maxMultiplier;
    uint16 duration;
    uint16 cooldown;
  }

  struct Bet {
    uint256 multiplier;
    uint256 amount;
    address[2] tokens;
  }

  struct Game {
    Status status;
    uint256 startTime;
    uint256 multiplier;
  }

  /// @notice house edge of game
  uint64 public houseEdge = 200;
  /// @notice game ids
  uint256 public currentGameId = 0;
  /// @notice duration to refund
  uint32 public refundCooldown = 2 hours; // default value
  /// @notice game list
  mapping(uint256 => Game) public games;
  /// @notice participant list of game
  mapping(uint256 => Bet[]) public participants;
  /// @notice game player claim pair
  mapping(uint256 => mapping(address => bool)) public claims;
  /// @notice holds total wager amounts according to currency
  mapping(uint256 => mapping(address => uint256)) public totalAmounts;
  /// @notice participant index list of game
  mapping(uint256 => mapping(address => uint256)) public participantIndex;
  /// @notice bet refunds
  mapping(uint256 => mapping(address => bool)) public refunds;

  /// @notice min multiplier 1.00, max multiplier 100.00
  /// @notice wagering duration 20s, cooldown duration after wagering closed 30s
  Configuration public config = Configuration(100, 10000, 20, 30);

  /// @notice randomizer request id and game id pair to find the game related with request
  mapping(uint256 => uint256) public requestGamePair;

  /*==================================================== Functions ===========================================================*/

  constructor(IRandomizerRouter _router) Core(_router) {}

  /// @notice updates configurations of the game
  /// @param _config Configuration
  function updateConfig(Configuration memory _config) external onlyGovernance {
    config = _config;
  }

  /// @notice function that calculation or return a constant of house edge
  /// @param _houseEdge edge percent of game eg. 1000 = 10.00
  function updateHouseEdge(uint64 _houseEdge) external onlyGovernance {
    houseEdge = _houseEdge;

    emit UpdateHouseEdge(_houseEdge);
  }

  /// @notice function to update refund cooldown
  /// @param _refundCooldown cooldown to refund
  function updateRefundCooldown(uint32 _refundCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
    refundCooldown = _refundCooldown;
  }

  /// @notice calculates reward according to winning multiplier
  /// @param _wager players wager for a game
  /// @param _multiplier chosen multiplier by player
  function calcReward(uint256 _wager, uint256 _multiplier) public pure returns (uint256 reward_) {
    reward_ = (_wager * (_multiplier * 1e16)) / PRECISION;
  }

  /// @notice gets the bets of player
  /// @param _gameId game id
  /// @param _player address
  function getParticipant(
    uint256 _gameId,
    address _player
  ) public view returns (uint256 index_, Bet memory bet_) {
    index_ = participantIndex[_gameId][_player];

    if (index_ != 0) {
      index_ -= 1;
      bet_ = participants[_gameId][index_];
    }
  }

  /// @notice creates new game if the previous has timed out
  function _createGame() internal {
    uint256 currentGameId_ = currentGameId;
    uint256 finishTime = games[currentGameId_].startTime + config.duration + config.cooldown;
    uint256 startTime_ = block.timestamp;

    /// @notice if the last game has finished
    if (startTime_ > finishTime) {
      currentGameId_++;

      /// @notice schedules random request for game for after wagering duration
      requestGamePair[_requestScheduledRandom(1, startTime_ + config.duration)] = currentGameId_;
      games[currentGameId_] = Game(Status.STARTED, startTime_, 0);
      currentGameId = currentGameId_;

      emit Created(currentGameId_, startTime_);
    }
  }

  /// @notice calculates winning amount of bet by splitting to token types
  /// @param _multiplier game
  /// @param _token game
  /// @param _participants game
  function collectWonAmounts(
    uint256 _multiplier,
    address _token,
    Bet[] memory _participants
  ) internal pure returns (uint256 wonAmounts_) {
    for (uint256 i = 0; i < _participants.length; i++) {
      if (_participants[i].multiplier <= _multiplier && _token == _participants[i].tokens[0]) {
        wonAmounts_ += _participants[i].amount;
      } else {
        break;
      }
    }
  }

  /// @notice calculates result of game by given random
  /// @param _random raw random number
  function getResult(uint256 _random) public view returns (uint256 multiplier_) {
    uint16 maxMultiplier_ = config.maxMultiplier;
    uint256 H = modNumber(_random, (maxMultiplier_ - config.minMultiplier + 1));
    uint256 E = maxMultiplier_ / 100;
    multiplier_ = (E * maxMultiplier_ - H) / (E * 100 - H);

    if (modNumber(_random, 66) == 0) {
      return 1;
    }

    if (multiplier_ == 0) {
      return config.minMultiplier;
    }
  }

  /// @notice randomizer consumer triggers that function
  /// @notice manages the game variables and shares the escrowed amount
  /// @param _requestId generated request id by randomizer
  /// @param _randoms raw random numbers sent by randomizers
  function randomizerFulfill(uint256 _requestId, uint256[] calldata _randoms) internal override {
    uint256 gameId_ = requestGamePair[_requestId];
    Game storage game_ = games[gameId_];
    require(
      block.timestamp < games[gameId_].startTime + refundCooldown,
      "MOO: FulFill is not allowed after the refund cooldown"
    );

    Bet[] memory participants_ = participants[gameId_];
    IVaultManager vaultManager_ = vaultManager;

    /// @notice gets currencies which are used to escrow wager
    address[] memory currencies = vaultManager_.getWhitelistedTokens();

    game_.multiplier = getResult(_randoms[0]);
    game_.status = Status.FINISHED;

    address token_;
    uint256 totalAmount_;
    uint256 wonAmounts_;

    for (uint256 i = 0; i < currencies.length; ++i) {
      token_ = currencies[i];
      wonAmounts_ = collectWonAmounts(game_.multiplier, token_, participants_);
      totalAmount_ = totalAmounts[gameId_][token_];

      if (totalAmount_ > wonAmounts_) {
        vaultManager_.payin(token_, totalAmount_ - wonAmounts_);
        totalAmounts[gameId_][token_] = wonAmounts_;
      }
    }

    emit Settled(gameId_, game_.multiplier);
  }

  /// @notice escrows tokens and writes the amounts
  /// @param _player address of player
  /// @param _wager amount for a game
  /// @param _tokens contains input and output token currencies
  function _escrow(address _player, uint256 _wager, address[2] memory _tokens) internal {
    IVaultManager vaultManager_ = vaultManager;

    /// @notice escrows total wager to Vault Manager
    vaultManager_.escrow(_tokens[0], _player, _wager);
    /// @notice mints the vWINR rewards
    vaultManager_.mintVestedWINR(_tokens[0], _wager, _player);
    /// @notice sets referral reward if player has referee
    vaultManager_.setReferralReward(_tokens[0], _player, _wager, houseEdge);

    totalAmounts[currentGameId][_tokens[0]] += _wager;
  }

  /// @notice makes bet for current game or creates if previous one is finished
  /// @param _wager amount for a game
  /// @param _multiplier choisen multiplayer by player
  /// @param _tokens contains input and output token currencies
  function bet(
    uint256 _wager,
    uint256 _multiplier,
    address[2] calldata _tokens
  )
    external
    nonReentrant
    isWagerAcceptable(_tokens[0], _wager)
    isChoiceInLimits(_multiplier)
    whenNotPaused
    whenNotClosed
  {
    address player_ = _msgSender();
    require(participantIndex[currentGameId][player_] == 0, "MOO: Bet cannot change");

    _escrow(player_, _wager, _tokens);

    /// @notice sets players bet to the list
    participants[currentGameId].push(Bet(_multiplier, _wager, _tokens));
    participantIndex[currentGameId][player_] = participants[currentGameId].length;

    emit Participated(currentGameId, player_, _wager, _multiplier, _tokens);
  }

  function refundGame(uint256 _gameId) external nonReentrant {
    address sender_ = _msgSender();
    (, Bet memory bet_) = getParticipant(_gameId, sender_);
    Game memory game_ = games[_gameId];

    require(game_.startTime + refundCooldown < block.timestamp, "Game is not refundable yet");
    require(game_.status != Status.FINISHED, "Game completed");
    require(!refunds[_gameId][sender_], "Already refunded");

    refunds[_gameId][sender_] = true;
    vaultManager.refund(bet_.tokens[0], bet_.amount, sender_);
    vaultManager.removeReferralReward(bet_.tokens[0], sender_, bet_.amount, houseEdge);
  }

  /// @notice transfer players winning
  /// @param _player amount for a game
  /// @param _bet contains input and output token currencies
  function _claim(address _player, Bet memory _bet) internal {
    uint256 reward_ = calcReward(_bet.amount, _bet.multiplier);
    vaultManager.payout(_bet.tokens, _player, _bet.amount, reward_);
  }

  /// @notice Called by player to claim profits of a game
  /// @param _gameId game id which wants to be claimed
  function claim(uint256 _gameId) external nonReentrant {
    address player_ = _msgSender();
    require(!claims[_gameId][player_], "MOO: Already claimed");
    (, Bet memory bet_) = getParticipant(_gameId, player_);
    require(bet_.multiplier <= games[_gameId].multiplier, "MOO: Lost");

    claims[_gameId][player_] = true;
    _claim(player_, bet_);

    emit Claimed(player_, _gameId);
  }

  /// @notice Called by nodes to send profits of players
  /// @param _gameId game id
  /// @param _players game id which wants to be claimed
  function claimBatch(uint256 _gameId, address[] memory _players) external nonReentrant {
    Game memory game_ = games[_gameId];
    require(game_.status == Status.FINISHED, "MOO: Game is not finished");
    for (uint256 i = 0; i < _players.length; ++i) {
      address player_ = _players[i];
      (, Bet memory bet_) = getParticipant(_gameId, _players[i]);
      require(!claims[_gameId][player_], "MOO: Already claimed");
      if (bet_.multiplier <= game_.multiplier && !claims[_gameId][player_]) {
        claims[_gameId][player_] = true;
        _claim(_players[i], bet_);
      }
    }

    emit ClaimedBatch(_gameId, _players);
  }
}
