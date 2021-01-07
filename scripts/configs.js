require('dotenv').config();

module.exports = {
  kovan: {
    dev: process.env.KOVAN_MULTI_DEV,
    deployedBonusRewards: process.env.KOVAN_BONUS_REWARDS,
  },  
  mainnet: {
    dev: process.env.MAINNET_MULTI_DEV,
    deployedBonusRewards: process.env.MAINNET_BONUS_REWARDS,
  },
}