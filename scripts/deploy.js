const configs = require('./configs');

async function main() {
  const [ deployer ] = await ethers.getSigners();
  console.log(`Deployer address: ${deployer.address}`);
  const deployerBalance = await deployer.getBalance();
  console.log(`Deployer balance: ${deployerBalance}`);

  const provider = deployer.provider;
  const network = await provider.getNetwork();
  const envVars = configs[network.chainId];
  console.log(`Network id ${network.chainId} is ${envVars.env}.`);

  const networkGasPrice = (await provider.getGasPrice()).toNumber();
  const gasPrice = networkGasPrice * 1.05;
  console.log(`Gas Price balance: ${gasPrice}`);
  
  // get the contract to deploy
  const BonusRewards = await ethers.getContractFactory('BonusRewards');
  
  // deploy BonusRewards
  const bonusRewards = await BonusRewards.deploy({ gasPrice });
  await bonusRewards.deployed();
  await bonusRewards.transferOwnership(envVars.dev, { gasPrice });
  console.log(`BonusRewards deployed to: ${bonusRewards.address}`);

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
