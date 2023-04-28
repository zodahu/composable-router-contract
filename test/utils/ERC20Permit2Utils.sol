// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {SafeERC20, IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {IParam} from 'src/interfaces/IParam.sol';
import {IAllowanceTransfer} from 'permit2/interfaces/IAllowanceTransfer.sol';
import {PermitSignature} from './permit2/PermitSignature.sol';
import {EIP712} from './permit2/Permit2EIP712.sol';

contract ERC20Permit2Utils is Test, PermitSignature {
    using SafeERC20 for IERC20;

    uint256 public constant SIGNER_REFERRAL = 1;
    address internal constant permit2Addr = address(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    address internal _erc20User;
    address internal _erc20Agent;
    uint256 internal _erc20UserPrivateKey;
    bytes32 DOMAIN_SEPARATOR;

    function erc20Permit2UtilsSetUp(address user_, uint256 userPrivateKey_, address agent) internal {
        _erc20User = user_;
        _erc20UserPrivateKey = userPrivateKey_;
        _erc20Agent = agent;
        DOMAIN_SEPARATOR = EIP712(permit2Addr).DOMAIN_SEPARATOR();
    }

    function permitToken(IERC20 token) internal {
        // Approve token to permit2
        vm.startPrank(_erc20User);
        token.safeApprove(permit2Addr, type(uint256).max);

        // Create signed permit
        uint48 defaultNonce = 0;
        uint48 defaultExpiration = uint48(block.timestamp + 5);
        IAllowanceTransfer.PermitSingle memory permit = defaultERC20PermitAllowance(
            address(token),
            type(uint160).max,
            _erc20Agent,
            defaultExpiration,
            defaultNonce
        );
        bytes memory sig = getPermitSignature(permit, _erc20UserPrivateKey, DOMAIN_SEPARATOR);

        // Permit Token
        IAllowanceTransfer(permit2Addr).permit(_erc20User, permit, sig);
        vm.stopPrank();
    }

    function logicERC20Permit2PullToken(IERC20 token, uint160 amount) internal view returns (IParam.Logic memory) {
        IParam.Input[] memory inputsEmpty;

        return
            IParam.Logic(
                address(permit2Addr), // to
                abi.encodeWithSignature(
                    'transferFrom(address,address,uint160,address)',
                    _erc20User,
                    _erc20Agent,
                    amount,
                    token
                ),
                inputsEmpty,
                IParam.WrapMode.NONE,
                address(0), // approveTo
                address(0) // callback
            );
    }
}
