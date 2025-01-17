// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/QuadraticVoting.sol";


contract QuadraticVotingTest is Test {
    QuadraticVotingSystem public voting;
    
    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    address constant EAS = 0xC2679fBD37d54388Ce493F1DB75320D236e1815e;
    bytes32 constant SCHEMA_ID = 0xcb0aeacdb62eef72b03b9a4380caf5c4d5cd39d4afe5f6863725b2ebaf414f50;
    uint256 constant TOKEN_AMOUNT = 1000 ether;

    function setUp() public {
        // Fork Sepolia
        uint256 forkId = vm.createSelectFork(
            vm.envString("SEPOLIA_RPC_URL")
        );
        
        vm.deal(admin, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        
        vm.prank(admin);
        voting = new QuadraticVotingSystem(EAS);
    }

    function testProjectJoining() public {
        console.log("Creating project...");
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",  // Keep project name simple
            "Test project",
            TOKEN_AMOUNT,
            SCHEMA_ID,
            block.timestamp + 1 weeks
        );

        console.log("Project created with ID:", projectId);

        vm.startPrank(user1);
        console.log("User1 joining project...");
        console.log("User1 address:", user1);
        console.log("Schema ID:", vm.toString(SCHEMA_ID));
        
        voting.joinProject{value: 0.01 ether}(projectId);
        
        uint256 votingPower = voting.getUserVotingPower(projectId, user1);
        assertEq(votingPower, TOKEN_AMOUNT);
        
        vm.stopPrank();
    }

    function testFullFlow() public {
        // Create project
        vm.startPrank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Test project",
            TOKEN_AMOUNT,
            SCHEMA_ID,
            block.timestamp + 1 weeks
        );
        vm.stopPrank();

        // Join project
        vm.startPrank(user1);
        voting.joinProject{value: 0.01 ether}(projectId);
        
        uint256 poolId = voting.createPool(
            projectId,
            "Broadway Street",
            "Is this street safe for cycling?"
        );

        uint256 voteAmount = 100 ether;
        voting.castVote(projectId, poolId, voteAmount);

        uint256 userVotes = voting.getPoolVotes(projectId, poolId, user1);
        assertEq(userVotes, voteAmount);

        uint256 voteCost = uint256(Math.sqrt(voteAmount));
        uint256 expectedRemainingPower = TOKEN_AMOUNT - voteCost;
        uint256 actualRemainingPower = voting.getUserVotingPower(projectId, user1);
        
        assertEq(actualRemainingPower, expectedRemainingPower);
        
        vm.stopPrank();
    }
}