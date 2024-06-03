// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { IUpgradeable } from "../../utility/interfaces/IUpgradeable.sol";
import { Token } from "../../token/Token.sol";

/**
 * @dev CarbonVortex interface
 */
interface ICarbonVortex is IUpgradeable {
    error DuplicateToken();
    error InvalidToken();
    error InvalidTokenLength();

    /**
     * @dev triggered when the tank address is updated
     */
    event TankSet(address prevTank, address newTank);

    /**
     * @dev returns the total available fees for the given token
     */
    function availableTokens(Token token) external view returns (uint256);
    
    /**
     * @dev returns the tank address to collect fees
     */
    function tank() external view returns (address);

    /**
     * @dev set the tank address to collect fees
     */
    function setTank(address newTank) external;

    /**
     * @dev withdraws the fees of the provided tokens from Carbon
     * @dev converts them along with the available contract token balance to BNT,
     * @dev rewards the caller and burns the rest of the tokens
     */
    function execute(Token[] calldata tokens) external;
}
