# cover-rewards

Contracts for Cover Protocol bonus tokens rewards

## Audits
* [Official Audit 1](https://github.com/maxsam4/cover-protocol-rewards-audit-january-2021)

## Development
* run `npm install` to install all node dependencies
* run `npx hardhat compile` to compile

### Run Test With hardhat EVM (as [an independent node](https://hardhat.dev/hardhat-evm/#connecting-to-hardhat-evm-from-wallets-and-other-software))
* Run `npx hardhat node` to setup a local blockchain emulator in one terminal.
* `npx hardhat test --network localhost` run tests in a new terminal.
 **`npx hardhat node` restart required after full test run.** As the blockchain timestamp has changed.

## Deploy to Kovan Testnet
* Comment out requirement in Constructor of the Migrator
* Run `npx hardhat run scripts/deploy.js --network kovan`.
* Run `npx hardhat flatten contracts/BonusRewards.sol > flat.sol` will flatten all contracts into one
* BonusRewards
`npx hardhat verify --network kovan 0xb5BBf98F7e3A83bAa0D088599AE634660309b0CC`
