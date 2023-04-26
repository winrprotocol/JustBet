// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Common.sol";

contract CoinFlip is CommonSolo {
  /*==================================================== Events ==========================================================*/

  event UpdateHouseEdge(
    uint256 multiplier,
    uint64 houseEdge
  );

  /*==================================================== Modifiers ==========================================================*/

  modifier isChoiceInsideLimits(bytes memory _gameData) {
    uint8 choice_ = decodeGameData(_gameData);

    require(choice_ == 0 || choice_ == 1, "Choice isn't allowed");
    _;
  }

  /*==================================================== State Variables ====================================================*/

  /// @notice contains 2 * 0.98 = 2% house edge
  uint256 public winMultiplier = 196e16;
  /// @notice house edge of game
  uint64 public houseEdge = 200;

  /*==================================================== Functions ===========================================================*/

  constructor(IRandomizerRouter _router) CommonSolo(_router) {}

  /// @notice updates win multiplier
  /// @param _winMultiplier winning multipliplier
  function updateWinMultiplier(uint256 _winMultiplier, uint64 _houseEdge) external onlyGovernance {
    require(_winMultiplier >= 1e18, "_multiplier should be greater than or equal to 1e18");
    require(_houseEdge >= 0, "_houseEdge should be greater than or equal to 0");

    winMultiplier = _winMultiplier;
    houseEdge = _houseEdge;
  
    emit UpdateHouseEdge(_winMultiplier, _houseEdge);
  }

  /// @notice function that calculation or return a constant of house edge
  /// @return edge_ calculated house edge of game
  function getHouseEdge(Game memory) public view override returns (uint64 edge_) {
    edge_ = houseEdge;
  }

  /// @notice encodes choice of player
  /// @param _choice players choice 0 or 1
  function encodeGameData(uint8 _choice) public pure returns (bytes memory) {
    return abi.encode(_choice);
  }

  /// @notice decodes game data
  /// @param _gameData encoded cohice
  /// @return choice_ 0 or 1
  function decodeGameData(bytes memory _gameData) public pure returns (uint8) {
    return abi.decode(_gameData, (uint8));
  }

  /// @notice calculates reward according to winning multiplier
  /// @param _wager players wager for a game
  function calcReward(uint256 _wager) public view returns (uint256 reward_) {
    reward_ = (_wager * winMultiplier) / PRECISION;
  }

  /// @notice makes the decision about choice
  /// @param _choice players choice 0 or 1
  /// @param _result modded random number
  function isWon(uint8 _choice, uint256 _result) public pure returns (bool won_) {
    won_ = (_choice == 1) ? (_result == 1) : (_result == 0);
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
    numbers_ = modNumbers(_randoms, 2);
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
    uint256 reward_ = calcReward(_game.wager);

    for (uint8 i = 0; i < _game.count; ++i) {
      if (isWon(choice_, _resultNumbers[i])) {
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
