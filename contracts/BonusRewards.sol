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
  address[] private poolList;
  // lpToken => BonusToken
  mapping(address => Pool) public override pools;
  // lpToken => User address => User data
  mapping(address => mapping(address => User)) public override users;
  // bonus token => [] allowed authorizers to add bonus tokens
  mapping(address => address[]) private allowedTokenAuthorizers;
  // bonusToken => 1, used to avoid collecting bonus token when not ready
  mapping(address => uint8) private bonusTokenMap;

  function getPoolList() external view override returns (address[] memory) {
    return poolList;
  }

  function getAuthorizers(address _bonusToken) external view override returns (address[] memory) {
    return allowedTokenAuthorizers[_bonusToken];
  }

  function viewRewards(address _lpToken, address _user) external view override returns (uint256 _rewards) {
    Pool memory pool = pools[_lpToken];
    User memory user = users[_lpToken][_user];
    uint256 lpTotal = IERC20(_lpToken).balanceOf(address(this));
    if (user.amount > 0 && lpTotal > 0
          && pool.startTime < block.timestamp && pool.weeklyRewards > 0) {
      uint256 bonus = _calRewardsForTime(pool);
      uint256 bonusPerToken = pool.accRewardsPerToken + bonus / lpTotal;
      _rewards = user.amount * bonusPerToken / CAL_MULTIPLIER - user.rewardsWriteoff;
    }
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
    if (pool.lastUpdatedAt < pool.endTime && pool.startTime < block.timestamp) {
      uint256 bonus = _calRewardsForTime(pool);
      pool.accRewardsPerToken = pool.accRewardsPerToken + bonus / lpTotal;
      pool.lastUpdatedAt = block.timestamp <= pool.endTime ? block.timestamp : pool.endTime;
    }
  }

  function deposit(address _lpToken, uint256 _amount) external override nonReentrant {
    require(pools[_lpToken].lastUpdatedAt > 0, "Blacksmith: pool does not exists");
    require(IERC20(_lpToken).balanceOf(msg.sender) >= _amount, "Blacksmith: insufficient balance");

    updatePool(_lpToken);
    Pool memory pool = pools[_lpToken];
    User storage user = users[_lpToken][msg.sender];
    _claimRewards(pool, user);
    user.amount = user.amount + _amount;
    // update writeoff to match current acc rewards per token
    user.rewardsWriteoff = user.amount * pool.accRewardsPerToken / CAL_MULTIPLIER;

    IERC20(_lpToken).safeTransferFrom(msg.sender, address(this), _amount);
    emit Deposit(msg.sender, _lpToken, _amount);
  }

  function withdraw(address _lpToken, uint256 _amount) external override nonReentrant {
    User storage user = users[_lpToken][msg.sender];
    updatePool(_lpToken);
    Pool memory pool = pools[_lpToken];
    _claimRewards(pool, user);
    user.amount = user.amount - _amount;
    // update writeoff to match current acc rewards/bonus per token
    user.rewardsWriteoff = user.amount * pool.accRewardsPerToken / CAL_MULTIPLIER;

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
    address _bonusToken,
    uint256 _startTime,
    uint256 _weeklyRewards,
    uint256 _transferAmount
  ) external override {
    require(_isAuthorized(_bonusToken), "BonusRewards: not authorized caller");
    require(_startTime >= block.timestamp, "BonusRewards: startTime in the past");

    // make sure the pool is in the right state (exist with no active bonus at the moment) to add new bonus tokens
    Pool memory pool = pools[_lpToken];
    require(pool.lastUpdatedAt != 0, "BonusRewards: pool does not exist");
    if (pool.endTime > 0) {
      // when there is alreay a bonus program, make sure the program has ended properly
      require(pool.endTime + WEEK < block.timestamp, "BonusRewards: last bonus period hasn't ended");
      require(IERC20(pool.bonusToken).balanceOf(address(this)) == 0, "BonusRewards: last bonus not all claimed");
    }

    IERC20 bonusToken = IERC20(_bonusToken);
    uint256 balanceBefore = bonusToken.balanceOf(address(this));
    bonusToken.safeTransferFrom(msg.sender, address(this), _transferAmount);
    uint256 received = bonusToken.balanceOf(address(this)) - balanceBefore;
    // endTime is based on how much tokens transfered v.s. planned weekly rewards
    uint256 endTime = received / _weeklyRewards * WEEK + _startTime;

    pools[_lpToken] = Pool({
      bonusToken: _bonusToken,
      startTime: _startTime,
      endTime: endTime,
      weeklyRewards: _weeklyRewards,
      accRewardsPerToken: 0,
      lastUpdatedAt: _startTime
    });
  }

  /// @notice extend the current bonus program, the program has to be active (endTime is in the future)
  function extendBonus(address _lpToken, uint256 _transferAmount) external override {
    Pool memory pool = pools[_lpToken];

    require(_isAuthorized(pool.bonusToken), "BonusRewards: not authorized caller");
    require(pool.endTime > block.timestamp, "BonusRewards: bonus program ended, please start a new one");

    IERC20 bonusToken = IERC20(pool.bonusToken);
    uint256 balanceBefore = bonusToken.balanceOf(address(this));
    bonusToken.safeTransferFrom(msg.sender, address(this), _transferAmount);
    uint256 received = bonusToken.balanceOf(address(this)) - balanceBefore;
    // endTime is based on how much tokens transfered v.s. planned weekly rewards
    uint256 endTime = (received / pool.weeklyRewards) * WEEK + pool.endTime;

    pools[_lpToken].endTime = endTime;
  }

  /// @notice only statusCode 1 will enable the bonusToken to allow partners to set their program
  function addPoolsAndAllowBonus(address[] calldata _lpTokens, address _bonusToken, address[] calldata _authorizers) external override onlyOwner {
    allowedTokenAuthorizers[_bonusToken] = _authorizers;
    bonusTokenMap[_bonusToken] = 1;

    for (uint256 i = 0; i < _lpTokens.length; i++) {
      Pool memory pool = pools[_lpTokens[i]];
      require(pool.lastUpdatedAt == 0, "BonusRewards: pool exists");
      pools[_lpTokens[i]] = Pool({
        bonusToken: _bonusToken,
        startTime: 0,
        endTime: 0,
        weeklyRewards: 0,
        accRewardsPerToken: 0,
        lastUpdatedAt: block.timestamp
      });
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
  function collectDust(address _token, address _lpToken) external override {
    require(pools[_token].lastUpdatedAt == 0, "BonusRewards: lpToken, not allowed");

    // bonus token
    if (bonusTokenMap[_token] == 1) {
      Pool memory pool = pools[_lpToken];
      require(pool.bonusToken == _token, "BonusRewards: wrong pool");
      require(pool.endTime + WEEK < block.timestamp, "BonusRewards: not ready");
    }

    if (_token == address(0)) { // token address(0) = ETH
      payable(owner()).transfer(address(this).balance);
    } else {
      uint256 balance = IERC20(_token).balanceOf(address(this));
      IERC20(_token).transfer(owner(), balance);
    }
  }

  /// @notice tranfer upto what the contract has
  function _safeTransfer(address _token, uint256 _amount) private {
    IERC20 token = IERC20(_token);
    uint256 balance = token.balanceOf(address(this));
    if (balance > _amount) {
      token.safeTransfer(msg.sender, _amount);
    } else if (balance > 0) {
      token.safeTransfer(msg.sender, balance);
    }
  }

  function _calRewardsForTime(Pool memory _pool) internal view returns (uint256) {
    uint256 timePassed = block.timestamp - _pool.lastUpdatedAt;
    return _pool.weeklyRewards * CAL_MULTIPLIER * timePassed / WEEK;
  }

  function _claimRewards(Pool memory pool, User memory user) private {
    if (user.amount > 0) {
      uint256 bonusSinceLastUpdate = user.amount * pool.accRewardsPerToken / CAL_MULTIPLIER - user.rewardsWriteoff;
      if (bonusSinceLastUpdate > 0) {
        _safeTransfer(pool.bonusToken, bonusSinceLastUpdate); // transfer bonus tokens to user
      }
    }
  }

  // only owner or authorized users can add bonus tokens
  function _isAuthorized(address _token) private view returns (bool) {
    if (msg.sender == owner()) return true;

    address[] memory authorizers = allowedTokenAuthorizers[_token];
    bool authorized = false;
    for (uint256 i = 0; i < authorizers.length; i++) {
      if (msg.sender == authorizers[i]) {
        authorized = true;
        break;
      }
    }
    return authorized;
  }
}
