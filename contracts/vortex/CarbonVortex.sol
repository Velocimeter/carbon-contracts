// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { ICarbonVortex } from "./interfaces/ICarbonVortex.sol";
import { IVersioned } from "../utility/interfaces/IVersioned.sol";
import { ICarbonController } from "../carbon/interfaces/ICarbonController.sol";
import { Upgradeable } from "../utility/Upgradeable.sol";
import { Token } from "../token/Token.sol";
import { Utils } from "../utility/Utils.sol";
import { MathEx } from "../utility/MathEx.sol";
import { MAX_GAP, PPM_RESOLUTION } from "../utility/Constants.sol";

/**
 * @dev CarbonVortex contract
 */
contract CarbonVortex is ICarbonVortex, Upgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, Utils {
    using Address for address payable;

    ICarbonController private immutable _carbonController;

    address private _tank;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP - 1] private __gap;

    /**
     * @dev used to set immutable state variables and initialize the implementation
     */
    constructor(
        ICarbonController carbonController
    ) validAddress(address(carbonController)) {
        _carbonController = carbonController;
        initialize();
    }

    /**
     * @dev fully initializes the contract and its parents
     */
    function initialize() public initializer {
        __CarbonVortex_init();
    }

    // solhint-disable func-name-mixedcase

    /**
     * @dev initializes the contract and its parents
     */
    function __CarbonVortex_init() internal onlyInitializing {
        __Upgradeable_init();
        __ReentrancyGuard_init();
        __Ownable_init();
    }

    /**
     * @dev authorize the contract to receive the native token
     */
    receive() external payable {}

    /**
     * @dev perform various validations for the token array
     */
    modifier validateTokens(Token[] calldata tokens) {
        _validateTokens(tokens);
        _;
    }

    /**
     * @inheritdoc Upgradeable
     */
    function version() public pure override(IVersioned, Upgradeable) returns (uint16) {
        return 2;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function availableTokens(Token token) external view returns (uint256) {
        return _carbonController.accumulatedFees(token) + token.balanceOf(address(this));
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function tank() external view returns (address) {
        return _tank;
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function setTank(address newTank) external onlyOwner validAddress(newTank) {
        address prevTank = _tank;
        if (prevTank == newTank) {
            return;
        }

        _tank = newTank;
        emit TankSet({ prevTank: prevTank, newTank: newTank });
    }

    /**
     * @inheritdoc ICarbonVortex
     */
    function execute(Token[] calldata tokens) external nonReentrant validateTokens(tokens) {
        uint256 len = tokens.length;

        // allocate balances array for the tokens
        uint256[] memory balances = new uint256[](len);

        // withdraw fees, load balances and reward amounts
        for (uint256 i = 0; i < len; i = uncheckedInc(i)) {
            // withdraw token fees
            _carbonController.withdrawFees(tokens[i], type(uint256).max, address(this));
            // get token balance
            balances[i] = tokens[i].balanceOf(address(this));
        }

        // allocate rewards to tank
        _allocateRewards(_tank, tokens, balances);
    }

    /**
     * @dev allocates the rewards to tank
     */
    function _allocateRewards(address sender, Token[] calldata tokens, uint256[] memory rewardAmounts) private {
        // transfer the rewards to caller
        uint256 len = tokens.length;
        for (uint256 i = 0; i < len; i = uncheckedInc(i)) {
            Token token = tokens[i];
            uint256 rewardAmount = rewardAmounts[i];
            if (rewardAmount == 0) {
                continue;
            }
            if (token.isNative()) {
                // using a regular transfer here could revert due to exceeding the 2300 gas limit
                // which is why we're using call instead (via sendValue)
                payable(sender).sendValue(rewardAmount);
            } else {
                token.safeTransfer(sender, rewardAmount);
            }
        }
    }

    function _validateTokens(Token[] calldata tokens) private pure {
        uint len = tokens.length;
        if (len == 0) {
            revert InvalidTokenLength();
        }
        for (uint256 i = 0; i < len; i = uncheckedInc(i)) {
            Token token = tokens[i];
            // validate token has no duplicates
            for (uint256 j = uncheckedInc(i); j < len; j = uncheckedInc(j)) {
                if (token == tokens[j]) {
                    revert DuplicateToken();
                }
            }
        }
    }

    function uncheckedInc(uint256 i) private pure returns (uint256 j) {
        unchecked {
            j = i + 1;
        }
    }
}
