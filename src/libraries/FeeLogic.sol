// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {SafeERC20, IERC20, Address} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {IAllowanceTransfer} from 'permit2/interfaces/IAllowanceTransfer.sol';
import {IParam} from 'src/interfaces/IParam.sol';

library FeeLogic {
    using Address for address payable;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant BPS_BASE = 10_000;

    event FeeCharged(address indexed token, uint256 amount, bytes32 metadata);

    error InvalidChargeTarget();

    function charge(IParam.Fee memory fee, address feeCollector) internal {
        address token = fee.token;
        uint256 amount = fee.amount;
        if (amount == 0) {
            return;
        } else if (token == NATIVE) {
            payable(feeCollector).sendValue(amount);
        } else {
            IERC20(token).safeTransfer(feeCollector, amount);
        }

        emit FeeCharged(token, amount, fee.metadata);
    }

    function chargeFrom(IParam.Fee memory fee, address feeCollector, address from, address permit2) internal {
        address token = fee.token;
        uint256 amount = fee.amount;
        if (amount == 0) {
            return;
        } else if (token == NATIVE) {
            revert InvalidChargeTarget();
        } else {
            IAllowanceTransfer(permit2).transferFrom(from, feeCollector, amount.toUint160(), token);
        }

        emit FeeCharged(token, amount, fee.metadata);
    }

    function getFee(
        address token,
        uint256 amount,
        uint256 feeRate,
        bytes32 metadata
    ) internal pure returns (IParam.Fee memory ret) {
        ret = IParam.Fee(token, _calculateFee(amount, feeRate), metadata);
    }

    function _calculateFee(uint256 amount, uint256 feeRate) private pure returns (uint256) {
        return (amount * feeRate) / (BPS_BASE + feeRate);
    }
}
