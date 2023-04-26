// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Common.sol";

contract Dice is CommonSolo {
  /*==================================================== Events ==========================================================*/

  event UpdateHouseEdge(
    uint64 houseEdge
  );

  /*==================================================== Modifiers ==========================================================*/

  modifier isChoiceInsideLimits(bytes memory _gameData) {
    uint8[] memory choices_ = decodeGameData(_gameData);

    require(choices_.length <= 5, "Choice count too high");

    for (uint256 i = 0; i < choices_.length; i++) {
      require(choices_[i] < 6, "Choice isn't allowed");
    }

    _;
  }

  /*==================================================== State Variables ====================================================*/

  /// @notice house edge of game
  uint64 public houseEdge = 200;
  mapping(uint8 => uint24) public multipliers;

  /*==================================================== CONSTRUCTOR ===========================================================*/

  constructor(IRandomizerRouter _router) CommonSolo(_router) {
    multipliers[1] = 5880;
    multipliers[2] = 2940;
    multipliers[3] = 1960;
    multipliers[4] = 1470;
    multipliers[5] = 1176;
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

  /// @notice encodes choices of player
  /// @return _choices selected side's by player
  function encodeGameData(uint8[] memory _choices) public pure returns (bytes memory) {
    return abi.encode(_choices);
  }

  /// @notice decodes game data
  /// @param _gameData encoded choices
  /// @return choices_ selected side's by player
  function decodeGameData(bytes memory _gameData) public pure returns (uint8[] memory) {
    return abi.decode(_gameData, (uint8[]));
  }
  /// @notice updates win multiplier
  /// @param _sideCount multiplier changes according to side count
  /// @param _multiplier multiplier
  function updateWinMultiplier(uint8 _sideCount, uint24 _multiplier) external onlyGovernance {
    require(_multiplier >= 1, "_multiplier should be greater than or equal to 1");
    require(_sideCount <= 5, "side count can't be greater than 5");

    multipliers[_sideCount] = _multiplier;
  }

  /// @notice updates win multiplier
  /// @param _sideCount multiplier changes according to side count
  /// @param _wager players wager for a game
  function calcReward(uint8 _sideCount, uint256 _wager) public view returns (uint256 reward_) {
    reward_ = (_wager * multipliers[_sideCount]) / 1e3;
  }

  /// @notice shares the amount which escrowed amount while starting the game by player
  /// @param _randoms raw random numbers sent by randomizers
  /// @return numbers_ modded numbers according to game
  function getResultNumbers(
    Game memory,
    uint256[] calldata _randoms
  ) internal pure override returns (uint256[] memory numbers_) {
    numbers_ = modNumbers(_randoms, 6);
  }

  function abs(int x) private pure returns (int) {
    return x >= 0 ? x : -x;
  }

  /// @notice makes the decision about choices
  /// @param _choices selected side's by player
  /// @param _result modded random number
  function isWon(uint8[] memory _choices, uint256 _result) public pure returns (bool result_) {
    for (uint8 i = 0; i < _choices.length; ++i) {
      if (_choices[i] == _result) {
        result_ = true;
        break;
      }
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
  )
    public
    view
    override
    returns (uint256 payout_, uint32 playedGameCount_, uint256[] memory payouts_)
  {
    payouts_ = new uint[](_game.count);
    playedGameCount_ = _game.count;

    uint8[] memory choices_ = decodeGameData(_game.gameData);
    uint256 reward_ = calcReward(uint8(choices_.length), _game.wager);

    for (uint8 i = 0; i < _game.count; ++i) {
      if (isWon(choices_, _resultNumbers[i])) {
        int _payout = int256(reward_) - int256(_game.wager);
        payouts_[i] = uint256(abs(_payout));
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
