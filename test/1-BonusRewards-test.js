const { expect } = require("chai");

const { time } = require("@openzeppelin/test-helpers");
const { expectRevert } = require("@openzeppelin/test-helpers");

describe("BonusRewards", () => {
  const ETHER_UINT_100000000 = ethers.utils.parseEther("1000000000");
  const ETHER_UINT_10000 = ethers.utils.parseEther("10000");
  const ETHER_UINT_20000 = ethers.utils.parseEther("20000");
  const ETHER_UINT_950 = ethers.utils.parseEther("950");
  const ETHER_UINT_800 = ethers.utils.parseEther("800");
  const ETHER_UINT_1 = ethers.utils.parseEther("1");
  const TOTAL_BONUS = ETHER_UINT_10000;
  const WEEKLY_REWARDS = ETHER_UINT_800;

  let ownerAddress, ownerAccount, partnerAccount, partnerAddress, userAAccount, userAAddress, userBAccount, userBAddress;

  let bonusRewards, lpToken, bonusToken, startTime;

  before(async () => {
    const accounts = await ethers.getSigners();
    [ ownerAccount, partnerAccount, userAAccount, userBAccount ] = accounts;
    ownerAddress = await ownerAccount.getAddress();
    partnerAddress = await partnerAccount.getAddress();
    userAAddress = await userAAccount.getAddress();
    userBAddress = await userBAccount.getAddress();

    const ERC20 = await ethers.getContractFactory("ERC20");
    const BonusRewards = await ethers.getContractFactory("BonusRewards");

    // deploy rewawrds contract
    bonusRewards = await BonusRewards.deploy();
    await bonusRewards.deployed();

    // deploy test lp token contract
    lpToken = await ERC20.deploy('BPT', 'BPT');
    await lpToken.deployed();
    lpToken.mint(ownerAddress, ETHER_UINT_100000000);
    lpToken.mint(userAAddress, ETHER_UINT_10000);
    lpToken.mint(userBAddress, ETHER_UINT_20000);
    await lpToken.connect(ownerAccount).approve(bonusRewards.address, ETHER_UINT_100000000);
    await lpToken.connect(userAAccount).approve(bonusRewards.address, ETHER_UINT_10000);
    await lpToken.connect(userBAccount).approve(bonusRewards.address, ETHER_UINT_20000);

    // deploy test bonus token contract
    bonusToken = await ERC20.deploy('COVER', 'COVER');
    await bonusToken.deployed();
    bonusToken.mint(partnerAddress, ETHER_UINT_20000);
    await bonusToken.connect(partnerAccount).approve(bonusRewards.address, ETHER_UINT_20000);
  });

  it("Should deploy correctly", async function() {
    expect(await bonusRewards.owner()).to.equal(ownerAddress);
  });

  it("Should collectDust", async function() {
    const ownerBonusBalBefore = await bonusToken.balanceOf(ownerAddress);
    await bonusToken.mint(bonusRewards.address, ETHER_UINT_1);
    await bonusRewards.collectDust(bonusToken.address, bonusToken.address);
    const ownerBonusBalAfter = await bonusToken.balanceOf(ownerAddress);
    expect(ownerBonusBalAfter.sub(ownerBonusBalBefore)).to.equal(ETHER_UINT_1);
  });

  it("Should NOT addPoolsAndAllowBonus by non-owner", async function() {
    await expectRevert(bonusRewards.connect(partnerAccount).addPoolsAndAllowBonus([lpToken.address], bonusToken.address, [partnerAddress]), "Ownable: caller is not the owner");
  });

  it("Should NOT addPoolsAndAllowBonus by non-owner", async function() {
    await expectRevert(bonusRewards.connect(partnerAccount).addPoolsAndAllowBonus([lpToken.address], bonusToken.address, [partnerAddress]), "Ownable: caller is not the owner");
  });

  it("Should addPoolsAndAllowBonus by owner", async function() {
    await bonusRewards.addPoolsAndAllowBonus([lpToken.address], bonusToken.address, [partnerAddress]);
    const poolList = await bonusRewards.getPoolList();
    expect(poolList).to.deep.equal([lpToken.address]);
    const authorizers = await bonusRewards.getAuthorizers(bonusToken.address);
    expect(authorizers).to.deep.equal([partnerAddress]);
  });

  it("Should NOT collectDust on lpToken", async function() {
    await expectRevert(bonusRewards.collectDust(lpToken.address, lpToken.address), "BonusRewards: lpToken, not allowed");
  });

  it("Should collectDust on bonusToken if not active", async function() {
    await bonusRewards.collectDust(bonusToken.address, lpToken.address);
  });

  it("Should addBonus by partner correctly", async function() {
    const latest = await time.latest();
    startTime = latest.toNumber() + 1;
    const endTime = startTime + 7 * 24 * 60 * 60;

    await bonusRewards.connect(partnerAccount).addBonus(lpToken.address, bonusToken.address, startTime, WEEKLY_REWARDS, WEEKLY_REWARDS);

    const [bonusTokenAddr, start, end, weeklyRewards, accRewardsPerToken] = await bonusRewards.pools(lpToken.address);
    expect(bonusTokenAddr).to.equal(bonusToken.address);
    expect(start.toNumber()).to.equal(startTime);
    expect(end.toNumber()).to.equal(endTime);
    expect(weeklyRewards.toString()).to.equal(weeklyRewards);
    expect(accRewardsPerToken.toNumber()).to.equal(0);

    await expectRevert(bonusRewards.connect(userAAccount).addBonus(lpToken.address, bonusToken.address, startTime, WEEKLY_REWARDS, WEEKLY_REWARDS), "BonusRewards: not authorized caller");
    await expectRevert(bonusRewards.connect(partnerAccount).addBonus(lpToken.address, bonusToken.address, startTime - 1, WEEKLY_REWARDS, WEEKLY_REWARDS), "BonusRewards: startTime in the past");
    await expectRevert(bonusRewards.connect(partnerAccount).addBonus(userAAddress, bonusToken.address, endTime, WEEKLY_REWARDS, WEEKLY_REWARDS), "BonusRewards: pool does not exist");
    await expectRevert(bonusRewards.connect(partnerAccount).addBonus(lpToken.address, bonusToken.address, endTime, WEEKLY_REWARDS, WEEKLY_REWARDS), "BonusRewards: last bonus period hasn't ended");
  });

  it("Should deposit lpToken for userA and userB", async function() {
    // deposit small amount first
    await bonusRewards.connect(userBAccount).deposit(lpToken.address, ETHER_UINT_1);
    expect(await lpToken.balanceOf(userBAddress)).to.equal(ETHER_UINT_20000.sub(ETHER_UINT_1));
    expect(await lpToken.balanceOf(bonusRewards.address)).to.equal(ETHER_UINT_1);

    await time.increase(10);
    await time.advanceBlock();

    await bonusRewards.connect(userAAccount).deposit(lpToken.address, ETHER_UINT_800);
    expect(await lpToken.balanceOf(userAAddress)).to.equal(ETHER_UINT_10000.sub(ETHER_UINT_800));
    expect(await lpToken.balanceOf(bonusRewards.address)).to.equal(ETHER_UINT_800.add(ETHER_UINT_1));
  });

  it("Should extendBonus by partner correctly", async function() {
    const week = 7 * 24 * 60 * 60;
    const [,, endBefore,] = await bonusRewards.pools(lpToken.address);

    await bonusRewards.connect(partnerAccount).extendBonus(lpToken.address, WEEKLY_REWARDS);

    const [,, end,] = await bonusRewards.pools(lpToken.address);
    expect(end.sub(endBefore).toNumber()).to.equal(week);
  });

  it("Should view minedRewards, claimRewards for userA, deposit and claim for userB", async function() {
    const lpTokenAddress = lpToken.address;
    const timePassed = 4 * 24 * 60 * 60;
    await time.increase(timePassed);
    await time.advanceBlock();

    const rewardsEstimate = WEEKLY_REWARDS.mul(3).div(7);
    const rewardsMax = WEEKLY_REWARDS.mul(5).div(7);

    // test view minedRewards function
    const userARewards = await bonusRewards.viewRewards(lpTokenAddress, userAAddress);
    // console.log('userARewards: ', userARewards.toString());
    // console.log('rewardsEstimate: ', rewardsEstimate.toString());
    expect(userARewards.gt(rewardsEstimate)).to.be.true;
    expect(userARewards.lt(WEEKLY_REWARDS)).to.be.true;

    // test claimRewards function for user A
    await bonusRewards.connect(userAAccount).deposit(lpToken.address, 0);
    const claimedRewardsA = await bonusToken.balanceOf(userAAddress);
    // console.log('claimedRewardsA: ', claimedRewardsA.toString());
    // console.log('rewardsEstimate: ', rewardsEstimate.toString());
    expect(claimedRewardsA.gt(rewardsEstimate)).to.be.true;
    expect(claimedRewardsA.lt(rewardsMax)).to.be.true;

    // test deposit second time for userB, 1st was 1 lpToken, now 800
    const bonusRewardsInitBal = await lpToken.balanceOf(bonusRewards.address);
    const userBInitBal = await lpToken.balanceOf(userBAddress);
    await bonusRewards.connect(userBAccount).deposit(lpTokenAddress, ETHER_UINT_800);
    expect(await lpToken.balanceOf(userBAddress)).to.equal(userBInitBal.sub(ETHER_UINT_800));
    expect(await lpToken.balanceOf(bonusRewards.address)).to.equal(bonusRewardsInitBal.add(ETHER_UINT_800));
    // the deposit should also auto claim rewards
    const claimedRewardsB = await bonusToken.balanceOf(userBAddress);
    // it should be > 1 userB share / 800 userA share
    expect(claimedRewardsB.gt(rewardsEstimate.div(800))).to.be.true;
    // it should be significantly less than userA
    expect(claimedRewardsB.lt(rewardsEstimate.mul(3).div(800))).to.be.true;

    // total claim rewards should be less than total
    expect(claimedRewardsB.add(claimedRewardsA).lt(rewardsMax)).to.be.true;
  });

  it("Should withdraw for userB", async function() {
    const lpTokenAddress = lpToken.address;
    const timePassed = 3 * 24 * 60 * 60;
    await time.increase(timePassed);
    await time.advanceBlock();

    const rewardsEstimate = WEEKLY_REWARDS.mul(3).div(7).div(2);
    const rewardsMax = WEEKLY_REWARDS.mul(4).div(7).div(2);
    
    const userBLptokenBefore = await lpToken.balanceOf(userBAddress);
    const userBRewardsBefore = await bonusToken.balanceOf(userBAddress);
    await bonusRewards.connect(userBAccount).withdraw(lpTokenAddress, ETHER_UINT_800);
    // userB lptoken balance should increase by withdraw amount
    expect(await lpToken.balanceOf(userBAddress)).to.equal(userBLptokenBefore.add(ETHER_UINT_800));
    const userBRewardsAfter = await bonusToken.balanceOf(userBAddress);

    // check Rewards
    const userBClaimedRewards = userBRewardsAfter.sub(userBRewardsBefore);
    expect(userBClaimedRewards.gt(rewardsEstimate)).to.be.true;
    expect(userBClaimedRewards.lt(rewardsMax)).to.be.true;
  });

  it("Should emergency withdraw for userA", async function() {
    const lpTokenAddress = lpToken.address;
    const user = await bonusRewards.users(lpTokenAddress, userAAddress);

    const userABalBefore = await lpToken.balanceOf(userAAddress);
    await bonusRewards.connect(userAAccount).emergencyWithdraw(lpTokenAddress);
    const userABalAfter = await lpToken.balanceOf(userAAddress);

    expect(userABalAfter.sub(userABalBefore)).to.equal(user.amount);
  });

  it("Should NOT collectDust on bonusToken if active", async function() {
    await expectRevert(bonusRewards.collectDust(bonusToken.address, lpToken.address), "BonusRewards: not ready");
  });

  it("Should NOT addBonus if not all bonusToken claimed", async function() {
    const timePassed = 2 * 7 * 24 * 60 * 60;
    await time.increase(timePassed);
    await time.advanceBlock();

    const latest = await time.latest();
    const startTime = latest.toNumber() + 2;
    await expectRevert(bonusRewards.connect(partnerAccount).addBonus(lpToken.address, bonusToken.address, startTime, WEEKLY_REWARDS, WEEKLY_REWARDS), "BonusRewards: last bonus not all claimed");
  });

  it("Should addBonus if all bonusToken claimed", async function() {
    await bonusRewards.connect(userAAccount).deposit(lpToken.address, 0);
    await bonusRewards.connect(userBAccount).deposit(lpToken.address, 0);
    await bonusRewards.deposit(lpToken.address, 0);
    await bonusRewards.collectDust(bonusToken.address, lpToken.address);

    const latest = await time.latest();
    const startTime = latest.toNumber() + 2;
    await bonusRewards.connect(partnerAccount).addBonus(lpToken.address, bonusToken.address, startTime, WEEKLY_REWARDS, WEEKLY_REWARDS);
  });
});