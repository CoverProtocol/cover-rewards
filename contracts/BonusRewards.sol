// SPDX-License-Identifier: NONE

pragma solidity ^0.8.0;

import "./utils/Ownable.sol";
import "./utils/ReentrancyGuard.sol";
import "./utils/SafeERC20.sol";
import "./interfaces/IBonusRewards.sol";

/**
 * @title Cover Protocol Bonus Token Rewards contract
 * @author crypto-pumpkin
 */
contract BonusRewards is IBonusRewards, Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20;

  uint256 private constant WEEK = 7 days;
  uint256 private constant CAL_MULTIPLIER = 1e12; // help calculate rewards/bonus PerToken only. 1e12 will allow meaningful $1 deposit in a $1bn pool
  bool public paused;
  address[] private responders;
  address[] private poolList;
  // lpToken => Pool
  mapping(address => Pool) private pools;
  // lpToken => User address => User data
  mapping(address => mapping(address => User)) private users;
  // bonus token => [] allowed authorizers to add bonus tokens
  mapping(address => address[]) private allowedTokenAuthorizers;
  // bonusTokenAddr => 1, used to avoid collecting bonus token when not ready
  mapping(address => uint8) private bonusTokenAddrMap;

  modifier notPaused() {
    require(!paused, "BonusRewards: paused");
    _;
  }

  function getPoolList() external view override returns (address[] memory) {
    return poolList;
  }

  function getPool(address _lpToken) external view override returns (Pool memory) {
    return pools[_lpToken];
  }

  function viewRewards(address _lpToken, address _user) public view override returns (uint256[] memory) {
    Pool memory pool = pools[_lpToken];
    User memory user = users[_lpToken][_user];
    uint256[] memory rewards = new uint256[](pool.bonuses.length);
    if (user.amount <= 0) return rewards;

    for (uint256 i = 0; i < rewards.length; i ++) {
      Bonus memory bonus = pool.bonuses[i];
      if (bonus.startTime < block.timestamp && bonus.remBonus > 0) {
        uint256 lpTotal = IERC20(_lpToken).balanceOf(address(this));
        uint256 bonusForTime = _calRewardsForTime(bonus, pool.lastUpdatedAt);
        uint256 bonusPerToken = bonus.accRewardsPerToken + bonusForTime / lpTotal;
        uint256 rewardsWriteoff = user.rewardsWriteoffs.length == i ? 0 : user.rewardsWriteoffs[i];
        rewards[i] = user.amount * bonusPerToken / CAL_MULTIPLIER - rewardsWriteoff;
      }
    }
    return rewards;
  }

  function getUser(address _lpToken, address _account) external view override returns (User memory, uint256[] memory) {
    return (users[_lpToken][_account], viewRewards(_lpToken, _account));
  }

  function getAuthorizers(address _bonusTokenAddr) external view override returns (address[] memory) {
    return allowedTokenAuthorizers[_bonusTokenAddr];
  }

  function getResponders() external view override returns (address[] memory) {
    return responders;
  }

  /// @notice update pool's bonus per staked token till current block timestamp
  function updatePool(address _lpToken) public override {
    Pool storage pool = pools[_lpToken];
    if (block.timestamp <= pool.lastUpdatedAt) return;
    uint256 lpTotal = IERC20(_lpToken).balanceOf(address(this));
    if (lpTotal == 0) {
      pool.lastUpdatedAt = block.timestamp;
      return;
    }

    for (uint256 i = 0; i < pool.bonuses.length; i ++) {
      Bonus storage bonus = pool.bonuses[i];
      if (pool.lastUpdatedAt < bonus.endTime && bonus.startTime < block.timestamp) {
        uint256 bonusForTime = _calRewardsForTime(bonus, pool.lastUpdatedAt);
        bonus.accRewardsPerToken = bonus.accRewardsPerToken + bonusForTime / lpTotal;
      }
    }
    pool.lastUpdatedAt = block.timestamp;
  }

  function claimRewards(address _lpToken) public override {
    User storage user = users[_lpToken][msg.sender];
    if (user.amount == 0) return;

    updatePool(_lpToken);
    _claimRewards(_lpToken, user);
    Bonus[] memory bonuses = pools[_lpToken].bonuses;
    for (uint256 i = 0; i < bonuses.length; i++) {
      // update writeoff to match current acc rewards per token
      if (user.rewardsWriteoffs.length == i) {
        user.rewardsWriteoffs.push(user.amount * bonuses[i].accRewardsPerToken / CAL_MULTIPLIER);
      } else {
        user.rewardsWriteoffs[i] = user.amount * bonuses[i].accRewardsPerToken / CAL_MULTIPLIER;
      }
    }
  }

  function claimRewardsForPools(address[] calldata _lpTokens) external override {
    for (uint256 i = 0; i < _lpTokens.length; i++) {
      claimRewards(_lpTokens[i]);
    }
  }

  function deposit(address _lpToken, uint256 _amount) external override nonReentrant notPaused {
    require(pools[_lpToken].lastUpdatedAt > 0, "Blacksmith: pool does not exists");
    require(IERC20(_lpToken).balanceOf(msg.sender) >= _amount, "Blacksmith: insufficient balance");

    updatePool(_lpToken);
    User storage user = users[_lpToken][msg.sender];
    _claimRewards(_lpToken, user);
    Bonus[] memory bonuses = pools[_lpToken].bonuses;
    user.amount = user.amount + _amount;
    for (uint256 i = 0; i < bonuses.length; i++) {
      // update writeoff to match current acc rewards per token
      if (user.rewardsWriteoffs.length == i) {
        user.rewardsWriteoffs.push(user.amount * bonuses[i].accRewardsPerToken / CAL_MULTIPLIER);
      } else {
        user.rewardsWriteoffs[i] = user.amount * bonuses[i].accRewardsPerToken / CAL_MULTIPLIER;
      }
    }

    IERC20(_lpToken).safeTransferFrom(msg.sender, address(this), _amount);
    emit Deposit(msg.sender, _lpToken, _amount);
  }

  function withdraw(address _lpToken, uint256 _amount) external override nonReentrant notPaused {
    User storage user = users[_lpToken][msg.sender];
    updatePool(_lpToken);
    _claimRewards(_lpToken, user);
    user.amount = user.amount - _amount;
    Bonus[] memory bonuses = pools[_lpToken].bonuses;
    for (uint256 i = 0; i < bonuses.length; i++) {
      // update writeoff to match current acc rewards per tokenå
      if (user.rewardsWriteoffs.length == i) {
        user.rewardsWriteoffs.push(user.amount * bonuses[i].accRewardsPerToken / CAL_MULTIPLIER);
      } else {
        user.rewardsWriteoffs[i] = user.amount * bonuses[i].accRewardsPerToken / CAL_MULTIPLIER;
      }
    }

    _safeTransfer(_lpToken, _amount);
    emit Withdraw(msg.sender, _lpToken, _amount);
  }

  /// @notice withdraw all without rewards
  function emergencyWithdraw(address _lpToken) external override nonReentrant {
    User storage user = users[_lpToken][msg.sender];
    uint256 amount = user.amount;
    user.amount = 0;
    _safeTransfer(_lpToken, amount);
    emit Withdraw(msg.sender, _lpToken, amount);
  }

  /// @notice called by authorizers only
  function addBonus(
    address _lpToken,
    address _bonusTokenAddr,
    uint256 _startTime,
    uint256 _weeklyRewards,
    uint256 _transferAmount
  ) external override notPaused {
    require(_isAuthorized(msg.sender, allowedTokenAuthorizers[_bonusTokenAddr]), "BonusRewards: not authorized caller");
    require(_startTime >= block.timestamp, "BonusRewards: startTime in the past");

    // make sure the pool is in the right state (exist with no active bonus at the moment) to add new bonus tokens
    Pool memory pool = pools[_lpToken];
    require(pool.lastUpdatedAt != 0, "BonusRewards: pool does not exist");
    for (uint256 i = 0; i < pool.bonuses.length; i ++) {
      if (pool.bonuses[i].bonusTokenAddr == _bonusTokenAddr) {
        // when there is alreay a bonus program with the same bonus token, make sure the program has ended properly
        require(pool.bonuses[i].endTime + WEEK < block.timestamp, "BonusRewards: last bonus period hasn't ended");
        require(pool.bonuses[i].remBonus == 0, "BonusRewards: last bonus not all claimed");
      }
    }

    IERC20 bonusTokenAddr = IERC20(_bonusTokenAddr);
    uint256 balanceBefore = bonusTokenAddr.balanceOf(address(this));
    bonusTokenAddr.safeTransferFrom(msg.sender, address(this), _transferAmount);
    uint256 received = bonusTokenAddr.balanceOf(address(this)) - balanceBefore;
    // endTime is based on how much tokens transfered v.s. planned weekly rewards
    uint256 endTime = received / _weeklyRewards * WEEK + _startTime;

    pools[_lpToken].bonuses.push(Bonus({
      bonusTokenAddr: _bonusTokenAddr,
      startTime: _startTime,
      endTime: endTime,
      weeklyRewards: _weeklyRewards,
      accRewardsPerToken: 0,
      remBonus: received
    }));
  }

  /// @notice extend the current bonus program, the program has to be active (endTime is in the future)
  function extendBonus(
    address _lpToken,
    uint256 _poolBonusId,
    address _bonusTokenAddr,
    uint256 _transferAmount
  ) external override notPaused {
    Bonus memory bonus = pools[_lpToken].bonuses[_poolBonusId];

    require(bonus.bonusTokenAddr == _bonusTokenAddr, "BonusRewards: bonus and id dont match");
    require(_isAuthorized(msg.sender, allowedTokenAuthorizers[_bonusTokenAddr]), "BonusRewards: not authorized caller");
    require(bonus.endTime > block.timestamp, "BonusRewards: bonus program ended, please start a new one");

    IERC20 bonusTokenAddr = IERC20(_bonusTokenAddr);
    uint256 balanceBefore = bonusTokenAddr.balanceOf(address(this));
    bonusTokenAddr.safeTransferFrom(msg.sender, address(this), _transferAmount);
    uint256 received = bonusTokenAddr.balanceOf(address(this)) - balanceBefore;
    // endTime is based on how much tokens transfered v.s. planned weekly rewards
    uint256 endTime = (received / bonus.weeklyRewards) * WEEK + bonus.endTime;

    pools[_lpToken].bonuses[_poolBonusId].endTime = endTime;
    pools[_lpToken].bonuses[_poolBonusId].remBonus = bonus.remBonus + received;
  }

  /// @notice add pools and authorizers to add bonus tokens for pools
  function addPoolsAndAllowBonus(
    address[] calldata _lpTokens,
    address[] calldata _bonusTokenAddrs,
    address[] calldata _authorizers
  ) external override onlyOwner notPaused {
    for (uint256 i = 0; i < _bonusTokenAddrs.length; i++) {
      allowedTokenAuthorizers[_bonusTokenAddrs[i]] = _authorizers;
      bonusTokenAddrMap[_bonusTokenAddrs[i]] = 1;
    }

    for (uint256 i = 0; i < _lpTokens.length; i++) {
      Pool memory pool = pools[_lpTokens[i]];
      require(pool.lastUpdatedAt == 0, "BonusRewards: pool exists");
      pools[_lpTokens[i]].lastUpdatedAt = block.timestamp;
      poolList.push(_lpTokens[i]);
    }
  }

  /// @notice use start and end to avoid gas limit in one call
  function updatePools(uint256 _start, uint256 _end) external override {
    address[] memory poolListCopy = poolList;
    for (uint256 i = _start; i < _end; i++) {
      updatePool(poolListCopy[i]);
    }
  }

  /// @notice collect bonus token dust to treasury
  function collectDust(address _token, address _lpToken, uint256 _poolBonusId) external override onlyOwner {
    require(pools[_token].lastUpdatedAt == 0, "BonusRewards: lpToken, not allowed");

    uint256 balance = IERC20(_token).balanceOf(address(this));
    // bonus token
    if (bonusTokenAddrMap[_token] == 1 && pools[_lpToken].bonuses.length > 0) {
      Bonus memory bonus = pools[_lpToken].bonuses[_poolBonusId];
      require(bonus.bonusTokenAddr == _token, "BonusRewards: wrong pool");
      require(bonus.endTime + WEEK < block.timestamp, "BonusRewards: not ready");
      balance = bonus.remBonus;
      pools[_lpToken].bonuses[_poolBonusId].remBonus = 0;
    }

    if (_token == address(0)) { // token address(0) = ETH
      payable(owner()).transfer(address(this).balance);
    } else {
      IERC20(_token).transfer(owner(), balance);
    }
  }

  function setResponders(address[] calldata _responders) external override onlyOwner {
    responders = _responders;
  }

  function setPaused(bool _paused) external override {
    require(_isAuthorized(msg.sender, responders), "BonusRewards: caller not responder");
    paused = _paused;
  }

  /// @notice tranfer upto what the contract has
  function _safeTransfer(address _token, uint256 _amount) private returns (uint256 _transferred) {
    IERC20 token = IERC20(_token);
    uint256 balance = token.balanceOf(address(this));
    if (balance > _amount) {
      token.safeTransfer(msg.sender, _amount);
      _transferred = _amount;
    } else if (balance > 0) {
      token.safeTransfer(msg.sender, balance);
      _transferred = balance;
    }
  }

  function _calRewardsForTime(Bonus memory _bonus, uint256 _lastUpdatedAt) internal view returns (uint256) {
    if (_bonus.endTime <= _lastUpdatedAt) return 0;

    uint256 calEndTime = block.timestamp > _bonus.endTime ? _bonus.endTime : block.timestamp;
    uint256 calStartTime = _lastUpdatedAt > _bonus.startTime ? _lastUpdatedAt : _bonus.startTime;
    uint256 timePassed = calEndTime - calStartTime;
    return _bonus.weeklyRewards * CAL_MULTIPLIER * timePassed / WEEK;
  }

  function _claimRewards(address _lpToken, User memory _user) private {
    // only claim if user has deposited before
    uint256 rewardsWriteoffsLen = _user.rewardsWriteoffs.length;
    if (_user.amount > 0 && rewardsWriteoffsLen > 0) {
      Bonus[] memory bonuses = pools[_lpToken].bonuses;
      for (uint256 i = 0; i < bonuses.length; i++) {
        uint256 rewardsWriteoff = rewardsWriteoffsLen == i ? 0 : _user.rewardsWriteoffs[i];
        uint256 bonusSinceLastUpdate = _user.amount * bonuses[i].accRewardsPerToken / CAL_MULTIPLIER - rewardsWriteoff;
        if (bonusSinceLastUpdate > 0) {
          uint256 transferred = _safeTransfer(bonuses[i].bonusTokenAddr, bonusSinceLastUpdate); // transfer bonus tokens to user
          pools[_lpToken].bonuses[i].remBonus = bonuses[i].remBonus - transferred;
        }
      }
    }
  }

  // only owner or authorized users can add bonus tokens
  function _isAuthorized(address _addr, address[] memory checkList) private view returns (bool) {
    if (_addr == owner()) return true;

    for (uint256 i = 0; i < checkList.length; i++) {
      if (msg.sender == checkList[i]) {
        return true;
      }
    }
    return false;
  }
}
