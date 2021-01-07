/**
 * Deploy:
 *    WETHDistributor
 *    COVER
 *    CoverDistributor
 *    
 * Calls after: 
 *    COVER.setDistributor
 */

const configs = require('./configs');

async function main() {
  const [ deployer ] = await ethers.getSigners();
  console.log(`Deployer address: ${deployer.address}`);
  const deployerBalance = await deployer.getBalance();
  console.log(`Deployer balance: ${deployerBalance}`);

  const provider = deployer.provider;
  const network = await provider.getNetwork();
  console.log(`Network: ${network.name} is kovan ${network.name === 'kovan'}`);
  const envVars = network.name === 'kovan' ? configs.kovan : configs.mainnet;

  const BonusRewards = await ethers.getContractFactory('BonusRewards');
  const bonusRewards = BonusRewards.attach(envVars.deployedBonusRewards);

  const bonusRewardsOwner = await bonusRewards.owner();
  console.log(`bonusRewards owner is ${bonusRewardsOwner}, it is ${bonusRewardsOwner == envVars.dev ? '' : 'NOT'} dev multi-sig`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
