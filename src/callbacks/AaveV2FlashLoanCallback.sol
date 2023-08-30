// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {SafeERC20, IERC20, Address} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {IAgent} from '../interfaces/IAgent.sol';
import {IParam} from '../interfaces/IParam.sol';
import {IRouter} from '../interfaces/IRouter.sol';
import {IAaveV2FlashLoanCallback} from '../interfaces/callbacks/IAaveV2FlashLoanCallback.sol';
import {IAaveV2Provider} from '../interfaces/aaveV2/IAaveV2Provider.sol';
import {ApproveHelper} from '../libraries/ApproveHelper.sol';
import {FeeLogic} from '../libraries/FeeLogic.sol';
import {CallbackFeeBase} from './CallbackFeeBase.sol';

/// @title Aave V2 flash loan callback
/// @notice Invoked by Aave V2 pool to call the current user's agent
contract AaveV2FlashLoanCallback is IAaveV2FlashLoanCallback, CallbackFeeBase {
    using SafeERC20 for IERC20;
    using Address for address;
    using FeeLogic for IParam.Fee;

    address public immutable router;
    address public immutable aaveV2Provider;
    bytes32 internal constant _META_DATA = bytes32(bytes('aave-v2:flash-loan'));

    constructor(address router_, address aaveV2Provider_, uint256 feeRate_) CallbackFeeBase(feeRate_, _META_DATA) {
        router = router_;
        aaveV2Provider = aaveV2Provider_;
    }

    /// @dev No need to check if `initiator` is the agent as it's certain when the below conditions are satisfied:
    ///      1. The `to` address used in agent is Aave Pool, i.e, the user signed a correct `to`
    ///      2. The callback address set in agent is this callback, i.e, the user signed a correct `callback`
    ///      3. The `msg.sender` of this callback is Aave Pool
    ///      4. The Aave pool is benign
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address, // initiator
        bytes calldata params
    ) external returns (bool) {
        address pool = IAaveV2Provider(aaveV2Provider).getLendingPool();

        if (msg.sender != pool) revert InvalidCaller();
        (, address agent) = IRouter(router).getCurrentUserAgent();

        // Transfer assets to the agent and record initial balances
        uint256 assetsLength = assets.length;
        uint256[] memory initBalances = new uint256[](assetsLength);
        for (uint256 i; i < assetsLength; ) {
            address asset = assets[i];
            uint256 amount = amounts[i];
            if (IAgent(agent).isCharging()) {
                IParam.Fee memory fee = FeeLogic.getFee(asset, amount, feeRate, metadata);
                fee.charge(IRouter(router).feeCollector());
                IERC20(asset).safeTransfer(agent, amount - fee.amount);
            } else {
                IERC20(asset).safeTransfer(agent, amount);
            }
            initBalances[i] = IERC20(asset).balanceOf(address(this));

            unchecked {
                ++i;
            }
        }

        agent.functionCall(
            abi.encodePacked(IAgent.executeByCallback.selector, params),
            'ERROR_AAVE_V2_FLASH_LOAN_CALLBACK'
        );

        // Approve assets for pulling from Aave Pool
        for (uint256 i; i < assetsLength; ) {
            address asset = assets[i];
            uint256 amountOwing = amounts[i] + premiums[i];

            // Check balance is valid
            if (IERC20(asset).balanceOf(address(this)) != initBalances[i] + amountOwing) revert InvalidBalance(asset);

            // Save gas by only the first user does approve. It's safe since this callback don't hold any asset
            ApproveHelper._approveMax(asset, pool, amountOwing);

            unchecked {
                ++i;
            }
        }

        return true;
    }
}
