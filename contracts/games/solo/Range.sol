// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Common.sol";

contract Range is CommonSolo {
  /*==================================================== Events ==========================================================*/

  event UpdateHouseEdge(
    uint256 multiplier,
    uint64 houseEdge
  );

  /*==================================================== Modifiers ==========================================================*/

  modifier isChoiceInsideLimits(bytes memory _gameData) {
    (uint8 choice_,) = decodeGameData(_gameData);

    require(choice_ >= 5 && choice_ <= 95, "Choice isn't allowed");
    _;
  }

  /*==================================================== State Variables ====================================================*/

  uint32 public range = 100;
  uint256 public houseEdgeMultiplier = 98e16;
  /// @notice house edge of game
  uint64 public houseEdge = 200;

  constructor(IRandomizerRouter _router) CommonSolo(_router) {}

  /*==================================================== EXTERNAL FUNCTIONS ===========================================================*/

  /// @notice function that calculation or return a constant of house edge
  /// @param _multiplier multiplier seperated from house edge
  /// @param _houseEdge edge percent of game eg. 1000 = 10.00
  function updateHouseEdge(uint256 _multiplier, uint64 _houseEdge) external onlyGovernance {
    houseEdgeMultiplier = _multiplier;
    houseEdge = _houseEdge;

    emit UpdateHouseEdge(_multiplier, _houseEdge);
  }

  /// @notice function that calculation or return a constant of house edge
  /// @return edge_ calculated house edge of game
  function getHouseEdge(Game memory) public view override returns (uint64 edge_) {
    edge_ = houseEdge;
  }

  /// @notice encodes choice of player
  /// @param _choice players choice between 5-95
  /// @param _over if the value is true, the game inside 0-choice. if not the game inside choice-100
  function encodeGameData(uint8 _choice,  bool _over) public pure returns (bytes memory) {
    return abi.encode(_choice, _over);
  }

  /// @notice decodes game data
  /// @param _gameData encoded cohice
  /// @return choice_ players choice between 5-95
  /// @return over_ if the value is true, the game inside 0-choice. if not the game inside choice-100
  function decodeGameData(bytes memory _gameData) public pure returns (uint8, bool) {
    return abi.decode(_gameData, (uint8, bool));
  }

  /// @notice makes the decision about choice
  /// @param _choice players choice 0 or 1
  /// @param _over if the value is true, the game inside 0-choice. if not the game inside choice-100
  /// @param _result modded random number
  function isWon(bool _over, uint16 _choice, uint256 _result) public pure returns (bool won_) {
    won_ = _over ? (_result >= 1 && _result <= _choice) : (_result >= _choice && _result <= 100);
  }

  /// @notice calculates selection range for choices
  /// @param _choice players choice between 5-95
  /// @param _over if the value is true, the game inside 0-choice. if not the game inside choice-100
  function calcSelectionRange(uint256 _choice, bool _over) public pure returns (uint256 selectionRange_) {
    if (_over) {
      selectionRange_ = _choice;
    } else {
      selectionRange_ = 100 - _choice;
    }
  }

  /// @notice calculates winning multiplier for choices
  /// @param _choice players choice between 5-95
  /// @param _over if the value is true, the game inside 0-choice. if not the game inside choice-100
  function calcWinMultiplier(uint256 _choice, bool _over) public view returns (uint256 winMultiplier_) {
    winMultiplier_ = (range * PRECISION) / calcSelectionRange(_choice, _over);
    winMultiplier_ = (winMultiplier_ * houseEdgeMultiplier) / PRECISION;
  }

  /// @notice calculates reward for choices
  /// @param _choice players choice between 5-95
  /// @param _over if the value is true, the game inside 0-choice. if not the game inside choice-100
  /// @param _wager players wager for a game
  function calcReward(uint256 _choice, bool _over, uint256 _wager) public view returns (uint256 reward_) {
    reward_ = (_wager * calcWinMultiplier(_choice, _over)) / PRECISION;
  }

  /// @notice shares the amount which escrowed amount while starting the game by player 
  /// @param _randoms raw random numbers sent by randomizers
  /// @return numbers_ modded numbers according to game
  function getResultNumbers(
    Game memory,
    uint256[] calldata _randoms
  ) internal view override returns (
    uint256[] memory numbers_
  ) {
    numbers_ = modNumbers(_randoms, range);
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

    (uint8 choice_, bool over_) = decodeGameData(_game.gameData);
    uint256 reward_ = calcReward(choice_, over_, _game.wager);

    for (uint8 i = 0; i < _game.count; ++i) {
      /// @notice adds 1 to number because the range is 1-100 not 0-100
      if (isWon(over_, choice_, _resultNumbers[i] + 1)) {
        payouts_[i] = reward_ - _game.wager;
        payout_ += reward_;
      }

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
