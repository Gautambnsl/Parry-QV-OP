// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Factory} from "../src/Factory.sol";

contract DeployFactory is Script {
    // OP Testnet passport scorer
    address constant PASSPORT_SCORER = 0xe53C60F8069C2f0c3a84F9B3DB5cf56f3100ba56;
    
    function run() external returns (Factory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy Factory
        Factory factory = new Factory(PASSPORT_SCORER);
        
        vm.stopBroadcast();
    
        
        return factory;
    }
}
