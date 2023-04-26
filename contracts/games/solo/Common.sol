// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../core/Core.sol";

abstract contract CommonSolo is Core {
  /*==================================================== Events =============================================================*/

  event Created(address indexed player, uint256 requestId, uint256 wager, address[2] tokens);

  event Settled(
    address indexed player,
    uint256 requestId,
    uint256 wager,
    bool won,
    uint256 payout,
    uint32 playedGameCount,
    uint256[] numbers,
    uint256[] payouts
  );

  /*==================================================== Modifiers ==========================================================*/

  modifier isGameCountAcceptable(uint256 _gameCount) {
    require(_gameCount > 0, "Game count out-range");
    require(_gameCount <= maxGameCount, "Game count out-range");
    _;
  }

  modifier isGameCreated(uint256 _requestId) {
    require(games[_requestId].player != address(0), "Game is not created");
    _;
  }

  modifier whenNotCompleted(uint256 _requestId) {
    require(!completedGames[_requestId], "Game is completed");
    completedGames[_requestId] = true;
    _;
  }

  /*==================================================== State Variables ====================================================*/

  struct Game {
    uint8 count;
    address player;
    bytes gameData;
    uint256 wager;
    uint256 startTime;
    address[2] tokens;
  }

  struct Options {
    uint256 stopGain;
    uint256 stopLoss;
  }

  /// @notice maximum selectable game count
  uint8 public maxGameCount = 100;
  /// @notice cooldown duration to refund
  uint32 public refundCooldown = 2 hours; // default value
  /// @notice stores all games
  mapping(uint256 => Game) public games;
  /// @notice stores randomizer request ids game pair
  mapping(uint256 => Options) public options;
  mapping(uint256 => bool) public completedGames;

  /*==================================================== Functions ===========================================================*/

  constructor(IRandomizerRouter _router) Core(_router) {}

  /// @notice updates max game count
  /// @param _maxGameCount maximum selectable count
  function updateMaxGameCount(uint8 _maxGameCount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    maxGameCount = _maxGameCount;
  }

  /// @notice function to update refund block count
  /// @param _refundCooldown duration to refund
  function updateRefundCooldown(uint32 _refundCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
    refundCooldown = _refundCooldown;
  }

  /// @notice checks the profit and loss amount to stop the game when reaches the limits
  /// @param _total total gain accumulated from all games
  /// @param _wager total wager used
  /// @param _stopGain maximum profit limit
  /// @param _stopLoss maximum loss limit
  function shouldStop(
    uint256 _total,
    uint256 _wager,
    uint256 _stopGain,
    uint256 _stopLoss
  ) public pure returns (bool stop_) {
    if (_stopGain != 0 && _total > _wager) {
      stop_ = _total - _wager >= _stopGain; // total gain >= stop gain
    } else if (_stopLoss != 0 && _wager > _total) {
      stop_ = _wager - _total >= _stopLoss; // total loss >= stop loss
    }
  }

  /// @notice if the game is stopped due to the win and loss limit,
  /// @notice this calculates the unused and used bet amount
  /// @param _count the selected game count by player
  /// @param _usedCount played game count by game contract
  /// @param _wager amount for a game
  function calcWager(
    uint256 _count,
    uint256 _usedCount,
    uint256 _wager
  ) public pure returns (uint256 usedWager_, uint256 unusedWager_) {
    usedWager_ = _usedCount * _wager;
    unusedWager_ = (_count * _wager) - usedWager_;
  }

  /// @notice function to refund uncompleted game wagers
  function refundGame(uint256 _requestId) external nonReentrant whenNotCompleted(_requestId) {
    Game memory game = games[_requestId];
    require(game.player == _msgSender(), "Only player");
    require(
      game.startTime + refundCooldown < block.timestamp,
      "Game is not refundable yet"
    );

    delete games[_requestId];

    vaultManager.refund(game.tokens[0], game.wager * game.count, game.player);
  }

  /// @notice shares the amount which escrowed amount while starting the game by player
  /// @param _game player's game
  /// @param _playedGameCount played game count by game contract
  /// @param _payout accumulated payouts by game contract
  function shareEscrow(
    Game memory _game,
    uint256 _playedGameCount,
    uint256 _payout
  ) internal virtual returns (bool) {
    (uint256 usedWager_, uint256 unusedWager_) = calcWager(
      _game.count,
      _playedGameCount,
      _game.wager
    );
    /// @notice sets referral reward if player has referee
    vaultManager.setReferralReward(_game.tokens[0], _game.player, usedWager_, getHouseEdge(_game));
    vaultManager.mintVestedWINR(_game.tokens[0], usedWager_, _game.player);

    /// @notice this call transfers the unused wager to player
    if (unusedWager_ != 0) {
      vaultManager.payback(_game.tokens[0], _game.player, unusedWager_);
    }

    /// @notice calculates the loss of user if its not zero transfers to Vault
    if (_payout == 0) {
      vaultManager.payin(_game.tokens[0], usedWager_);
    } else {
      vaultManager.payout(_game.tokens, _game.player, usedWager_, _payout);
    }

    /// @notice The used wager is the zero point. if the payout is above the wager, player wins
    return _payout > usedWager_;
  }

  /// @notice shares the amount which escrowed amount while starting the game by player
  /// @param _game request's game
  /// @param _randoms raw random numbers sent by randomizers
  /// @return numbers_ modded numbers according to game
  function getResultNumbers(
    Game memory _game,
    uint256[] calldata _randoms
  ) internal virtual returns (uint256[] memory numbers_);

  /// @notice function that calculation or return a constant of house edge
  /// @param _game request's game
  /// @return edge_ calculated house edge of game
  function getHouseEdge(Game memory _game) public view virtual returns (uint64 edge_);

  /// @notice game logic contains here, decision mechanism
  /// @param _game request's game
  /// @param _resultNumbers modded numbers according to game
  /// @param _stopGain maximum profit limit
  /// @param _stopLoss maximum loss limit
  /// @return payout_ _payout accumulated payouts by game contract
  /// @return playedGameCount_  played game count by game contract
  /// @return payouts_ profit calculated at every step of the game, wager excluded
  function play(
    Game memory _game,
    uint256[] memory _resultNumbers,
    uint256 _stopGain,
    uint256 _stopLoss
  )
    public
    view
    virtual
    returns (uint256 payout_, uint32 playedGameCount_, uint256[] memory payouts_);

  /// @notice randomizer consumer triggers that function
  /// @notice manages the game variables and shares the escrowed amount
  /// @param _requestId generated request id by randomizer
  /// @param _randoms raw random numbers sent by randomizers
  function randomizerFulfill(
    uint256 _requestId,
    uint256[] calldata _randoms
  )
    internal
    override
    isGameCreated(_requestId)
    whenNotCompleted(_requestId)
    nonReentrant
  {
    Game memory game_ = games[_requestId];
    Options memory options_ = options[_requestId];
    uint256[] memory resultNumbers_ = getResultNumbers(game_, _randoms);
    (uint256 payout_, uint32 playedGameCount_, uint256[] memory payouts_) = play(
      game_,
      resultNumbers_,
      options_.stopGain,
      options_.stopLoss
    );

    emit Settled(
      game_.player,
      _requestId,
      game_.wager,
      shareEscrow(game_, playedGameCount_, payout_),
      payout_,
      playedGameCount_,
      resultNumbers_,
      payouts_
    );

    delete games[_requestId];
    delete options[_requestId];
  }

  /// @notice randomizer consumer triggers that function
  /// @notice manages the game variables and shares the escrowed amount
  /// @param _wager amount for a game
  /// @param _count the selected game count by player
  /// @param _stopGain maximum profit limit
  /// @param _stopLoss maximum loss limit
  /// @param _gameData players decisions according to game
  /// @param _tokens contains input and output token currencies
  function _create(
    uint256 _wager,
    uint8 _count,
    uint256 _stopGain,
    uint256 _stopLoss,
    bytes memory _gameData,
    address[2] memory _tokens
  )
    internal
    isGameCountAcceptable(_count)
    isWagerAcceptable(_tokens[0], _wager)
    whenNotPaused
    nonReentrant
  {
    address player_ = _msgSender();
    uint256 requestId_ = _requestRandom(_count);

    /// @notice escrows total wager to Vault Manager
    vaultManager.escrow(_tokens[0], player_, _count * _wager);

    games[requestId_] = Game(
      _count,
      player_,
      _gameData,
      _wager,
      block.timestamp,
      _tokens
    );

    if (_stopGain != 0 || _stopLoss != 0) {
      options[requestId_] = Options(_stopGain, _stopLoss);
    }

    emit Created(player_, requestId_, _wager, _tokens);
  }
}
