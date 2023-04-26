// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Common.sol";

contract RPS is CommonSolo {
  /*==================================================== Events ==========================================================*/

  event UpdateHouseEdge(
    uint64 houseEdge
  );

  /*==================================================== Modifiers ==========================================================*/

  modifier isChoiceInsideLimits(bytes memory _gameData) {
    uint8 choice_ = decodeGameData(_gameData);
    require(choice_ >= 0 && choice_ < 3, "Choice isn't allowed");

    _;
  }

  /*==================================================== State Variables ====================================================*/

  enum Result {
    WIN,
    DRAW,
    LOSE
  }

  mapping(Result => uint256) public multipliers;
  /// @notice house edge of game
  uint64 public houseEdge = 200;

  /*==================================================== CONSTRUCTOR ===========================================================*/

  constructor(IRandomizerRouter _router) CommonSolo(_router) {
    multipliers[Result.WIN] = 196e16;
    multipliers[Result.DRAW] = 98e16;
  }

  /*==================================================== EXTERNAL FUNCTIONS ===========================================================*/

  /// @notice function that calculation or return a constant of house edge
  /// @param _houseEdge edge percent of game eg. 1000 = 10.00
  function updateHouseEdge(uint64 _houseEdge) external onlyGovernance {
    houseEdge = _houseEdge;

    emit UpdateHouseEdge(_houseEdge);
  }

  /// @notice function that calculation or return a constant of house edge
  /// @return edge_ calculated house edge of game
  function getHouseEdge(Game memory) public view override returns (uint64 edge_) {
    edge_ = houseEdge;
  }

  /// @notice updates win multiplier
  /// @param _result win, draw, lose
  /// @param _multiplier result's winning multipliplier
  function _updateWinMultiplier(Result _result, uint256 _multiplier) external onlyGovernance {
    multipliers[_result] = _multiplier;
  }

  /// @notice encodes choice of player
  /// @param _choice players choice 0, 1, 2 
  function encodeGameData(uint8 _choice) public pure returns (bytes memory) {
    return abi.encode(_choice);
  }

  /// @notice decodes game data
  /// @param _gameData encoded cohice
  /// @return choice_ 0, 1, 2
  function decodeGameData(bytes memory _gameData) public pure returns (uint8) {
    return abi.decode(_gameData, (uint8));
  }

  /// @notice calculates reward according to winning multiplier
  /// @param _result win, draw, lose
  /// @param _wager players wager for a game
  function calcReward(Result _result, uint256 _wager) public view returns (uint256 reward_) {
    reward_ = (_wager * multipliers[_result]) / PRECISION;
  }

  /// @notice shares the amount which escrowed amount while starting the game by player 
  /// @param _randoms raw random numbers sent by randomizers
  /// @return numbers_ modded numbers according to game
  function getResultNumbers(
    Game memory,
    uint256[] calldata _randoms
  ) internal pure override returns (
    uint256[] memory numbers_
  ) {
    numbers_ = modNumbers(_randoms, 3);
  }

  function abs(int x) private pure returns (int) {
    return x >= 0 ? x : -x;
  }

  /// @notice makes the decision about choice
  /// @param _choice players choice 0 or 1
  /// @param _result modded random number
  function isWon(uint16 _choice, uint256 _result) public pure returns (Result result_) {
    if (_choice == 0) {
      if (_result == 0) result_ = Result.DRAW;
      else if (_result == 1) result_ = Result.LOSE;
      else if (_result == 2) result_ = Result.WIN;
    }
    else if (_choice == 1) {
      if (_result == 0) result_ = Result.WIN;
      else if (_result == 1) result_ = Result.DRAW;
      else if (_result == 2) result_ = Result.LOSE;
    }
    else if (_choice == 2) {
      if (_result == 0) result_ = Result.LOSE;
      else if (_result == 1) result_ = Result.WIN;
      else if (_result == 2) result_ = Result.DRAW;
    }
  }

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
  ) public view override returns (
    uint256 payout_, 
    uint32 playedGameCount_, 
    uint256[] memory payouts_
  ) {
    payouts_ = new uint[](_game.count);
    playedGameCount_ = _game.count;
    uint8 choice_ = decodeGameData(_game.gameData);

    for (uint8 i = 0; i < _game.count; ++i) {
      Result _result = isWon(choice_, _resultNumbers[i]);
      uint256 _reward = calcReward(_result, _game.wager);
      int _payout = int256(_reward) - int256(_game.wager);

      if (abs(_payout) == int256(_game.wager)) {
       _payout = 0;
      }

      payouts_[i] = uint256(abs(_payout));
      payout_ += _reward;

      if (shouldStop(payout_, (i + 1) * _game.wager, _stopGain, _stopLoss)) {
        playedGameCount_ = i + 1;
        break;
      }
    }
  }

  /// @notice randomizer consumer triggers that function
  /// @notice manages the game variables and shares the escrowed amount
  /// @param _wager amount for a game 
  /// @param _count the selected game count by player
  /// @param _stopGain maximum profit limit
  /// @param _stopLoss maximum loss limit
  /// @param _gameData players decisions according to game
  /// @param _tokens contains input and output token currencies
  function bet(
    uint256 _wager, 
    uint8 _count,
    uint256 _stopGain,
    uint256 _stopLoss,
    bytes memory _gameData,
    address[2] memory _tokens
  ) external isChoiceInsideLimits(_gameData) {
    _create(
      _wager,
      _count,
      _stopGain,
      _stopLoss,
      _gameData,
      _tokens
    );
  }
}
