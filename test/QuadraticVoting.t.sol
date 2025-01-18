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
    uint256 constant TOKENS_PER_USER = 100 ether; // 100 tokens per user

    function setUp() public {
        mockEas = new MockEAS();
        
        vm.prank(admin);
        voting = new QuadraticVotingSystem(address(mockEas));

        vm.deal(admin, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    function testProjectCreation() public {
        vm.startPrank(admin);
        
        uint256 projectId = voting.createProject(
            "Cycling Safety",
            "Test project for cycling safety spots",
            TOKENS_PER_USER,
            SCHEMA_ID,
            block.timestamp + 1 weeks
        );
        
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
        
        assertEq(name, "Cycling Safety");
        assertEq(description, "Test project for cycling safety spots");
        assertTrue(votingToken != address(0));
        assertEq(tokensPerUser, TOKENS_PER_USER);
        assertEq(schemaId, SCHEMA_ID);
        assertTrue(isActive);
        assertEq(projectAdmin, admin);
        
        vm.stopPrank();
    }

    function testProjectJoining() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Cycling Safety",
            "Test project",
            TOKENS_PER_USER,
            SCHEMA_ID,
            block.timestamp + 1 weeks
        );

        vm.startPrank(user1);
        voting.joinProject{value: 0.01 ether}(projectId);
        
        uint256 tokensLeft = voting.getUserTokensLeft(projectId, user1);
        assertEq(tokensLeft, TOKENS_PER_USER, "Should have full tokens after joining");
        
        vm.stopPrank();
    }

    function testQuadraticVoting() public {
        // Create project
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Cycling Safety",
            "Test project",
            TOKENS_PER_USER,
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

        // Test quadratic voting mechanics
        uint256 numVotes = 3;               // Want to cast 3 votes
        uint256 expectedCost = 9;           // Should cost 9 tokens (3^2)
        
        uint256 initialTokens = voting.getUserTokensLeft(projectId, user1);
        voting.castVote(projectId, poolId, numVotes);

        // Verify votes cast
        uint256 votesRecorded = voting.getPoolVotes(projectId, poolId, user1);
        assertEq(votesRecorded, numVotes, "Should record the number of votes cast");

        // Verify tokens spent
        uint256 tokensLeft = voting.getUserTokensLeft(projectId, user1);
        assertEq(tokensLeft, initialTokens - expectedCost, "Should deduct squared number of tokens");
        
        vm.stopPrank();
    }

    function testFailExcessiveVoting() public {
        // Create project with 100 tokens per user
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Cycling Safety",
            "Test project",
            100,  // Only 100 tokens
            SCHEMA_ID,
            block.timestamp + 1 weeks
        );

        vm.startPrank(user1);
        voting.joinProject{value: 0.01 ether}(projectId);
        
        uint256 poolId = voting.createPool(
            projectId,
            "Broadway Street",
            "Is this street safe for cycling?"
        );

        // Try to cast 11 votes which would cost 11^2 = 121 tokens (more than available)
        voting.castVote(projectId, poolId, 11);
        
        vm.stopPrank();
    }

   function testMultipleUsersVoting() public {
        // Create project
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Cycling Safety",
            "Test project",
            TOKENS_PER_USER,
            SCHEMA_ID,
            block.timestamp + 1 weeks
        );

        // User1 joins and creates pool
        vm.startPrank(user1);
        voting.joinProject{value: 0.01 ether}(projectId);
        
        uint256 poolId = voting.createPool(
            projectId,
            "Broadway Street",
            "Is this street safe for cycling?"
        );

        // User1 votes
        voting.castVote(projectId, poolId, 3);  // 9 tokens for 3 votes
        vm.stopPrank();

        // User2 joins and votes
        vm.startPrank(user2);
        voting.joinProject{value: 0.01 ether}(projectId);
        voting.castVote(projectId, poolId, 4);  // 16 tokens for 4 votes
        vm.stopPrank();

        // Verify votes
        assertEq(voting.getPoolVotes(projectId, poolId, user1), 3, "User1 votes wrong");
        assertEq(voting.getPoolVotes(projectId, poolId, user2), 4, "User2 votes wrong");

        // Verify remaining tokens
        assertEq(voting.getUserTokensLeft(projectId, user1), TOKENS_PER_USER - 9, "User1 tokens wrong");  // 100 - 9 = 91
        assertEq(voting.getUserTokensLeft(projectId, user2), TOKENS_PER_USER - 16, "User2 tokens wrong"); // 100 - 16 = 84
    }

    function testFailVoteTwice() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Cycling Safety",
            "Test project",
            TOKENS_PER_USER,
            SCHEMA_ID,
            block.timestamp + 1 weeks
        );

        vm.startPrank(user1);
        voting.joinProject{value: 0.01 ether}(projectId);
        
        uint256 poolId = voting.createPool(
            projectId,
            "Broadway Street",
            "Is this street safe for cycling?"
        );

        voting.castVote(projectId, poolId, 3);
        voting.castVote(projectId, poolId, 2);  // Should fail - can't vote twice
        
        vm.stopPrank();
    }

    function testFailVoteWithoutJoining() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Cycling Safety",
            "Test project",
            TOKENS_PER_USER,
            SCHEMA_ID,
            block.timestamp + 1 weeks
        );

        vm.prank(user1);
        uint256 poolId = voting.createPool(
            projectId,
            "Broadway Street",
            "Is this street safe for cycling?"
        );

        vm.prank(user2);  // user2 hasn't joined
        voting.castVote(projectId, poolId, 3);  // Should fail
    }

    function testFailCreateProjectNonAdmin() public {
        vm.prank(user1);  // non-admin
        voting.createProject(
            "Cycling Safety",
            "Test project",
            TOKENS_PER_USER,
            SCHEMA_ID,
            block.timestamp + 1 weeks
        );  // Should fail
    }

    function testFailCreatePoolAfterEnd() public {
        // Create project that ends in 1 day
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Cycling Safety",
            "Test project",
            TOKENS_PER_USER,
            SCHEMA_ID,
            block.timestamp + 1 days
        );

        vm.startPrank(user1);
        voting.joinProject{value: 0.01 ether}(projectId);

        // Warp to after end time
        vm.warp(block.timestamp + 2 days);

        // Try to create pool after end
        voting.createPool(
            projectId,
            "Broadway Street",
            "Is this street safe for cycling?"
        );  // Should fail
        
        vm.stopPrank();
    }
}