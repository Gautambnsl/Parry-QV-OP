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

        Factory factory =  new Factory(
            PASSPORT_SCORER
        );


        // Factory factory =   Factory(
        //     0x02F59DE6a66B7e9bb63fD3e112A3d03c043a5278
        // );

        // factory.executeMetaTransaction(0xA92ea390D2Cd54239050b9ea044BB02690CF27F8, "0xe8df8d800000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000000005000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000003e800000000000000000000000000000000000000000000000000000000000005dc0000000000000000000000000000000000000000000000000000000073a695dd000000000000000000000000000000000000000000000000000000000000000667617574616d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000667617574616d000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000026c6c000000000000000000000000000000000000000000000000000000000000");

        //factory.createProject("gautam","gautam","ll",5,10,1000,1500,1940297181);

        // console.log(factory.owner());
        // console.log(QuadraticVoting(0xB25E3cfea43Ad89B748735937150d04c411d98aB).owner());
        //QuadraticVoting(0x0b916a3f244E86EfE387c3FbE80709e9Eb8f5580).joinProject();
        //QuadraticVoting(0x0b916a3f244E86EfE387c3FbE80709e9Eb8f5580).castVote(0, 1);

        

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
