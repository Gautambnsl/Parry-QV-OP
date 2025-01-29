// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/QuadraticVoting.sol";

contract QuadraticVotingTest is Test {
    QuadraticVotingSystem public voting;

    address public admin = makeAddr("admin");
    // Real addresses with known passport scores
    address public user1 = makeAddr("user1"); // Score 0 - can't join
    address public user2 = 0xb974C9Aaf445ba8ABEe973E36781F658c98743Fa; // Score 0.8 - regular user
    address public user3 = 0xFCF07cf03599cBBAfB90ee179fc6F5b198B67474; // Score 1.8 - verified user
    address public user4 = makeAddr("user4"); // Will be used for mocking tests if needed

    uint256 sepoliaFork;
    string sepolia_url = vm.rpcUrl("sepolia");

    // OP Testnet passport scorer
    address constant PASSPORT_SCORER =
        0xe53C60F8069C2f0c3a84F9B3DB5cf56f3100ba56;

    // Token constants
    uint256 constant TOKENS_REGULAR = 100 ether; // 100 tokens for regular users
    uint256 constant TOKENS_VERIFIED = 1000 ether; // 1000 tokens for verified users

    function setUp() public {
        sepoliaFork = vm.createSelectFork(sepolia_url);

        // Fund test accounts
        vm.deal(admin, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(user4, 100 ether);

        // Deploy contract using real Passport scorer
        vm.prank(admin);
        voting = new QuadraticVotingSystem(PASSPORT_SCORER);
    }

    function testProjectCreation() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );

        (
            string memory name,
            string memory description,
            address votingToken,
            uint256 tokensPerUser,
            uint256 tokensPerVerifiedUser,
            bool isActive,
            uint256 endTime,
            address projectAdmin
        ) = voting.projects(projectId);

        assertEq(name, "Test Project");
        assertEq(description, "Description");
        assertTrue(votingToken != address(0));
        assertEq(tokensPerUser, TOKENS_REGULAR);
        assertEq(tokensPerVerifiedUser, TOKENS_VERIFIED);
        assertTrue(isActive);
        assertGt(endTime, block.timestamp);
        assertEq(projectAdmin, admin);
    }

    function testCantJoinWithLowScore() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );

        // Try to join with user1 (score 0)
        vm.prank(user1);
        vm.expectRevert("Score too low to join");
        voting.joinProject(projectId);
    }

    function testRegularUserJoinAndVote() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );

        // Join with user2 (score 0.8)
        vm.startPrank(user2);
        voting.joinProject(projectId);

        // Verify initial state
        uint256 initialTokens = voting.getUserTokensLeft(projectId, user2);
        (bool isRegistered, bool isVerified) = voting.getUserInfo(user2);
        assertEq(initialTokens, TOKENS_REGULAR);
        assertTrue(isRegistered);
        assertFalse(isVerified);

        // Create and vote in pool
        uint256 poolId = voting.createPool(
            projectId,
            "Test Pool",
            "Description"
        );
        voting.castVote(projectId, poolId, 1);

        // Verify vote
        (uint256 votingPower, uint256 tokensCost, bool voteVerified) = voting
            .getVoteInfo(projectId, poolId, user2);
        assertEq(votingPower, 1);
        assertEq(tokensCost, 1);
        assertFalse(voteVerified);

        // Try to vote with more than 1
        vm.expectRevert("Non-verified users can only cast 1 vote");
        voting.castVote(projectId, poolId, 2);

        vm.stopPrank();
    }

    function testVerifiedUserJoinAndVote() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );

        // Join with user3 (score 1.8)
        vm.startPrank(user3);
        voting.joinProject(projectId);

        // Verify initial state
        uint256 initialTokens = voting.getUserTokensLeft(projectId, user3);
        (bool isRegistered, bool isVerified) = voting.getUserInfo(user3);
        assertEq(initialTokens, TOKENS_VERIFIED);
        assertTrue(isRegistered);
        assertTrue(isVerified);

        // Create and vote in pool with quadratic voting
        uint256 poolId = voting.createPool(
            projectId,
            "Test Pool",
            "Description"
        );
        voting.castVote(projectId, poolId, 4); // Should cost 16 tokens

        // Verify vote
        (uint256 votingPower, uint256 tokensCost, bool voteVerified) = voting
            .getVoteInfo(projectId, poolId, user3);
        assertEq(votingPower, 4);
        assertEq(tokensCost, 16); // 4^2 = 16
        assertTrue(voteVerified);

        // Check remaining tokens
        uint256 remainingTokens = voting.getUserTokensLeft(projectId, user3);
        assertEq(remainingTokens, TOKENS_VERIFIED - 16);

        vm.stopPrank();
    }

    function testUpdateToVerified() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );

        // Start with user2 who has enough score to join (0.8) but not enough to be verified (1.5 needed)
        vm.startPrank(user2);
        voting.joinProject(projectId);

        // Create and vote in pools
        uint256 poolId1 = voting.createPool(projectId, "Pool 1", "Description");
        uint256 poolId2 = voting.createPool(projectId, "Pool 2", "Description");
        voting.castVote(projectId, poolId1, 1);
        voting.castVote(projectId, poolId2, 1);

        // Check initial tokens (should have regular tokens minus votes cast)
        uint256 tokensBeforeUpdate = voting.getUserTokensLeft(projectId, user2);
        assertEq(tokensBeforeUpdate, TOKENS_REGULAR - 2); // Used 2 tokens
        vm.stopPrank();

        // Now use user3 who has high enough score for verification
        vm.startPrank(user3);
        voting.joinProject(projectId);

        // Verify final state
        uint256 tokensAfterJoin = voting.getUserTokensLeft(projectId, user3);
        (bool isRegistered, bool isVerified) = voting.getUserInfo(user3);
        assertEq(tokensAfterJoin, TOKENS_VERIFIED);
        assertTrue(isRegistered);
        assertTrue(isVerified);

        vm.stopPrank();
    }

    function testVoteModificationAndRemoval() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );

        // Use verified user
        vm.startPrank(user3);
        voting.joinProject(projectId);
        uint256 poolId = voting.createPool(
            projectId,
            "Test Pool",
            "Description"
        );

        // Cast initial vote
        voting.castVote(projectId, poolId, 4); // Costs 16 tokens
        uint256 tokensAfterFirstVote = voting.getUserTokensLeft(
            projectId,
            user3
        );

        // Modify vote to smaller amount
        voting.castVote(projectId, poolId, 2); // Costs 4 tokens
        uint256 tokensAfterModification = voting.getUserTokensLeft(
            projectId,
            user3
        );
        assertEq(tokensAfterModification, TOKENS_VERIFIED - 4);

        // Remove vote entirely
        voting.removeVote(projectId, poolId);
        uint256 tokensAfterRemoval = voting.getUserTokensLeft(projectId, user3);
        assertEq(tokensAfterRemoval, TOKENS_VERIFIED);

        vm.stopPrank();
    }

    function testProjectExpiration() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 days
        );

        // Move time forward
        vm.warp(block.timestamp + 2 days);

        vm.prank(user2);
        vm.expectRevert("Project ended");
        voting.joinProject(projectId);
    }

    function testPreventDoubleJoining() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );

        vm.startPrank(user2);
        voting.joinProject(projectId);

        vm.expectRevert("Already joined project");
        voting.joinProject(projectId);
        vm.stopPrank();
    }

    function testOnlyAdminCanCreateProject() public {
        vm.prank(user1);
        vm.expectRevert();
        voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );
    }
}
