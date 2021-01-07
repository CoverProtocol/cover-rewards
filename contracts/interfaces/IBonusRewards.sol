// SPDX-License-Identifier: NONE

pragma solidity ^0.8.0;

/**
 * @title Cover Protocol Bonus Token Rewards Interface
 * @author crypto-pumpkin
 */
interface IBonusRewards {
  event Deposit(address indexed miner, address indexed lpToken, uint256 amount);
  event Withdraw(address indexed miner, address indexed lpToken, uint256 amount);

  struct Pool {
    address bonusToken; // the external bonus token, like CRV
    uint256 startTime;
    uint256 endTime;
    uint256 weeklyRewards; // total amount to be distributed from start to end
    uint256 accRewardsPerToken; // accumulated bonus to the lastUpdated Time
    uint256 lastUpdatedAt; // last accumulated bonus update timestamp
  }

  struct Miner {
    uint256 amount;
    uint256 rewardsWriteoff; // the amount of bonus tokens to write off when calculate rewards from last update
  }

  function getPoolList() external view returns (address[] memory);

  function updatePool(address _lpToken) external;
  function updatePools(uint256 _start, uint256 _end) external;
  function deposit(address _lpToken, uint256 _amount) external;
  function withdraw(address _lpToken, uint256 _amount) external;
  function emergencyWithdraw(address _lpToken) external;
  function addBonus(
    address _lpToken,
    address _bonusToken,
    uint256 _startTime,
    uint256 _weeklyRewards,
    uint256 _transferAmount
  ) external;
  function extendBonus(address _lpToken, uint256 _transferAmount) external;
  // collect to owner
  function collectDust(address _lpToken) external;

  // only owner
  function addPoolsAndAllowBonus(address[] calldata _lpTokens, address _bonusToken, address[] calldata _authorizers) external;
}
