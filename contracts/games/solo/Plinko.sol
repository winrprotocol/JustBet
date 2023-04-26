// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Common.sol";
import "../helpers/InternalRNG.sol";

contract Plinko is CommonSolo, InternalRNG {
  /*==================================================== Modifiers ==========================================================*/

  modifier isRowInsideLimits(bytes memory _gameData) {
    uint32 _rows = decodeGameData(_gameData);

    require(_rows >= rowLimits.min && _rows <= rowLimits.max, "Rows out-range");
    _;
  }

  /*==================================================== State Variables ====================================================*/

  struct RowLimits {
    uint32 min;
    uint32 max;
  }

  RowLimits public rowLimits = RowLimits(6, 12);

  mapping(uint32 => uint32[]) public multipliers;
  /// @notice house edges of game
  mapping(uint32 => uint64) public houseEdges;

  constructor(IRandomizerRouter _router) CommonSolo(_router) {
    // Pre defined multipliers
    multipliers[6] = [1000, 100, 70, 40, 70, 100, 1000];
    multipliers[7] = [1500, 250, 70, 40, 40, 70, 250, 1500];
    multipliers[8] = [2050, 400, 90, 60, 40, 60, 90, 400, 2050];
    multipliers[9] = [4500, 800, 90, 60, 40, 40, 60, 90, 800, 4500];
    multipliers[10] = [4700, 800, 200, 90, 60, 40, 60, 90, 200, 800, 4700];
    multipliers[11] = [6500, 1700, 400, 90, 60, 40, 40, 60, 90, 400, 1700, 6500];
    multipliers[12] = [7000, 1600, 300, 200, 90, 60, 40, 60, 90, 200, 300, 1600, 7000];

    // Pre defined houseEdges
    houseEdges[6] = 468;
    houseEdges[7] = 437;
    houseEdges[8] = 211;
    houseEdges[9] = 226;
    houseEdges[10] = 206;
    houseEdges[11] = 202;
    houseEdges[12] = 202;
  }

  /*==================================================== Functions ===========================================================*/

  /// @notice updates row multipliers
  /// @param _index row count
  /// @param _multipliers of row. generally 1 more or same size
  function updateMultipliers(uint32 _index, uint32[] memory _multipliers, uint64 _houseEdge) external onlyGovernance {
    require(_multipliers.length == _index + 1, "insufficient _multipliers length");

    multipliers[_index] = _multipliers;
    houseEdges[_index] = _houseEdge;
  }

  /// @notice function that calculation or return a constant of house edge
  /// @return edge_ calculated house edge of game
  function getHouseEdge(Game memory _game) public view override returns (uint64 edge_) {
    uint32 rows_ = decodeGameData(_game.gameData);

    edge_ = houseEdges[rows_];
  }

  /// @notice encodes choices of player
  /// @return _rows selected row count by player
  function encodeGameData(uint32 _rows) public pure returns (bytes memory) {
    return abi.encode(_rows);
  }

  /// @notice decodes game data
  /// @param _gameData encoded choices
  /// @return rows_ selected row count by player
  function decodeGameData(bytes memory _gameData) public pure returns (uint32) {
    return abi.decode(_gameData, (uint32));
  }

  /// @notice updates row selection limits
  /// @param _min minimum selectable row
  /// @param _max maxiumum selectable row
  function updateRowLimits(uint32 _min, uint32 _max) external onlyGovernance {
    for (uint32 i = _min; i < _max; ++i) {
      require(multipliers[i].length != 0, "multipliers doesn't exist");
    }
    rowLimits = RowLimits(_min, _max);
  }

  /// @notice returns row multipliers
  /// @param _rows row count
  function getMultipliers(uint32 _rows) public view returns (uint32[] memory multipliers_) {
    multipliers_ = multipliers[_rows];
  }

  /// @notice returns multiplier according to row's index
  /// @param _rows row count
  /// @param _index multiplier index
  function getMultiplier(uint32 _rows, uint32 _index) public view returns (uint32 multiplier_) {
    multiplier_ = multipliers[_rows][_index];
  }

  /// @notice calculates reward according to given index's multiplier
  /// @param _rows row count
  /// @param _index multiplier index
  /// @param _wager players wager for a game
  function calcReward(
    uint32 _rows,
    uint32 _index,
    uint256 _wager
  ) public view returns (uint256 reward_) {
    reward_ = (_wager * getMultiplier(_rows, _index)) / 1e2;
  }

  /// @notice shares the amount which escrowed amount while starting the game by player
  /// @param _game request's game
  /// @param _randoms raw random numbers sent by randomizers
  /// @return numbers_ modded numbers according to game
  function getResultNumbers(
    Game memory _game,
    uint256[] calldata _randoms
  ) internal override returns (uint256[] memory numbers_) {
    uint32 rows_ = decodeGameData(_game.gameData);
    numbers_ = new uint256[](_game.count * rows_);
    uint256 random_;
    uint32 randomIndex_;

    /// @notice generates count * row number random numbers
    for (uint8 i = 0; i < _randoms.length; ++i) {
      random_ = _randoms[i];
      randomIndex_ = i * rows_;

      for (uint8 s = 0; s < rows_; ++s) {
        numbers_[randomIndex_] = random_ & (1 << s);
        randomIndex_ += 1;
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
    payouts_ = new uint256[](_game.count);
    playedGameCount_ = _game.count;

    uint32 rows_ = decodeGameData(_game.gameData);
    uint32 index_ = rows_;
    uint32 gameIndex_;

    for (uint32 i = 0; i < _resultNumbers.length; i++) {
      /// @notice calculates the final index by moving the ball movements sequentially on the index
      if (_resultNumbers[i] == 0) {
        index_--;
      } else {
        index_++;
      }

      if ((i + 1) % rows_ == 0) {
        gameIndex_ = i / rows_;

        payouts_[gameIndex_] = calcReward(rows_, index_ / 2, _game.wager);
        payout_ += payouts_[gameIndex_];

        if (shouldStop(payout_, (gameIndex_ + 1) * _game.wager, _stopGain, _stopLoss)) {
          playedGameCount_ = gameIndex_ + 1;
          break;
        }

        index_ = rows_;
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
  ) external isRowInsideLimits(_gameData) {
    _create(_wager, _count, _stopGain, _stopLoss, _gameData, _tokens);
  }
}
