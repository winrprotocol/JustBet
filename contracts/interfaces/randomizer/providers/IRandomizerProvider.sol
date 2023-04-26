// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IRandomizerProvider {
  function request(uint256 _requestId, uint32 _count, uint256 minConfirmations) external returns (uint256);
}
