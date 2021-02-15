require('dotenv').config();

module.exports = {
  42: {
    env: 'Kovan',
    dev: process.env.KOVAN_MULTI_DEV,
    deployedBonusRewards: process.env.KOVAN_BONUS_REWARDS,
  },
  250: {
    env: 'Fantom',
    dev: process.env.MAINNET_DEV,
    deployedBonusRewards: process.env.MAINNET_BONUS_REWARDS,
  },
  1: {
    env: 'Mainnet',
    dev: process.env.MAINNET_MULTI_DEV,
    deployedBonusRewards: process.env.MAINNET_BONUS_REWARDS,
  },
}