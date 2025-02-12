// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Factory, QuadraticVoting} from "../src/QuadraticVoting.sol";

import "forge-std/console.sol";

import "../lib/forge-std/src/console.sol";

import "forge-std/console2.sol";



contract DeployFactory is Script {
    // OP Testnet passport scorer
    address constant PASSPORT_SCORER =
        0xe53C60F8069C2f0c3a84F9B3DB5cf56f3100ba56;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Factory
        Factory qv =  new Factory(
            PASSPORT_SCORER
        );
    //     QuadraticVoting.UserInfoView memory value = qv.getUserInfo(0xc6Ce7736B846d7Ce13fb533152283340E6771263);
    //     // console.log(value.isRegistered);
    //     // console.log(value.isVerified);
    //     console.log(value.tokensLeft);
    //     // console.log(value.lastScoreCheck);
    //     console.log(value.passportScore);
    //     // console.log(value.totalVotesCast);
    //     console.log("---------------");




    //    QuadraticVoting.ProjectDetails memory data =  qv.getProjectInfo();
    //     console.log(data.tokensPerUser);
    //     console.log(data.tokensPerVerifiedUser);
    //     console.log(data.minScoreToJoin);
    //     console.log(data.minScoreToVerify);


    //     uint256 score = qv.getPassportScore(0xc6Ce7736B846d7Ce13fb533152283340E6771263);
    //     console.log("Score is",score);

        vm.stopBroadcast();

    }
}
