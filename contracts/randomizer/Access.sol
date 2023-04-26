// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";

abstract contract Access is AccessControl {
  /*==================================================== Events ==========================================================*/

  event VaultManagerChange(address vaultManager);

  /*==================================================== Modifiers ==========================================================*/

  modifier onlyGovernance() {
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "RND: Not governance");
    _;
  }

  modifier onlyTeam() {
    require(hasRole(TEAM_ROLE, _msgSender()), "RND: Not team");
    _;
  }

  modifier onlyConsumer() {
    require(hasRole(CONSUMER_ROLE, _msgSender()), "RND: Not consumer");
    _;
  }

  modifier onlyProvider() {
    require(hasRole(PROVIDER_ROLE, _msgSender()), "RND: Not provider");
    _;
  }

  modifier onlyRouter() {
    require(hasRole(ROUTER_ROLE, _msgSender()), "RPR: Not router");
    _;
  }

  modifier onlyRandomizer() {
    require(hasRole(RANDOMIZER_ROLE, _msgSender()), "RPR: Not randomizer");
    _;
  }

  /*==================================================== State Variables ====================================================*/

  bytes32 public constant TEAM_ROLE = bytes32(keccak256("TEAM"));
  bytes32 public constant CONSUMER_ROLE = bytes32(keccak256("CONSUMER"));
  bytes32 public constant PROVIDER_ROLE = bytes32(keccak256("PROVIDER"));
  bytes32 public constant ROUTER_ROLE = bytes32(keccak256("ROUTER"));
  bytes32 public constant RANDOMIZER_ROLE = bytes32(keccak256("RANDOMIZER"));

  /*==================================================== FUNCTIONS ===========================================================*/

  constructor() {
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
  }
}
