// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Number.sol";

abstract contract InternalRNG is NumberHelper {
  /*==================================================== State Variables ====================================================*/

  uint32 private randNonce;

  /*==================================================== FUNCTIONS ===========================================================*/

  function getRandom(uint256 _seed, uint32 _nonce) internal returns(uint) {
    return uint(keccak256(abi.encodePacked(_seed, _nonce)));
  }

  function _getRandomNumbers(
    uint256 _seed, 
    uint32 _length, 
    uint32 _mod) internal returns (uint256[] memory) {
    uint256[] memory randoms_ = new uint[](_length);
    uint32 randNonce_ = randNonce;
    uint32 index_ = 1;

    randoms_[0] = modNumber(_seed, _mod);

    while (index_ != _length) {
      randoms_[index_] = modNumber(getRandom(_seed, randNonce_ + index_), _mod);

      index_++;
    }

    randNonce += index_;

    return randoms_;
  }
}
