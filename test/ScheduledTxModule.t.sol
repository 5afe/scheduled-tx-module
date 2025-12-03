// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ScheduledTxModule} from "../src/ScheduledTxModule.sol";

contract CounterTest is Test {
    ScheduledTxModule public scheduledTxModule;

    function setUp() public {
        scheduledTxModule = new ScheduledTxModule();
    }

    function test_Increment() public {}
}
