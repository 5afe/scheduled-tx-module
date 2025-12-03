// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ScheduledTxModule} from "../src/ScheduledTxModule.sol";

contract ScheduledTxModuleScript is Script {
    ScheduledTxModule public scheduledTxModule;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        scheduledTxModule = new ScheduledTxModule();

        vm.stopBroadcast();
    }
}
