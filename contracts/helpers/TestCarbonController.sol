// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { CarbonController } from "../carbon/CarbonController.sol";
import { IVoucher } from "../voucher/interfaces/IVoucher.sol";
import { Token } from "../token/Token.sol";

contract TestCarbonController is CarbonController {
    constructor(IVoucher initVoucher, address proxy) CarbonController(initVoucher, proxy) {}

    function testSetAccumulatedFees(Token token, uint256 amount) external {
        _accumulatedFees[token] = amount;
    }

    receive() external payable {}
}
