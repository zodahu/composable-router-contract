// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {SafeERC20, IERC20, Address} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {IAgent} from '../interfaces/IAgent.sol';
import {IParam} from '../interfaces/IParam.sol';
import {IRouter} from '../interfaces/IRouter.sol';
import {IBalancerV2FlashLoanCallback} from '../interfaces/callbacks/IBalancerV2FlashLoanCallback.sol';
import {FeeLogic} from '../libraries/FeeLogic.sol';
import {CallbackFeeBase} from './CallbackFeeBase.sol';

/// @title Balancer V2 flash loan callback
/// @notice Invoked by Balancer V2 vault to call the current user's agent
contract BalancerV2FlashLoanCallback is IBalancerV2FlashLoanCallback, CallbackFeeBase {
    using SafeERC20 for IERC20;
    using Address for address;
    using FeeLogic for IParam.Fee;

    address public immutable router;
    address public immutable balancerV2Vault;
    bytes32 internal constant _META_DATA = bytes32(bytes('balancer-v2:flash-loan'));

    constructor(address router_, address balancerV2Vault_, uint256 feeRate_) CallbackFeeBase(feeRate_, _META_DATA) {
        router = router_;
        balancerV2Vault = balancerV2Vault_;
    }

    function receiveFlashLoan(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata userData
    ) external {
        if (msg.sender != balancerV2Vault) revert InvalidCaller();
        (, address agent) = IRouter(router).getCurrentUserAgent();

        // Transfer assets to the agent and record initial balances
        uint256 tokensLength = tokens.length;
        uint256[] memory initBalances = new uint256[](tokensLength);
        for (uint256 i; i < tokensLength; ) {
            address token = tokens[i];
            uint256 amount = amounts[i];
            IParam.Fee memory fee = FeeLogic.getFee(token, amount, feeRate, metadata);
            fee.charge(IRouter(router).feeCollector());
            IERC20(token).safeTransfer(agent, amount - fee.amount);
            initBalances[i] = IERC20(token).balanceOf(address(this));

            unchecked {
                ++i;
            }
        }

        agent.functionCall(
            abi.encodePacked(IAgent.executeByCallback.selector, userData),
            'ERROR_BALANCER_V2_FLASH_LOAN_CALLBACK'
        );

        // Repay tokens to Vault
        for (uint256 i; i < tokensLength; ) {
            address token = tokens[i];
            IERC20(token).safeTransfer(balancerV2Vault, amounts[i] + feeAmounts[i]);

            // Check balance is valid
            if (IERC20(token).balanceOf(address(this)) != initBalances[i]) revert InvalidBalance(token);

            unchecked {
                ++i;
            }
        }
    }
}
