// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../../interfaces/randomizer/IRandomizerRouter.sol";
import "../../interfaces/randomizer/providers/supra/ISupraRouter.sol";
import "../../interfaces/randomizer/providers/IRandomizerProvider.sol";
import "../Access.sol";

contract SupraProvider is Access, IRandomizerProvider {
  /*==================================================== State Variables ====================================================*/

  IRandomizerRouter public router;
  ISupraRouter public randomizer;
  address public walletAddress;
  mapping(uint256 => uint256) public routerRequestIds;

  constructor(ISupraRouter _randomizer) {
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    changeRandomizer(_randomizer);
  }

  /*==================================================== FUNCTIONS ===========================================================*/

  function setRouter(IRandomizerRouter _router) external onlyGovernance {
    router = _router;
    grantRole(ROUTER_ROLE, address(_router));
  }

  function changeRandomizer(ISupraRouter _randomizer) public onlyGovernance {
    randomizer = _randomizer;
    grantRole(RANDOMIZER_ROLE, address(_randomizer));
  }

  function changeWalletAddress(address _walletAddress) public onlyGovernance {
    walletAddress = _walletAddress;
  }

  function callback(uint256 _requestId, uint256[] calldata _rngList) external onlyRandomizer {
    uint256 _routerRequestId = routerRequestIds[_requestId];

    router.response(_routerRequestId, _rngList);
    delete routerRequestIds[_requestId];
  }

  function request(uint256 _routerRequestId, uint32 _count, uint256 minConfirmations) external onlyRouter returns (uint256 requestId_) {
    requestId_ = randomizer.generateRequest("callback(uint256,uint256[])", uint8(_count), minConfirmations, walletAddress);
    routerRequestIds[requestId_] = _routerRequestId;
  }
}
