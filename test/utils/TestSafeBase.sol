// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {Safe} from "safe-smart-account/Safe.sol";
import {SafeProxyFactory} from "safe-smart-account/proxies/SafeProxyFactory.sol";
import {SafeProxy} from "safe-smart-account/proxies/SafeProxy.sol";
import {CompatibilityFallbackHandler} from "safe-smart-account/handler/CompatibilityFallbackHandler.sol";
import {ModuleManager} from "safe-smart-account/base/ModuleManager.sol";
import {Enum} from "safe-smart-account/common/Enum.sol";
import {Test} from "forge-std/Test.sol";

abstract contract TestSafeBase is Test {
    struct SafeInstance {
        Safe safe;
        uint256[] ownerPKs;
        uint256 threshold;
    }

    Safe internal singleton = new Safe();
    SafeProxyFactory internal proxyFactory = new SafeProxyFactory();
    CompatibilityFallbackHandler internal handler = new CompatibilityFallbackHandler();

    function _setupSafe(uint256[] memory ownerPKs, uint256 threshold, uint256 salt)
        public
        returns (SafeInstance memory)
    {
        address[] memory owners = new address[](ownerPKs.length);
        for (uint256 i; i < ownerPKs.length; i++) {
            owners[i] = vm.addr(ownerPKs[i]);
        }

        bytes memory initData = abi.encodeWithSelector(
            Safe.setup.selector, owners, threshold, address(0), address(0), address(handler), address(0), 0, address(0)
        );

        SafeProxy deployedSafe =
            SafeProxy(payable(proxyFactory.createProxyWithNonce(address(singleton), initData, salt)));

        return SafeInstance({safe: Safe(payable(deployedSafe)), ownerPKs: ownerPKs, threshold: threshold});
    }

    function enableModule(SafeInstance memory instance, address module) public {
        execTransaction(
            instance,
            address(instance.safe),
            0,
            abi.encodeWithSelector(ModuleManager.enableModule.selector, module),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            address(0),
            ""
        );
    }

    function execTransaction(
        SafeInstance memory instance,
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        bytes memory signatures
    ) internal returns (bool) {
        return _execTransaction(
            instance, to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, signatures
        );
    }

    function execTransaction(SafeInstance memory instance, address to, uint256 value, bytes memory data)
        internal
        returns (bool)
    {
        return _execTransaction(instance, to, value, data, Enum.Operation.Call, 0, 0, 0, address(0), address(0), "");
    }

    function _execTransaction(
        SafeInstance memory instance,
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        bytes memory signatures
    ) internal returns (bool) {
        bytes32 safeTxHash;
        {
            uint256 _nonce = instance.safe.nonce();
            safeTxHash = instance.safe.getTransactionHash({
                to: to,
                value: value,
                data: data,
                operation: operation,
                safeTxGas: safeTxGas,
                baseGas: baseGas,
                gasPrice: gasPrice,
                gasToken: gasToken,
                refundReceiver: refundReceiver,
                _nonce: _nonce
            });
        }

        if (signatures.length == 0) {
            for (uint256 i; i < instance.ownerPKs.length; ++i) {
                uint256 pk = instance.ownerPKs[i];
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, safeTxHash);
                // Smart contracts as signers not taken into consideration
                signatures = bytes.concat(signatures, abi.encodePacked(r, s, v));
            }
        }

        return instance.safe.execTransaction({
            to: to,
            value: value,
            data: data,
            operation: operation,
            safeTxGas: safeTxGas,
            baseGas: baseGas,
            gasPrice: gasPrice,
            gasToken: gasToken,
            refundReceiver: payable(refundReceiver),
            signatures: signatures
        });
    }
}
