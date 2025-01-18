// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/QuadraticVoting.sol";
import "./MockEAS.sol";

contract QuadraticVotingTest is Test {
    QuadraticVotingSystem public voting;
    MockEAS public mockEas;
    
    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    bytes32 constant SCHEMA_ID = 0xcb0aeacdb62eef72b03b9a4380caf5c4d5cd39d4afe5f6863725b2ebaf414f50;
    uint256 constant TOKEN_AMOUNT = 1000 ether;

    function setUp() public {
        // Deploy mock EAS
        mockEas = new MockEAS();
        
        // Deploy voting system with mock EAS
        vm.prank(admin);
        voting = new QuadraticVotingSystem(address(mockEas));

        // Set ETH balances
        vm.deal(admin, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    function testProjectCreation() public {
        vm.startPrank(admin);
        
        uint256 projectId = voting.createProject(
            "Cycling Safety",
            "Test project for cycling safety spots",
            TOKEN_AMOUNT,
            SCHEMA_ID,
            block.timestamp + 1 weeks
        );
        
        // Get project info and verify
        (
            string memory name,
            string memory description,
            address votingToken,
            uint256 tokensPerUser,
            bytes32 schemaId,
            bool isActive,
            ,  // endTime
            address projectAdmin
        ) = voting.getProject(projectId);
        
        // Assert project details
        assertEq(name, "Cycling Safety");
        assertEq(description, "Test project for cycling safety spots");
        assertTrue(votingToken != address(0));
        assertEq(tokensPerUser, TOKEN_AMOUNT);
        assertEq(schemaId, SCHEMA_ID);
        assertTrue(isActive);
        assertEq(projectAdmin, admin);
        
        vm.stopPrank();
    }

    function testProjectJoining() public {
        // Create project first
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Cycling Safety",
            "Test project",
            TOKEN_AMOUNT,
            SCHEMA_ID,
            block.timestamp + 1 weeks
        );

        // User joins project
        vm.startPrank(user1);
        voting.joinProject{value: 0.01 ether}(projectId);
        
        // Verify user's voting power
        uint256 votingPower = voting.getUserVotingPower(projectId, user1);
        assertEq(votingPower, TOKEN_AMOUNT);
        
        vm.stopPrank();
    }

    function testPoolCreation() public {
        // Create project
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Cycling Safety",
            "Test project",
            TOKEN_AMOUNT,
            SCHEMA_ID,
            block.timestamp + 1 weeks
        );

        // User joins and creates pool
        vm.startPrank(user1);
        voting.joinProject{value: 0.01 ether}(projectId);
        
        uint256 poolId = voting.createPool(
            projectId,
            "Broadway Street",
            "Is this street safe for cycling?"
        );

        // Verify pool was created
        assertEq(voting.getPoolCount(projectId), 1);
        
        vm.stopPrank();
    }

    function testVoting() public {
        // Create project
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Cycling Safety",
            "Test project",
            TOKEN_AMOUNT,
            SCHEMA_ID,
            block.timestamp + 1 weeks
        );

        // User joins, creates pool and votes
        vm.startPrank(user1);
        
        voting.joinProject{value: 0.01 ether}(projectId);
        uint256 poolId = voting.createPool(
            projectId,
            "Broadway Street",
            "Is this street safe for cycling?"
        );

        uint256 voteAmount = 100 ether;
        voting.castVote(projectId, poolId, voteAmount);

        // Verify vote was recorded
        uint256 userVotes = voting.getPoolVotes(projectId, poolId, user1);
        assertEq(userVotes, voteAmount);

        // Verify voting power was reduced by sqrt(voteAmount)
        uint256 voteCost = Math.sqrt(voteAmount); // sqrt(100) = 10
        uint256 expectedRemainingPower = TOKEN_AMOUNT - voteCost;
        uint256 actualRemainingPower = voting.getUserVotingPower(projectId, user1);
        assertEq(actualRemainingPower, expectedRemainingPower);
        
        vm.stopPrank();
    }
}