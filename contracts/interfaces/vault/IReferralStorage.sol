// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IReferralStorage {
  function setReward(address _player, address _token, uint256 _amount) external;
   function removeReward(address _player, address _token, uint256 _amount) external; 
}
