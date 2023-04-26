// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPriceFeed {
  function getPrice(address token) external view returns (uint256);
}
