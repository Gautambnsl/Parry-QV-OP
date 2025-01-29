// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/QuadraticVoting.sol";

contract QuadraticVotingTest is Test {
    QuadraticVotingSystem public voting;

    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1"); // 0 balance
    address public user2 = 0xb974C9Aaf445ba8ABEe973E36781F658c98743Fa; // 0.8 balance
    address public user3 = 0xFCF07cf03599cBBAfB90ee179fc6F5b198B67474; // 1.8 balance

    uint256 sepoliaFork;
    string sepolia_url = vm.rpcUrl("sepolia");

    // OP Testnet addresses
    address constant PASSPORT_SCORER =
        0xe53C60F8069C2f0c3a84F9B3DB5cf56f3100ba56;

    // Token constants
    uint256 constant TOKENS_REGULAR = 100 ether;
    uint256 constant TOKENS_VERIFIED = 1000 ether;

    // Score constants (with 4 decimals)
    uint256 constant SCORE_MIN = 5000; // 0.5000 - Minimum to join
    uint256 constant SCORE_REGULAR = 8000; // 0.8000 - Can join, limited voting
    uint256 constant SCORE_VERIFIED = 15000; // 1.5000 - Full quadratic voting

    function setUp() public {
        sepoliaFork = vm.createSelectFork(sepolia_url);

        // Fund test accounts with ETH
        vm.deal(admin, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);

        // Deploy contract using real Passport scorer
        vm.prank(admin);
        voting = new QuadraticVotingSystem(PASSPORT_SCORER);
    }

    // Helper function to mock passport score (if needed)
    function mockPassportScore(address user, uint256 score) internal {
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

    function testJoinWithLowScore() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );

        // user1 has 0 balance
        vm.prank(user1);
        vm.expectRevert();
        voting.joinProject(projectId);
    }

    function testJoinAsLimitedUser() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );

        // user2 has 0.8 balance
        vm.startPrank(user2);
        voting.joinProject(projectId);

        uint256 tokensLeft = voting.getUserTokensLeft(projectId, user2);
        (bool isRegistered, bool isVerified) = voting.getUserInfo(user2);

        assertEq(tokensLeft, TOKENS_REGULAR);
        assertTrue(isRegistered);
        assertFalse(isVerified);

        uint256 poolId = voting.createPool(
            projectId,
            "Test Pool",
            "Description"
        );

        // Limited user can only cast 1 vote
        voting.castVote(projectId, poolId, 1);

        // Should revert on multiple votes
        vm.expectRevert("Non-verified users can only cast 1 vote");
        voting.castVote(projectId, poolId, 2);
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

        // user3 has 1.8 balance - fully verified
        vm.startPrank(user3);
        voting.joinProject(projectId);

        uint256 tokensLeft = voting.getUserTokensLeft(projectId, user3);
        (bool isRegistered, bool isVerified) = voting.getUserInfo(user3);

        assertEq(tokensLeft, TOKENS_VERIFIED);
        assertTrue(isRegistered);
        assertTrue(isVerified);

        uint256 poolId = voting.createPool(
            projectId,
            "Test Pool",
            "Description"
        );

        // Verified user can cast multiple votes with quadratic cost
        uint256 voteAmount = 4;
        voting.castVote(projectId, poolId, voteAmount);

        (uint256 votingPower, uint256 tokensCost, bool verified) = voting
            .getVoteInfo(projectId, poolId, user3);

        assertEq(votingPower, voteAmount);
        assertEq(tokensCost, voteAmount * voteAmount);
        assertTrue(verified);
        vm.stopPrank();
    }

    function testVoteRemoval() public {
        vm.prank(admin);
        uint256 projectId = voting.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            block.timestamp + 1 weeks
        );

        // user3 (verified user) joins and votes
        vm.startPrank(user3);
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
            user3
        );

        // Modify vote
        uint256 newVotes = 2;
        voting.castVote(projectId, poolId, newVotes);

        // Remove vote completely
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

        // user2 tries to join expired project
        vm.prank(user2);
        vm.expectRevert("Project ended");
        voting.joinProject(projectId);
    }

    function testDuplicateProjectJoin() public {
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

        // Try to join again
        vm.expectRevert("Already joined project");
        voting.joinProject(projectId);
        vm.stopPrank();
    }

    function testNonAdminProjectCreation() public {
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
