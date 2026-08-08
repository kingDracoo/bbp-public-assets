// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/* solhint-disable func-name-mixedcase */
/* solhint-disable private-vars-leading-underscore */

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import {SigUtils} from "../../utils/SigUtils.sol";

import "../../../contracts/USDe.sol";
import "../../../contracts/StakedUSDeV2.sol";
import "../../../contracts/interfaces/IUSDe.sol";
import "../../../contracts/interfaces/IERC20Events.sol";
import "./StakedUSDe.t.sol";

/// @dev Run all StakedUSDeV1 tests against StakedUSDeV2 with cooldown duration enabled.
contract StakedUSDeV2CooldownTest is StakedUSDeTest {
  StakedUSDeV2 stakedUSDeV2;

  function setUp() public virtual override {
    usdeToken = new USDe(address(this));

    alice = vm.addr(0xB44DE);
    bob = vm.addr(0x1DE);
    greg = vm.addr(0x6ED);
    owner = vm.addr(0xA11CE);
    rewarder = vm.addr(0x1DEA);

    vm.label(alice, "alice");
    vm.label(bob, "bob");
    vm.label(greg, "greg");
    vm.label(owner, "owner");
    vm.label(rewarder, "rewarder");

    vm.startPrank(owner);

    stakedUSDe = new StakedUSDeV2(
      IUSDe(address(usdeToken)),
      rewarder,
      owner
    );

    stakedUSDeV2 = StakedUSDeV2(address(stakedUSDe));
    rateProvider = new EthenaBalancerRateProvider(address(stakedUSDe));

    vm.stopPrank();

    sigUtilsUSDe = new SigUtils(usdeToken.DOMAIN_SEPARATOR());
    sigUtilsStakedUSDe = new SigUtils(stakedUSDe.DOMAIN_SEPARATOR());

    usdeToken.setMinter(address(this));
  }

  function testFuzzFairStakeAndUnstakePrices(
    uint256 amount1,
    uint256 amount2,
    uint256 amount3,
    uint256 rewardAmount,
    uint256 waitSeconds
  ) public {
    amount1 = bound(amount1, 100 ether, 1e32 - 1);
    amount2 = bound(amount2, 1, 1e32 - 1);
    amount3 = bound(amount3, 1, 1e32 - 1);
    rewardAmount = bound(rewardAmount, 1, 1e32 - 1);
    waitSeconds = bound(waitSeconds, 0, 9 hours);

    uint256 totalContributions = amount1;

    _mintApproveDeposit(alice, amount1);

    _transferRewards(rewardAmount, rewardAmount);

    vm.warp(block.timestamp + waitSeconds);

    uint256 vestedAmount;

    if (waitSeconds > 8 hours) {
      vestedAmount = amount1 + rewardAmount;
    } else {
      vestedAmount =
        amount1 +
        rewardAmount -
        (rewardAmount * (8 hours - waitSeconds)) /
        8 hours;
    }

    _assertVestedAmountIs(vestedAmount);

    uint256 bobStakedUSDe =
      (amount2 * (amount1 + 1)) /
      (vestedAmount + 1);

    if (bobStakedUSDe > 0) {
      _mintApproveDeposit(bob, amount2);
      totalContributions += amount2;
    }

    vm.warp(block.timestamp + waitSeconds);

    if (waitSeconds > 4 hours) {
      vestedAmount = totalContributions + rewardAmount;
    } else {
      vestedAmount =
        totalContributions +
        rewardAmount -
        ((4 hours - waitSeconds) * rewardAmount) /
        4 hours;
    }

    _assertVestedAmountIs(vestedAmount);

    uint256 gregStakedUSDe =
      (amount3 * (stakedUSDe.totalSupply() + 1)) /
      (vestedAmount + 1);

    if (gregStakedUSDe > 0) {
      _mintApproveDeposit(greg, amount3);
      totalContributions += amount3;
    }

    vm.warp(block.timestamp + 8 hours);

    vestedAmount = totalContributions + rewardAmount;

    _assertVestedAmountIs(vestedAmount);

    uint256 usdePerStakedUSDeBefore =
      stakedUSDe.convertToAssets(1 ether);

    uint256 bobUnstakeAmount =
      (stakedUSDe.balanceOf(bob) * (vestedAmount + 1)) /
      (stakedUSDe.totalSupply() + 1);

    uint256 gregUnstakeAmount =
      (stakedUSDe.balanceOf(greg) * (vestedAmount + 1)) /
      (stakedUSDe.totalSupply() + 1);

    if (bobUnstakeAmount > 0) {
      _redeem(bob, stakedUSDe.balanceOf(bob));
    }

    uint256 usdePerStakedUSDeAfter =
      stakedUSDe.convertToAssets(1 ether);

    if (usdePerStakedUSDeAfter != 0) {
      assertApproxEq
