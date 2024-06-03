// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { TestFixture } from "./TestFixture.t.sol";
import { CarbonVortex } from "../../contracts/vortex/CarbonVortex.sol";

import { AccessDenied, InvalidAddress, InvalidFee } from "../../contracts/utility/Utils.sol";
import { PPM_RESOLUTION } from "../../contracts/utility/Constants.sol";

import { IVoucher } from "../../contracts/voucher/interfaces/IVoucher.sol";
import { ICarbonController } from "../../contracts/carbon/interfaces/ICarbonController.sol";
import { ICarbonVortex } from "../../contracts/vortex/interfaces/ICarbonVortex.sol";

import { Token, toIERC20, NATIVE_TOKEN } from "../../contracts/token/Token.sol";

contract CarbonVortexTest is TestFixture {
    using Address for address payable;

    /**
     * @dev triggered when fees are withdrawn
     */
    event FeesWithdrawn(Token indexed token, address indexed recipient, uint256 indexed amount, address sender);

    /**
     * @dev triggered when the tank address is updated
     */
    event TankSet(address prevTank, address newTank);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @dev function to set up state before tests
    function setUp() public virtual {
        // Set up tokens and users
        systemFixture();
        // Deploy Carbon Controller and Voucher
        setupCarbonController();
        // Deploy Carbon Vortex
        deployCarbonVortex(address(carbonController));
        // Transfer tokens to Carbon Controller
        transferTokensToCarbonController();
    }

    /**
     * @dev construction tests
     */

    function testShouldRevertWhenDeployingWithInvalidCarbonControllerContract() public {
        vm.expectRevert(InvalidAddress.selector);
        new CarbonVortex(ICarbonController(address(0)));
    }

    function testShouldBeInitialized() public {
        uint16 version = carbonVortex.version();
        assertEq(version, 2);
    }

    function testShouldntBeAbleToReinitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        carbonVortex.initialize();
    }

    /**
     * @dev rewards distribution tests
     */

    /// @dev test should distribute rewards to tank with token input being BNT
    function testShouldDistributeRewardsToTank() public {
        vm.startPrank(admin);
        uint256 amount = 50 ether;
        carbonController.testSetAccumulatedFees(bnt, amount);

        uint256 balanceBefore = bnt.balanceOf(tank);

        Token[] memory tokens = new Token[](1);
        tokens[0] = bnt;
        uint256[] memory expectedUserRewards = new uint256[](1);

        expectedUserRewards[0] = amount;

        carbonVortex.execute(tokens);

        uint256 balanceAfter = bnt.balanceOf(tank);

        uint256 bntGain = balanceAfter - balanceBefore;

        assertEq(bntGain, expectedUserRewards[0]);

        vm.stopPrank();
    }

    /// @dev test should distribute rewards to tank if fees have accumulated
    function testShouldDistributeRewardsToTankIfFeesHaveAccumulated() public {
        vm.startPrank(admin);
        uint256[] memory tokenAmounts = new uint256[](3);
        tokenAmounts[0] = 50 ether;
        tokenAmounts[1] = 30 ether;
        tokenAmounts[2] = 10 ether;

        carbonController.testSetAccumulatedFees(token1, tokenAmounts[0]);
        carbonController.testSetAccumulatedFees(token2, tokenAmounts[1]);
        carbonController.testSetAccumulatedFees(NATIVE_TOKEN, tokenAmounts[2]);

        uint256[] memory balancesBefore = new uint256[](3);
        balancesBefore[0] = token1.balanceOf(tank);
        balancesBefore[1] = token2.balanceOf(tank);
        balancesBefore[2] = tank.balance;

        uint256[] memory expectedUserRewards = new uint256[](3);

        for (uint256 i = 0; i < 3; ++i) {
            expectedUserRewards[i] = tokenAmounts[i];
        }

        Token[] memory tokens = new Token[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = NATIVE_TOKEN;

        carbonVortex.execute(tokens);

        uint256[] memory balancesAfter = new uint256[](3);
        balancesAfter[0] = token1.balanceOf(tank);
        balancesAfter[1] = token2.balanceOf(tank);
        balancesAfter[2] = tank.balance;

        uint256[] memory balanceGains = new uint256[](3);
        balanceGains[0] = balancesAfter[0] - balancesBefore[0];
        balanceGains[1] = balancesAfter[1] - balancesBefore[1];
        balanceGains[2] = balancesAfter[2] - balancesBefore[2];

        assertEq(balanceGains[0], expectedUserRewards[0]);
        assertEq(balanceGains[1], expectedUserRewards[1]);
        assertEq(balanceGains[2], expectedUserRewards[2]);

        vm.stopPrank();
    }

    /// @dev test should distribute rewards to tank and burn bnt if carbonVortex has token balance
    function testShouldDistributeRewardsToTankIfContractHasTokenBalance() public {
        vm.startPrank(admin);
        uint256[] memory tokenAmounts = new uint256[](3);
        tokenAmounts[0] = 50 ether;
        tokenAmounts[1] = 30 ether;
        tokenAmounts[2] = 10 ether;

        token1.safeTransfer(address(carbonVortex), tokenAmounts[0]);
        token2.safeTransfer(address(carbonVortex), tokenAmounts[1]);
        payable(address(carbonVortex)).sendValue(tokenAmounts[2]);

        uint256[] memory balancesBefore = new uint256[](3);
        balancesBefore[0] = token1.balanceOf(tank);
        balancesBefore[1] = token2.balanceOf(tank);
        balancesBefore[2] = tank.balance;

        uint256[] memory expectedUserRewards = new uint256[](3);

        for (uint256 i = 0; i < 3; ++i) {
            expectedUserRewards[i] = tokenAmounts[i];
        }

        Token[] memory tokens = new Token[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = NATIVE_TOKEN;

        carbonVortex.execute(tokens);

        uint256[] memory balancesAfter = new uint256[](3);
        balancesAfter[0] = token1.balanceOf(tank);
        balancesAfter[1] = token2.balanceOf(tank);
        balancesAfter[2] = tank.balance;

        uint256[] memory balanceGains = new uint256[](3);
        balanceGains[0] = balancesAfter[0] - balancesBefore[0];
        balanceGains[1] = balancesAfter[1] - balancesBefore[1];
        balanceGains[2] = balancesAfter[2] - balancesBefore[2];

        assertEq(balanceGains[0], expectedUserRewards[0]);
        assertEq(balanceGains[1], expectedUserRewards[1]);
        assertEq(balanceGains[2], expectedUserRewards[2]);

        vm.stopPrank();
    }

    /// @dev test should distribute rewards to tank if fees have accumulated and carbon vortex has token balance
    function testShouldDistributeRewardsToTankForTokenBalanceAndAccumulatedFees() public {
        vm.startPrank(admin);
        uint256[] memory tokenAmounts = new uint256[](3);
        tokenAmounts[0] = 100 ether;
        tokenAmounts[1] = 60 ether;
        tokenAmounts[2] = 20 ether;

        carbonController.testSetAccumulatedFees(token1, tokenAmounts[0] / 2);
        carbonController.testSetAccumulatedFees(token2, tokenAmounts[1] / 2);
        carbonController.testSetAccumulatedFees(NATIVE_TOKEN, tokenAmounts[2] / 2);

        token1.safeTransfer(address(carbonVortex), tokenAmounts[0] / 2);
        token2.safeTransfer(address(carbonVortex), tokenAmounts[1] / 2);
        payable(address(carbonVortex)).sendValue(tokenAmounts[2] / 2);

        uint256[] memory balancesBefore = new uint256[](3);
        balancesBefore[0] = token1.balanceOf(tank);
        balancesBefore[1] = token2.balanceOf(tank);
        balancesBefore[2] = tank.balance;

        uint256[] memory expectedUserRewards = new uint256[](3);

        for (uint256 i = 0; i < 3; ++i) {
            expectedUserRewards[i] = tokenAmounts[i];
        }

        Token[] memory tokens = new Token[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = NATIVE_TOKEN;

        carbonVortex.execute(tokens);

        uint256[] memory balancesAfter = new uint256[](3);
        balancesAfter[0] = token1.balanceOf(tank);
        balancesAfter[1] = token2.balanceOf(tank);
        balancesAfter[2] = tank.balance;

        uint256[] memory balanceGains = new uint256[](3);
        balanceGains[0] = balancesAfter[0] - balancesBefore[0];
        balanceGains[1] = balancesAfter[1] - balancesBefore[1];
        balanceGains[2] = balancesAfter[2] - balancesBefore[2];


        assertEq(balanceGains[0], expectedUserRewards[0]);
        assertEq(balanceGains[1], expectedUserRewards[1]);
        assertEq(balanceGains[2], expectedUserRewards[2]);

        vm.stopPrank();
    }

    /**
     * @dev execute function tests
     */

    /// @dev test should withdraw fees from CarbonController on calling execute
    function testShouldWithdrawFeesOnExecute() public {
        vm.startPrank(user1);
        uint256[] memory tokenAmounts = new uint256[](3);
        tokenAmounts[0] = 100 ether;
        tokenAmounts[1] = 60 ether;
        tokenAmounts[2] = 20 ether;
        Token[] memory tokens = new Token[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = NATIVE_TOKEN;

        for (uint256 i = 0; i < 3; ++i) {
            carbonController.testSetAccumulatedFees(tokens[i], tokenAmounts[i]);

            vm.expectEmit();
            emit FeesWithdrawn(tokens[i], address(carbonVortex), tokenAmounts[i], address(carbonVortex));
            carbonVortex.execute(tokens);
        }
        vm.stopPrank();
    }

    /// @dev test should skip tokens which don't have accumulated fees on calling execute
    function testShouldSkipTokensWhichDontHaveAccumulatedFees() public {
        vm.startPrank(admin);
        uint256[] memory tokenAmounts = new uint256[](3);
        tokenAmounts[0] = 50 ether;
        tokenAmounts[1] = 30 ether;
        tokenAmounts[2] = 0;

        carbonController.testSetAccumulatedFees(token1, tokenAmounts[0]);
        carbonController.testSetAccumulatedFees(bnt, tokenAmounts[1]);
        carbonController.testSetAccumulatedFees(token2, tokenAmounts[2]);

        uint256[] memory rewardAmounts = new uint256[](3);

        for (uint256 i = 0; i < 3; ++i) {
            rewardAmounts[i] = tokenAmounts[i];
        }

        Token[] memory tokens = new Token[](3);
        tokens[0] = token1;
        tokens[1] = bnt;
        tokens[2] = token2;

        carbonVortex.execute(tokens);

        vm.stopPrank();
    }

    /// @dev test should revert if any of the tokens sent has duplicates
    function testShouldRevertIfAnyOfTheTokensSentHasDuplicates() public {
        vm.prank(user1);
        Token[] memory tokens = new Token[](3);
        tokens[0] = bnt;
        tokens[1] = nonTradeableToken;
        tokens[2] = bnt;
        vm.expectRevert(ICarbonVortex.DuplicateToken.selector);
        carbonVortex.execute(tokens);
    }

    /// @dev test should revert if no tokens are sent
    function testShouldRevertIfNoTokensAreSent() public {
        vm.prank(user1);
        Token[] memory tokens = new Token[](0);
        vm.expectRevert(ICarbonVortex.InvalidTokenLength.selector);
        carbonVortex.execute(tokens);
    }

    /**
     * @dev setTank function tests
     */

    /// @dev test should set tank if new tank is not the same as prev tank
    function testShouldSetTankIfNewTankIsNotTheSame() public {
        vm.startPrank(admin);

        address proposedNewTank = address(0x01);
        address prevTank = carbonVortex.tank();

        vm.expectEmit();
        emit TankSet({ prevTank: prevTank, newTank: proposedNewTank });
        carbonVortex.setTank(proposedNewTank);

        address newTank = carbonVortex.tank();
        assertEq(newTank, proposedNewTank);

        vm.stopPrank();
    }

    /// @dev test should revert if non owner sets tank
    function testShouldRevertIfNonOwnerSetsTank() public {
        address proposedNewTank = address(0x01);
        vm.expectRevert("Ownable: caller is not the owner");
        carbonVortex.setTank(proposedNewTank);
    }

    /// @dev test should revert if invalid address is set for tank
    function testShouldRevertIfInvalidAddressIsSetForTank() public {
        vm.startPrank(admin);

        vm.expectRevert(InvalidAddress.selector);
        carbonVortex.setTank(address(0));

        vm.stopPrank();
    }

    /// @dev test should not change tank address if same address is input
    function testShouldNotChangeTankAddressIfSameAddressIsInput() public {
        vm.startPrank(admin);

        address prevTank = carbonVortex.tank();
        carbonVortex.setTank(tank);
        address newTank = carbonVortex.tank();

        assertEq(newTank, prevTank);

        vm.stopPrank();
    }

    /**
     * @dev tansferOwnership function tests
     */

    /// @dev test should set tank if new tank is not the same as prev tank
    function testShouldTransferOwnershipIfCallerIsTheOwner() public {
        vm.startPrank(admin);

        address prevOwner = carbonVortex.owner();
        assertEq(prevOwner, admin);

        vm.expectEmit();
        emit OwnershipTransferred(prevOwner, admin2);
        carbonVortex.transferOwnership(admin2);

        address newOwner = carbonVortex.tank();
        assertEq(newOwner, admin2);

        vm.stopPrank();
    }

    /// @dev test should revert if non owner tries to transfer ownership
    function testShouldRevertIfNonOwnerTriesToTransferOwnership() public {
        vm.expectRevert("Ownable: caller is not the owner");
        carbonVortex.transferOwnership(admin2);
    }
}
