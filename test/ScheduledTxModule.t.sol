// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ScheduledTxModule} from "../src/ScheduledTxModule.sol";
import {TestSafeBase} from "./utils/TestSafeBase.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ScheduledTxModuleTest is TestSafeBase {
    ScheduledTxModule scheduledTxModule;
    SafeInstance instance;
    ERC20 token;

    function setUp() public {
        scheduledTxModule = new ScheduledTxModule();
        (, uint256 key) = makeAddrAndKey("alice");
        uint256[] memory ownerPKs = new uint256[](1);
        ownerPKs[0] = key;
        instance = _setupSafe(ownerPKs, 1, 0);
        enableModule(instance, address(scheduledTxModule));

        MockERC20 mockToken = new MockERC20("MockToken", "MTK");
        mockToken.mint(address(instance.safe), 1000 ether);
        token = ERC20(mockToken);
        vm.deal(address(instance.safe), 1000 ether);
    }

    function getDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ScheduledTxModule")),
                keccak256(bytes("1")),
                block.chainid,
                address(scheduledTxModule)
            )
        );
    }

    function test_Transfer() public {
        address receiver = makeAddr("bob");
        bool result = execTransaction(instance, receiver, 0.5 ether, "");
        assertTrue(result);
        assertEq(receiver.balance, 0.5 ether);
    }

    function test_ERC20Transfer() public {
        address to = makeAddr("bob");
        uint256 amount = 1 ether;
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", to, amount);
        uint64 executeAfter = uint64(block.timestamp);
        uint64 deadline = uint64(block.timestamp + 1 days);

        uint256 beforeBalanceBob = token.balanceOf(to);
        uint256 beforeBalanceSafe = token.balanceOf(address(instance.safe));

        // Generate EIP-712 signature
        bytes32 structHash = keccak256(
            abi.encode(scheduledTxModule.PERMIT_TYPEHASH(), address(token), 0, data, 0, executeAfter, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(instance.ownerPKs[0], digest);

        // Execute the scheduled transaction
        scheduledTxModule.execute(
            address(instance.safe), address(token), 0, data, 0, executeAfter, deadline, abi.encodePacked(r, s, v)
        );

        // Verify balances
        assertEq(token.balanceOf(to) - beforeBalanceBob, amount);
        assertEq(beforeBalanceSafe - token.balanceOf(address(instance.safe)), amount);
    }

    function test_ExecuteTransaction() public {
        address to = makeAddr("bob");
        uint256 value = 1 ether;
        uint64 executeAfter = uint64(block.timestamp);
        uint64 deadline = uint64(block.timestamp + 1 days);

        uint256 beforeBalanceBob = to.balance;
        uint256 beforeBalanceSafe = address(instance.safe).balance;

        // Generate EIP-712 signature
        bytes32 structHash =
            keccak256(abi.encode(scheduledTxModule.PERMIT_TYPEHASH(), to, value, bytes(""), 0, executeAfter, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(instance.ownerPKs[0], digest);

        // Execute the scheduled transaction
        scheduledTxModule.execute(
            address(instance.safe), to, value, "", 0, executeAfter, deadline, abi.encodePacked(r, s, v)
        );

        // Verify balances
        assertEq(to.balance - beforeBalanceBob, value);
        assertEq(beforeBalanceSafe - address(instance.safe).balance, value);
    }

    function test_RevertIfCalledEarly() public {
        address to = makeAddr("bob");
        uint256 value = 1 ether;
        uint64 executeAfter = uint64(block.timestamp + 1 hours);
        uint64 deadline = uint64(block.timestamp + 1 days);

        bytes32 structHash =
            keccak256(abi.encode(scheduledTxModule.PERMIT_TYPEHASH(), to, value, bytes(""), 0, executeAfter, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(instance.ownerPKs[0], digest);

        vm.expectRevert(ScheduledTxModule.TooEarly.selector);
        scheduledTxModule.execute(
            address(instance.safe), to, value, "", 0, executeAfter, deadline, abi.encodePacked(r, s, v)
        );
    }

    function test_RevertIfCalledAfterDeadline() public {
        address to = makeAddr("bob");
        uint256 value = 1 ether;
        uint64 executeAfter = uint64(block.timestamp);
        uint64 deadline = uint64(block.timestamp + 1 hours);

        bytes32 structHash =
            keccak256(abi.encode(scheduledTxModule.PERMIT_TYPEHASH(), to, value, bytes(""), 0, executeAfter, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(instance.ownerPKs[0], digest);

        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert(ScheduledTxModule.TransactionExpired.selector);
        scheduledTxModule.execute(
            address(instance.safe), to, value, "", 0, executeAfter, deadline, abi.encodePacked(r, s, v)
        );
    }

    function test_RevertIfAlreadyExecuted() public {
        address to = makeAddr("bob");
        uint256 value = 1 ether;
        uint64 executeAfter = uint64(block.timestamp);
        uint64 deadline = uint64(block.timestamp + 1 days);
        uint256 nonce = 0;

        bytes32 structHash = keccak256(
            abi.encode(scheduledTxModule.PERMIT_TYPEHASH(), to, value, bytes(""), nonce, executeAfter, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(instance.ownerPKs[0], digest);

        scheduledTxModule.execute(
            address(instance.safe), to, value, "", nonce, executeAfter, deadline, abi.encodePacked(r, s, v)
        );

        vm.expectRevert(ScheduledTxModule.AlreadyExecuted.selector);
        scheduledTxModule.execute(
            address(instance.safe), to, value, "", nonce, executeAfter, deadline, abi.encodePacked(r, s, v)
        );
    }

    function test_RevertWhenSignaturesAreInvalid() public {
        address to = makeAddr("bob");
        uint256 value = 1 ether;
        uint64 executeAfter = uint64(block.timestamp);
        uint64 deadline = uint64(block.timestamp + 1 days);

        bytes32 structHash =
            keccak256(abi.encode(scheduledTxModule.PERMIT_TYPEHASH(), to, value, bytes(""), 0, executeAfter, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), structHash));

        (, uint256 wrongKey) = makeAddrAndKey("eve");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, digest);

        vm.expectRevert();
        scheduledTxModule.execute(
            address(instance.safe), to, value, "", 0, executeAfter, deadline, abi.encodePacked(r, s, v)
        );
    }

    function test_ModuleTxFailureReverts() public {
        address to = makeAddr("bob");
        uint256 value = 1000000 ether;
        uint64 executeAfter = uint64(block.timestamp);
        uint64 deadline = uint64(block.timestamp + 1 days);

        bytes32 structHash =
            keccak256(abi.encode(scheduledTxModule.PERMIT_TYPEHASH(), to, value, bytes(""), 0, executeAfter, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(instance.ownerPKs[0], digest);

        vm.expectRevert(ScheduledTxModule.ModuleTxFailed.selector);
        scheduledTxModule.execute(
            address(instance.safe), to, value, "", 0, executeAfter, deadline, abi.encodePacked(r, s, v)
        );
    }

    function test_CannotUseSignatureFromAnotherSafe() public {
        (, uint256 bobKey) = makeAddrAndKey("bob");
        uint256[] memory bobPKs = new uint256[](1);
        bobPKs[0] = bobKey;
        SafeInstance memory instance2 = _setupSafe(bobPKs, 1, 1);
        enableModule(instance2, address(scheduledTxModule));
        vm.deal(address(instance2.safe), 1000 ether);

        address to = makeAddr("charlie");
        uint256 value = 1 ether;
        uint64 executeAfter = uint64(block.timestamp);
        uint64 deadline = uint64(block.timestamp + 1 days);

        bytes32 structHash =
            keccak256(abi.encode(scheduledTxModule.PERMIT_TYPEHASH(), to, value, bytes(""), 0, executeAfter, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(instance.ownerPKs[0], digest);

        vm.expectRevert();
        scheduledTxModule.execute(
            address(instance2.safe), to, value, "", 0, executeAfter, deadline, abi.encodePacked(r, s, v)
        );
    }

    function test_RevertIfModuleDisabled() public {
        address to = makeAddr("bob");
        uint256 value = 1 ether;
        uint64 executeAfter = uint64(block.timestamp);
        uint64 deadline = uint64(block.timestamp + 1 days);

        bytes32 structHash =
            keccak256(abi.encode(scheduledTxModule.PERMIT_TYPEHASH(), to, value, bytes(""), 0, executeAfter, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(instance.ownerPKs[0], digest);

        bytes memory disableModuleData =
            abi.encodeWithSignature("disableModule(address,address)", address(0x1), address(scheduledTxModule));
        execTransaction(instance, address(instance.safe), 0, disableModuleData);

        vm.expectRevert();
        scheduledTxModule.execute(
            address(instance.safe), to, value, "", 0, executeAfter, deadline, abi.encodePacked(r, s, v)
        );
    }

    function test_RevertIfSafeConfigurationChanges() public {
        address to = makeAddr("bob");
        uint64 executeAfter = uint64(block.timestamp);
        uint64 deadline = uint64(block.timestamp + 1 days);

        bytes32 structHash = keccak256(
            abi.encode(scheduledTxModule.PERMIT_TYPEHASH(), to, 1 ether, bytes(""), 0, executeAfter, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(instance.ownerPKs[0], digest);

        (, uint256 newOwnerKey) = makeAddrAndKey("newOwner");
        bytes memory swapOwnerData = abi.encodeWithSignature(
            "swapOwner(address,address,address)", address(0x1), vm.addr(instance.ownerPKs[0]), vm.addr(newOwnerKey)
        );
        execTransaction(instance, address(instance.safe), 0, swapOwnerData);

        vm.expectRevert();
        scheduledTxModule.execute(
            address(instance.safe), to, 1 ether, "", 0, executeAfter, deadline, abi.encodePacked(r, s, v)
        );
    }
}
