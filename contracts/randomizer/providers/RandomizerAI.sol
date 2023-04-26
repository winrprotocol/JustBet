// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../../interfaces/randomizer/IRandomizerRouter.sol";
import "../../interfaces/randomizer/providers/randomizerai/IRandomizer.sol";
import "../../interfaces/randomizer/providers/IRandomizerProvider.sol";
import "../../games/helpers/InternalRNG.sol";
import "../Access.sol";

contract RandomizerAiProvider is Access, IRandomizerProvider, InternalRNG {

  /*==================================================== State Variables ====================================================*/

  IRandomizerRouter public router;
  IRandomizer public randomizer;
  uint32 public callbackGasLimit = 5000000;
  mapping(uint256 => uint256) public routerRequestIds;
  mapping(uint256 => uint32) public counts; 

  constructor(IRandomizer _randomizer) {
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    changeRandomizer(_randomizer);
  }

  /*==================================================== FUNCTIONS ===========================================================*/

  function setCallbackGasLimit(uint32 _callbackGasLimit) external onlyGovernance {
    callbackGasLimit = _callbackGasLimit;
  }

  function setRouter(IRandomizerRouter _router) external onlyGovernance {
    router = _router;
    grantRole(ROUTER_ROLE, address(_router));
  }

  function changeRandomizer(IRandomizer _randomizer) public onlyGovernance {
    randomizer = _randomizer;
    grantRole(RANDOMIZER_ROLE, address(_randomizer));
  }

  function callback(uint256 _requestId, uint256[] memory _rngList) internal {
    uint256 _routerRequestId = routerRequestIds[_requestId];

    router.response(_routerRequestId, _rngList);
    delete routerRequestIds[_requestId];
  }

  function randomizerCallback(uint256 _requestId, bytes32 _value) external onlyRandomizer {
    uint32 count_ = counts[_requestId];
    uint256[] memory randoms_ = new uint[](count_);
    uint256 random_ = uint256(_value);

    if (count_ == 1) {
      randoms_[0] = random_;
    } else {
      randoms_ = _getRandomNumbers(random_, count_, 0);
    }

    callback(_requestId, randoms_);
    delete counts[_requestId];
  }

  function request(uint256 _routerRequestId, uint32 _count, uint256) external onlyRouter returns (uint256 requestId_) {
    requestId_ = randomizer.request(callbackGasLimit);
    counts[requestId_] = _count;
    routerRequestIds[requestId_] = _routerRequestId;
  }
}
