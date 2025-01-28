// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/QuadraticVoting.sol";

contract QuadraticVotingTest is Test {
    QuadraticVotingSystem public voting;

    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint256 sepoliaFork;
    string sepolia_url = vm.rpcUrl("sepolia");

    // OP Testnet addresses
    address constant PASSPORT_SCORER =
        0xe53C60F8069C2f0c3a84F9B3DB5cf56f3100ba56;

    uint256 constant TOKENS_REGULAR = 100 ether;
    uint256 constant TOKENS_VERIFIED = 1000 ether;

    // Score constants (with 4 decimals)
    uint256 constant SCORE_BELOW_MIN = 4999; // 0.4999 - Can't join
    uint256 constant SCORE_REGULAR = 10000; // 1.0000 - Can join, linear voting
    uint256 constant SCORE_VERIFIED = 15000; // 1.5000 - Can join, quadratic voting

    function setUp() public {
        sepoliaFork = vm.createSelectFork(sepolia_url);

        // Fund test accounts with ETH
        vm.deal(admin, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Deploy contract using real Passport scorer
        vm.prank(admin);
        voting = new QuadraticVotingSystem(PASSPORT_SCORER);
    }

    // Helper to set passport score (through mocking)
    function mockPassportScore(address user, uint256 score) internal {
        // Mock the passport scorer's response
        vm.mockCall(
            PASSPORT_SCORER,
            abi.encodeWithSignature("getScore(address)", user),
            abi.encode(score)
        );
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

    function test_RevertWhen_ScoreBelowMinimum() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );

        mockPassportScore(user1, SCORE_BELOW_MIN);

        vm.prank(user1);
        vm.expectRevert("Score must be at least 2.0000");
        voting.joinProject(projectId);
    }

    function testJoinAsRegularUser() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );

        mockPassportScore(user1, SCORE_REGULAR);

        vm.startPrank(user1);
        voting.joinProject(projectId);

        uint256 tokensLeft = voting.getUserTokensLeft(projectId, user1);
        (bool isRegistered, bool isVerified) = voting.getUserInfo(user1);

        assertEq(tokensLeft, TOKENS_REGULAR);
        assertTrue(isRegistered);
        assertFalse(isVerified);
        vm.stopPrank();
    }

    function testJoinAsVerifiedUser() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );

        mockPassportScore(user1, SCORE_VERIFIED);

        vm.startPrank(user1);
        voting.joinProject(projectId);

        uint256 tokensLeft = voting.getUserTokensLeft(projectId, user1);
        (bool isRegistered, bool isVerified) = voting.getUserInfo(user1);

        assertEq(tokensLeft, TOKENS_VERIFIED);
        assertTrue(isRegistered);
        assertTrue(isVerified);
        vm.stopPrank();
    }

    function testRegularUserVoting() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );

        mockPassportScore(user1, SCORE_REGULAR);

        vm.startPrank(user1);
        voting.joinProject(projectId);

        uint256 poolId = voting.createPool(
            projectId,
            "Test Pool",
            "Description"
        );

        // Try to cast more than 1 vote
        vm.expectRevert("Non-verified users can only cast 1 vote");
        voting.castVote(projectId, poolId, 2);

        // Cast 1 vote successfully
        voting.castVote(projectId, poolId, 1);

        // Verify vote details
        (uint256 votingPower, uint256 tokensCost, bool isVerified) = voting
            .getVoteInfo(projectId, poolId, user1);
        assertEq(votingPower, 1);
        assertEq(tokensCost, 1);
        assertFalse(isVerified);

        vm.stopPrank();
    }

    function testVerifiedUserQuadraticVoting() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );

        mockPassportScore(user1, SCORE_VERIFIED);

        vm.startPrank(user1);
        voting.joinProject(projectId);
        uint256 poolId = voting.createPool(
            projectId,
            "Test Pool",
            "Description"
        );

        uint256 voteAmount = 5;
        voting.castVote(projectId, poolId, voteAmount);

        (uint256 votingPower, uint256 tokensCost, bool isVerified) = voting
            .getVoteInfo(projectId, poolId, user1);
        assertEq(votingPower, voteAmount);
        assertEq(tokensCost, voteAmount * voteAmount);
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

        mockPassportScore(user1, SCORE_VERIFIED);

        vm.startPrank(user1);
        voting.joinProject(projectId);
        uint256 poolId = voting.createPool(
            projectId,
            "Test Pool",
            "Description"
        );

        uint256 initialVotes = 4;
        voting.castVote(projectId, poolId, initialVotes);
        uint256 tokensAfterFirstVote = voting.getUserTokensLeft(
            projectId,
            user1
        );

        uint256 newVotes = 2;
        voting.castVote(projectId, poolId, newVotes);
        uint256 tokensAfterModification = voting.getUserTokensLeft(
            projectId,
            user1
        );
        assertGt(tokensAfterModification, tokensAfterFirstVote);

        voting.removeVote(projectId, poolId);
        uint256 tokensAfterRemoval = voting.getUserTokensLeft(projectId, user1);
        assertEq(tokensAfterRemoval, TOKENS_VERIFIED);

        vm.stopPrank();
    }

    function testMultipleUsersVoting() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );

        mockPassportScore(user1, SCORE_REGULAR); // Regular user
        mockPassportScore(user2, SCORE_VERIFIED); // Verified user

        vm.startPrank(user1);
        voting.joinProject(projectId);
        uint256 poolId = voting.createPool(
            projectId,
            "Test Pool",
            "Description"
        );
        voting.castVote(projectId, poolId, 1); // Can only vote once
        vm.stopPrank();

        vm.startPrank(user2);
        voting.joinProject(projectId);
        voting.castVote(projectId, poolId, 4); // Can vote multiple times
        vm.stopPrank();

        (uint256 votingPower1, uint256 cost1, bool verified1) = voting
            .getVoteInfo(projectId, poolId, user1);
        assertEq(votingPower1, 1);
        assertEq(cost1, 1);
        assertFalse(verified1);

        (uint256 votingPower2, uint256 cost2, bool verified2) = voting
            .getVoteInfo(projectId, poolId, user2);
        assertEq(votingPower2, 4);
        assertEq(cost2, 16); // 4^2 = 16
        assertTrue(verified2);
    }

    function test_RevertWhen_ProjectExpired() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 days
        );

        mockPassportScore(user1, SCORE_REGULAR);

        vm.warp(block.timestamp + 2 days);

        vm.prank(user1);
        vm.expectRevert("Project ended");
        voting.joinProject(projectId);
    }

    function test_RevertWhen_DoubleJoining() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );

        mockPassportScore(user1, SCORE_REGULAR);

        vm.startPrank(user1);
        voting.joinProject(projectId);

        vm.expectRevert("Already joined project");
        voting.joinProject(projectId);
        vm.stopPrank();
    }

    function test_RevertWhen_NonAdminCreatesProject() public {
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
