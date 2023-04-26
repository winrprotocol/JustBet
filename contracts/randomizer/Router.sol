// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/randomizer/IRandomizerRouter.sol";
import "../interfaces/randomizer/IRandomizerConsumer.sol";
import "../interfaces/randomizer/providers/IRandomizerProvider.sol";
import "./Access.sol";

contract RandomizerRouter is Access, IRandomizerRouter {
  /*==================================================== Events =============================================================*/

  event RequestCreated (
    uint256 indexed requestId,
    address consumer,
    address provider,
    uint32 count
  );

  event ScheduledRequestCreated (
    uint256 indexed requestId,
    address consumer,
    address provider,
    uint32 count,
    uint256 originTargetTime
  );

  event Triggered (
    uint256 indexed requestId
  );

  event ReRequested (
    uint256 indexed requestId,
    address consumer,
    address provider
  );

  event Fulfilled (
    uint256 indexed requestId,
    address consumer,
    address provider,
    uint256[] randoms
  );

  /*=================================================== Modifiers ===========================================================*/

  modifier onlyNotFilled(uint256 _requestId) {
    require(requests[_requestId].provider != address(0), "RND: Already filled");
    _;
  }

  /*==================================================== State Variables ====================================================*/

  struct Request {
    uint32 count;
    IRandomizerConsumer consumer;
    address provider;
    uint256 minConfirmations;
    uint256 targetTime;
  }

  mapping(uint32 => IRandomizerProvider) public providers;
  mapping(uint256 => Request) public requests;
  uint256 public requestIds = 1;
  uint32 public defaultProviderId;

  /*==================================================== FUNCTIONS ===========================================================*/

  /// @notice adds provider and grants
  /// @param _id id of provider
  /// @param _provider provider address
  function setProvider(uint32 _id, IRandomizerProvider _provider) external onlyGovernance() {
    providers[_id] = _provider;
    _grantRole(PROVIDER_ROLE, address(_provider));
  }

  /// @notice gets default provider address
  function getDefaultProvider() internal view returns (IRandomizerProvider provider) {
    provider = providers[defaultProviderId];
  }

  /// @notice changes default provider
  /// @param _id of provider
  function updateDefaultProvider(uint32 _id) external onlyGovernance() {
    require(address(providers[_id]) != address(0), "RND: Provider not found");
    defaultProviderId = _id;
  }

  /// @notice adds request to list
  /// @param _provider address
  /// @param _count random number count
  /// @param _targetTime if the request is scheduled, if not pass (0)
  function _addRequest(
    IRandomizerProvider _provider, 
    uint32 _count, 
    uint256 _targetTime, 
    uint256 _minConfirmations
  ) internal returns (uint256 requestId_) {
    requests[requestIds] = Request(
      _count, 
      IRandomizerConsumer(_msgSender()), 
      address(_provider), 
      _minConfirmations,
      _targetTime
    );

    requestId_ = requestIds;
    requestIds++;
  }

  /// @notice requests immeadiate random number(s)
  /// @param _count random number count
  /// @param _minConfirmations min confirmation count that rng should wait till
  function request(uint32 _count, uint256 _minConfirmations) external onlyConsumer returns (uint256 requestId_) {
    IRandomizerProvider provider_ = getDefaultProvider();
    provider_.request(requestIds, _count, _minConfirmations);

    requestId_ = _addRequest(provider_, _count, 0, _minConfirmations);

    emit RequestCreated(requestId_, _msgSender(), address(provider_), _count);
  }

  /// @notice requests scheduled random number(s)
  /// @param _count random number count
  /// @param _targetTime target time of rng response
  function scheduledRequest(uint32 _count, uint256 _targetTime) external onlyConsumer returns (uint256 requestId_) {
    IRandomizerProvider provider_ = getDefaultProvider();

    requestId_ = _addRequest(provider_, _count, _targetTime, 0);

    emit ScheduledRequestCreated(
      requestId_,
      _msgSender(),
      address(provider_),
      _count,
      _targetTime
    );
  }

  /// @notice triggers scheduled requests
  /// @param _requestId of scheduled request
  function trigger(
    uint256 _requestId
  ) external onlyNotFilled(_requestId) {
    Request memory request_ = requests[_requestId];
    require(request_.targetTime != 0, "RND: Not scheduled");
    require(block.timestamp >= request_.targetTime, "RND: Not time");
    IRandomizerProvider(request_.provider).request(_requestId, request_.count, 0);

    emit Triggered(_requestId);
  }

  /// @notice re-call for not filled requests
  /// @param _requestId of scheduled request
  function reRequest(uint256 _requestId) external onlyNotFilled(_requestId) 
  {
    Request memory request_ = requests[_requestId];
    IRandomizerProvider(request_.provider).request(_requestId, request_.count, request_.minConfirmations);

    emit ReRequested(_requestId, _msgSender(), request_.provider);
  }

  /// @notice re-call for not filled requests by changing provider
  /// @param _requestId of scheduled request
  /// @param _providerId one of the providers id
  function reRequest(
    uint256 _requestId,
    uint32 _providerId
  ) external onlyTeam onlyNotFilled(_requestId) 
  {
    Request memory request_ = requests[_requestId];
    IRandomizerProvider provider_ = providers[_providerId];

    requests[_requestId].provider = address(provider_);
    provider_.request(_requestId, request_.count, request_.minConfirmations);

    emit ReRequested(_requestId, _msgSender(), requests[_requestId].provider);
  }

  /// @notice provider response
  /// @param _requestId of request
  /// @param _rngList random number list
  function response(
    uint256 _requestId, 
    uint256[] calldata _rngList
  ) external onlyProvider onlyNotFilled(_requestId)
  {
    Request memory request_ = requests[_requestId];
    request_.consumer.randomizerCallback(_requestId, _rngList);

    delete requests[_requestId];

    emit Fulfilled(
      _requestId, 
      address(request_.consumer), 
      _msgSender(), 
      _rngList
    );
  }
}
