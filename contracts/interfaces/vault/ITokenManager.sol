// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ITokenManager {
  function mintVestedWINR(address _input, uint256 _amount, address _recipient) external;
  function increaseVolume(address _input, uint256 _amount) external;
  function decreaseVolume(address _input, uint256 _amount) external;
}
