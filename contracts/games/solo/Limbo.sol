// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Common.sol";

contract Limbo is CommonSolo {
  /*==================================================== Events ==========================================================*/

  event UpdateHouseEdge(
    uint64 houseEdge
  );

  /*==================================================== Modifiers ==========================================================*/

  modifier isChoiceInsideLimits(bytes memory _gameData) {
    uint32 choice_ = decodeGameData(_gameData);

    require(
      choice_ >= config.minMultiplier && choice_ <= config.maxMultiplier,
      "Choice isn't allowed"
    );
    _;
  }

  /*==================================================== State Variables ====================================================*/

  struct Configuration {
    uint32 minMultiplier;
    uint32 maxMultiplier;
  }

  Configuration public config = Configuration(100, 10000);
  /// @notice house edge of game
  uint64 public houseEdge = 200;

  /*==================================================== Functions ===========================================================*/

  constructor(IRandomizerRouter _router) CommonSolo(_router) {}

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

  /// @notice function that calculation or return a constant of house edge
  /// @return edge_ calculated house edge of game
  function getHouseEdge(Game memory) public view override returns (uint64 edge_) {
    edge_ = houseEdge;
  }

  /// @notice encodes choice of player
  /// @param _choice players choice 0 or 1
  function encodeGameData(uint32 _choice) public pure returns (bytes memory) {
    return abi.encode(_choice);
  }

  /// @notice decodes game data
  /// @param _gameData encoded cohice
  /// @return choice_ 100 to 10000(1.00 - 100.00)
  function decodeGameData(bytes memory _gameData) public pure returns (uint32) {
    return abi.decode(_gameData, (uint32));
  }

  /// @notice calculates reward according to winning multiplier
  /// @param _wager players wager for a game
  /// @param _multiplier chosen multiplier by player
  function calcReward(uint256 _wager, uint256 _multiplier) public pure returns (uint256 reward_) {
    reward_ = (_wager * (_multiplier * 1e16)) / PRECISION;
  }

  /// @notice makes the decision about choice
  /// @param _choice players choice
  /// @param _result modded random number
  function isWon(uint256 _choice, uint256 _result) public pure returns (bool won_) {
    if (_choice <= _result) return true;
  }

  /// @notice calculates result of game by given random
  /// @param _randoms raw random numbers
  function getResultNumbers(
    Game memory,
    uint256[] calldata _randoms
  ) internal view override returns (uint256[] memory numbers_) {
    uint256[] memory H = modNumbers(_randoms, (config.maxMultiplier - config.minMultiplier + 1));
    uint256 E = config.maxMultiplier / 100;

    uint256[] memory randoms_ = new uint256[](_randoms.length);
    for (uint256 i = 0; i < _randoms.length; i++) {
      uint256 _multiplier = (E * config.maxMultiplier - H[i]) / (E * 100 - H[i]);

      if (modNumber(_randoms[i], 66) == 0) {
        _multiplier = 1;
      }

      if (_multiplier == 0) {
        _multiplier = config.minMultiplier;
      }
      randoms_[i] = _multiplier;
    }
    numbers_ = randoms_;
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
  )
    public
    pure
    override
    returns (uint256 payout_, uint32 playedGameCount_, uint256[] memory payouts_)
  {
    payouts_ = new uint[](_game.count);
    playedGameCount_ = _game.count;

    uint256 choice_ = decodeGameData(_game.gameData);
    uint256 reward_ = calcReward(_game.wager, choice_);

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
    _create(_wager, _count, _stopGain, _stopLoss, _gameData, _tokens);
  }
}
