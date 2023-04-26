// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../core/Core.sol";

contract Wheel is Core {
  /*==================================================== Events =============================================================*/

  event Created(uint256 indexed gameId, uint256 startTime);

  event Participated(
    uint256 indexed gameId,
    address player,
    uint256 amount,
    Color color,
    address[2] tokens
  );

  event Claimed(address indexed player, uint256 gameId);

  event ClaimedBatch(uint256 indexed gameId, address[] players);

  event Settled(uint256 indexed gameId, Color color, uint64 angle);

  event UpdateHouseEdge(uint64 houseEdge);

  /*==================================================== State Variables ====================================================*/

  enum Color {
    IDLE,
    GREY,
    BLUE,
    GREEN,
    RED
  }

  enum Status {
    IDLE,
    STARTED,
    SPIN,
    FINISHED
  }

  struct Configuration {
    uint16 duration;
    uint16 cooldown;
    uint64 unitHeight;
    uint64 range;
  }

  struct Bet {
    Color color;
    uint256 amount;
    address[2] tokens;
  }

  struct Game {
    Color color;
    Status status;
    uint256 startTime;
  }

  /// @notice house edge of game
  uint64 public houseEdge = 200;
  uint64 public startTime;
  /// @notice color list of wheel
  Color[] public units;
  /// @notice game ids
  uint256 public currentGameId = 0;
  /// @notice block count to refund
  uint32 public refundCooldown = 2 hours; // default value
  /// @notice game list
  mapping(uint256 => Game) public games;
  /// @notice holds total wager amounts according to currency and choice
  mapping(bytes => uint256) public amounts;
  /// @notice bet refunds
  mapping(uint256 => mapping(address => bool)) public refunds;
  /// @notice game player claim pair
  mapping(uint256 => mapping(address => bool)) public claims;
  /// @notice participant list of game
  mapping(uint256 => mapping(address => Bet)) public participants;
  /// @notice holds total wager amounts according to currency
  mapping(uint256 => mapping(address => uint256)) public totalAmounts;
  /// @notice wagering duration 20s, cooldown duration after wagering closed 30s
  /// @notice height of every single unit 360 / 49 = 7.3469387755102041, total height of wheel 360
  /// @notice in order to make the calculation precise, unit and range are scaled to 17640
  Configuration public config = Configuration(20, 30, 1296000, 63504000);
  /// @notice color's multiplier pair
  mapping(Color => uint64) public multipliers;
  /// @notice randomizer request id and game id pair to find the game related with request
  mapping(uint256 => uint256) public requestGamePair;

  /*==================================================== Functions ===========================================================*/

  constructor(IRandomizerRouter _randomizerRouter) Core(_randomizerRouter) {
    // Default Multipliers
    multipliers[Color.RED] = 4800;
    multipliers[Color.GREEN] = 600;
    multipliers[Color.BLUE] = 300;
    multipliers[Color.GREY] = 200;

    // Default Units, Length: 49
    units = [
      Color.GREY,
      Color.BLUE,
      Color.GREY,
      Color.GREEN,
      Color.GREY,
      Color.BLUE,
      Color.GREY,
      Color.BLUE,
      Color.GREY,
      Color.GREEN,
      Color.GREY,
      Color.BLUE,
      Color.GREY,
      Color.BLUE,
      Color.GREY,
      Color.GREEN,
      Color.GREY,
      Color.BLUE,
      Color.GREY,
      Color.BLUE,
      Color.GREY,
      Color.GREEN,
      Color.GREY,
      Color.BLUE,
      Color.GREY,
      Color.BLUE,
      Color.GREY,
      Color.GREEN,
      Color.GREY,
      Color.BLUE,
      Color.GREY,
      Color.GREEN,
      Color.GREY,
      Color.BLUE,
      Color.GREY,
      Color.BLUE,
      Color.GREY,
      Color.GREEN,
      Color.GREY,
      Color.BLUE,
      Color.GREY,
      Color.BLUE,
      Color.GREY,
      Color.GREEN,
      Color.GREY,
      Color.BLUE,
      Color.GREY,
      Color.BLUE,
      Color.RED
    ];
  }

  /// @notice function to update refund block count
  /// @param _refundCooldown block count to refund
  function updaterefundCooldown(uint32 _refundCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
    refundCooldown = _refundCooldown;
  }

  /// @notice updates multiplier of color
  /// @param _color color id
  /// @param _multiplier winning multiplier of color
  function updateColorMultiplier(Color _color, uint64 _multiplier) public onlyGovernance {
    multipliers[_color] = _multiplier;
  }

  /// @notice updates configurations of the game
  /// @param _config Configuration
  function updateConfigAndUnits(
    Configuration calldata _config,
    Color[] calldata _units
  ) external onlyGovernance whenPaused {
    require(_config.unitHeight != 0, "WHE: unit height can't be zero");
    require(_config.range != 0, "WHE: range can't be zero");
    require(
      _config.range / _config.unitHeight == _units.length,
      "WHE: does not match with units length"
    );

    config = _config;
    units = _units;
  }

  /// @notice function that calculation or return a constant of house edge
  /// @param _houseEdge edge percent of game eg. 1000 = 10.00
  function updateHouseEdge(uint64 _houseEdge) external onlyGovernance {
    houseEdge = _houseEdge;

    emit UpdateHouseEdge(_houseEdge);
  }

  /// @notice calculates reward according to winning multiplier
  /// @param _wager players wager for a game
  /// @param _color chosen color by player
  function calcReward(uint256 _wager, Color _color) public view returns (uint256 reward_) {
    reward_ = (_wager * multipliers[_color]) / 1e2;
  }

  /// @notice calculates reward according to winning multiplier
  /// @param _random raw random number
  function getUnit(uint256 _random) public view returns (uint64 angle_, uint64 index_) {
    Configuration memory config_ = config;

    angle_ = uint64(_random % config_.range);
    index_ = uint64((angle_ - (angle_ % config_.unitHeight)) / config_.unitHeight);
  }

  /// @notice calculates reward according to winning multiplier
  /// @param _gameId played game id
  /// @param _token address of input
  /// @param _color choice
  function generateCurrencyId(
    uint256 _gameId,
    address _token,
    Color _color
  ) internal pure returns (bytes memory id_) {
    id_ = abi.encode(_gameId, _token, _color);
  }

  /// @notice randomizer consumer triggers that function
  /// @notice manages the game variables and shares the escrowed amount
  /// @param _requestId generated request id by randomizer
  /// @param _randoms raw random numbers sent by randomizers
  function randomizerFulfill(uint256 _requestId, uint256[] calldata _randoms) internal override {
    /// @notice checks whether the game is finished
    uint256 gameId_ = requestGamePair[_requestId];
    require(games[gameId_].status == Status.STARTED, "WHE: Game finished");
    require(
      block.timestamp < games[gameId_].startTime + refundCooldown,
      "WHE: FulFill is not allowed after the refund cooldown"
    );

    /// @notice finds the color
    (uint64 angle_, uint64 index_) = getUnit(_randoms[0]);
    Color color_ = units[index_];
    IVaultManager vaultManager_ = vaultManager;

    /// @notice gets currencies which are used to escrow wager
    address[] memory currencies = vaultManager_.getWhitelistedTokens();

    bytes memory currencyId;
    address token_;
    uint256 amount_;
    uint256 totalAmount_;

    /// @notice decreases winning amounts from total amounts
    /// @notice and transfers the amounts to vault
    for (uint8 i = 0; i < currencies.length; ++i) {
      token_ = currencies[i];
      currencyId = generateCurrencyId(gameId_, token_, color_);
      amount_ = amounts[currencyId];
      totalAmount_ = totalAmounts[gameId_][token_];

      if (totalAmount_ > amount_) {
        vaultManager.payin(token_, totalAmount_ - amount_);
        totalAmounts[gameId_][token_] = amount_;
      }
    }

    /// @notice closes the game
    games[gameId_].color = color_;
    games[gameId_].status = Status.FINISHED;

    emit Settled(gameId_, color_, angle_);
  }

  /// @notice creates new game if the previous has timed out
  function _createGame() internal {
    uint256 currentGameId_ = currentGameId;
    uint256 finishTime_ = games[currentGameId_].startTime + config.duration + config.cooldown;
    uint256 startTime_ = block.timestamp;

    /// @notice if the last game has finished
    if (startTime_ > finishTime_) {
      currentGameId_++;

      /// @notice schedules random request for game for after wagering duration
      uint256 requestId_ = _requestScheduledRandom(1, startTime_ + config.duration);

      requestGamePair[requestId_] = currentGameId_;

      games[currentGameId_] = Game(Color.IDLE, Status.STARTED, startTime_);

      emit Created(currentGameId_, startTime_);

      currentGameId = currentGameId_;
    }
  }

  /// @notice gets current game
  function getCurrentGame() external view returns (Game memory) {
    Game memory game_ = games[currentGameId];
    uint256 spinStartTime;

    unchecked {
      spinStartTime = game_.startTime + config.duration;
    }

    /// @notice if wagering time is finished, wheel should spin
    if (block.timestamp >= spinStartTime && game_.status == Status.STARTED) {
      game_.status = Status.SPIN;
    }

    return game_;
  }

  /// @notice escrows tokens and writes the amounts
  /// @param _player address of player
  /// @param _wager amount for a game
  /// @param _color selected color by player
  /// @param _tokens contains input and output token currencies
  function _escrow(
    address _player,
    uint256 _wager,
    Color _color,
    address[2] memory _tokens
  ) internal {
    IVaultManager vaultManager_ = vaultManager;
    bytes memory currencyId = generateCurrencyId(currentGameId, _tokens[0], _color);

    unchecked {
      totalAmounts[currentGameId][_tokens[0]] += _wager;
      amounts[currencyId] += _wager;
    }

    /// @notice escrows total wager to Vault Manager
    vaultManager_.escrow(_tokens[0], _player, _wager);
    /// @notice mints the vWINR rewards
    vaultManager_.mintVestedWINR(_tokens[0], _wager, _player);
    /// @notice sets referral reward if player has referee
    vaultManager_.setReferralReward(_tokens[0], _player, _wager, houseEdge);
  }

  /// @notice makes bet for current game or creates if previous one is finished
  /// @param _wager amount for a game
  /// @param _color selected color by player
  /// @param _tokens contains input and output token currencies
  function bet(
    uint256 _wager,
    Color _color,
    address[2] memory _tokens
  ) external nonReentrant isWagerAcceptable(_tokens[0], _wager) whenNotPaused {
    _createGame();
    uint256 spinStartTime = games[currentGameId].startTime + config.duration;
    require(block.timestamp < spinStartTime, "WHE: Game closed");
    require(_color != Color.IDLE, "Choose a color");
    address player_ = _msgSender();
    uint256 currentGameId_ = currentGameId;
    require(participants[currentGameId_][player_].amount == 0, "Bet cannot change");

    _escrow(player_, _wager, _color, _tokens);

    /// @notice sets players bet to the list
    participants[currentGameId_][player_] = Bet(_color, _wager, _tokens);

    emit Participated(currentGameId_, player_, _wager, _color, _tokens);
  }

  function refundGame(uint256 _gameId) external nonReentrant {
    address sender_ = _msgSender();
    Bet storage bet_ = participants[_gameId][sender_];
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
    vaultManager.payout(_bet.tokens, _player, _bet.amount, calcReward(_bet.amount, _bet.color));
  }

  /// @notice Called by player to claim profits of a game
  /// @param _gameId game id which wants to be claimed
  function claim(uint256 _gameId) external nonReentrant {
    address sender_ = _msgSender();
    Game memory game_ = games[_gameId];
    Bet memory bet_ = participants[_gameId][sender_];

    require(!claims[_gameId][sender_], "WHE: Already claimed");
    require(game_.status == Status.FINISHED, "Game hasn't finished yet");
    require(bet_.color == game_.color, "WHE: Lost");

    claims[_gameId][sender_] = true;
    _claim(sender_, bet_);

    emit Claimed(sender_, _gameId);
  }

  /// @notice Called by nodes to send profits of players
  /// @param _gameId game id which wants to be claimed
  /// @param _players game id which wants to be claimed
  function claimBatch(uint256 _gameId, address[] memory _players) external nonReentrant {
    Game memory game_ = games[_gameId];
    require(game_.status == Status.FINISHED, "WHE: Game is not finished");
    for (uint256 i = 0; i < _players.length; i++) {
      address player_ = _players[i];
      Bet memory bet_ = participants[_gameId][player_];
       require(!claims[_gameId][player_], "WHE: Already claimed");
      if (game_.color == bet_.color && !claims[_gameId][player_]) {
        claims[_gameId][player_] = true;
        _claim(player_, bet_);
      }
    }

    emit ClaimedBatch(_gameId, _players);
  }
}
