// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { StringUtil } from "./StringUtil.sol";
import { MockERC20 } from "../../../test/foundry/mocks/token/MockERC20.sol";
import { Users, UsersLib } from "../../../test/foundry/utils/Users.t.sol";

contract BroadcastManager is Script {
    address public multisig;
    address public deployer;
    address public relayer;
    address public guardian;

    function _beginBroadcast() internal {
        uint256 deployerPrivateKey;
        if (block.chainid == 1512) {
            deployerPrivateKey = vm.envUint("STORY_PRIVATEKEY");
            deployer = vm.addr(deployerPrivateKey);
            multisig = vm.envAddress("STORY_MULTISIG_ADDRESS");
            relayer = vm.envAddress("STORY_RELAYER_ADDRESS");
            guardian = vm.envAddress("STORY_GUARDIAN_ADDRESS");
            vm.startBroadcast(deployerPrivateKey);
        } else if (block.chainid == 1513) {
            deployerPrivateKey = vm.envUint("STORY_PRIVATEKEY");
            deployer = vm.addr(deployerPrivateKey);
            multisig = vm.envAddress("STORY_MULTISIG_ADDRESS");
            relayer = vm.envAddress("STORY_RELAYER_ADDRESS");
            guardian = vm.envAddress("STORY_GUARDIAN_ADDRESS");
            vm.startBroadcast(deployerPrivateKey);
        } else if (block.chainid == 1516) {
            deployerPrivateKey = vm.envUint("STORY_PRIVATEKEY");
            deployer = vm.addr(deployerPrivateKey);
            multisig = vm.envAddress("STORY_MULTISIG_ADDRESS");
            relayer = vm.envAddress("STORY_RELAYER_ADDRESS");
            guardian = vm.envAddress("STORY_GUARDIAN_ADDRESS");
            vm.startBroadcast(deployerPrivateKey);
        } else if (block.chainid == 1315) {
            deployerPrivateKey = vm.envUint("STORY_PRIVATEKEY");
            deployer = vm.addr(deployerPrivateKey);
            multisig = vm.envAddress("STORY_MULTISIG_ADDRESS");
            relayer = vm.envAddress("STORY_RELAYER_ADDRESS");
            guardian = vm.envAddress("STORY_GUARDIAN_ADDRESS");
            vm.startBroadcast(deployerPrivateKey);
        } else if (block.chainid == 1337) {
            deployerPrivateKey = vm.envUint("STORY_PRIVATEKEY");
            deployer = vm.addr(deployerPrivateKey);
            multisig = vm.envAddress("STORY_MULTISIG_ADDRESS");
            relayer = vm.envAddress("STORY_RELAYER_ADDRESS");
            guardian = vm.envAddress("STORY_GUARDIAN_ADDRESS");
            vm.startBroadcast(deployerPrivateKey);
        } else if (block.chainid == 1514) {
            deployerPrivateKey = vm.envUint("STORY_PRIVATEKEY");
            deployer = vm.addr(deployerPrivateKey);
            multisig = vm.envAddress("STORY_MULTISIG_ADDRESS");
            relayer = vm.envAddress("STORY_RELAYER_ADDRESS");
            guardian = vm.envAddress("STORY_GUARDIAN_ADDRESS");
            vm.startBroadcast(deployerPrivateKey);
        } else if (block.chainid == 31337) {
            Users memory u = UsersLib.createMockUsers(vm);
            // DeployHelper.sol will set the final admin as the multisig, so we do this for coherence
            // with the tests (DeployHelper.sol is used both in tests and in the deployment scripts)
            multisig = u.admin;
            deployer = u.alice;
            relayer = u.relayer;
            vm.startPrank(deployer);
        } else if (block.chainid == 1399) {
            deployerPrivateKey = vm.envUint("STORY_PRIVATEKEY");
            deployer = vm.addr(deployerPrivateKey);
            multisig = vm.envAddress("STORY_MULTISIG_ADDRESS");
            relayer = vm.envAddress("STORY_RELAYER_ADDRESS");
            vm.startBroadcast(deployerPrivateKey);
        } else {
            console2.log("Unsupported chain", block.chainid);
            revert("Unsupported chain");
        }
    }

    function _endBroadcast() internal {
        if (block.chainid == 31337) {
            vm.stopPrank();
        } else {
            vm.stopBroadcast();
        }
    }
}
