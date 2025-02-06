// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/QuadraticVoting.sol";

contract QuadraticVotingTest is Test {
    Factory public factory;
    
    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1"); 
    address public user2 = 0xb974C9Aaf445ba8ABEe973E36781F658c98743Fa; 
    address public user3 = 0xFCF07cf03599cBBAfB90ee179fc6F5b198B67474;
    address public user4 = makeAddr("user4");

    uint256 sepoliaFork;
    string sepolia_url = vm.rpcUrl("optimism_sepolia");

    // OP Testnet passport scorer
    address constant PASSPORT_SCORER = 0xe53C60F8069C2f0c3a84F9B3DB5cf56f3100ba56;

    // Mock passport scorer to use in tests
    MockPassportScorer public mockScorer;

    // Constants
    uint256 constant TOKENS_REGULAR = 100 ether;
    uint256 constant TOKENS_VERIFIED = 1000 ether;
    uint256 constant MIN_SCORE_JOIN = 1e15; // 0.001
    uint256 constant MIN_SCORE_VERIFY = 2e15; // 0.002
    string constant TEST_IPFS_HASH = "QmTest...";
    string constant TEST_POLL_IPFS_HASH = "QmPoll...";

    function setUp() public {
        // Deploy mock passport scorer
        mockScorer = new MockPassportScorer();
        
        vm.deal(admin, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(user4, 100 ether);

        // Set mock scores
        mockScorer.setScore(admin, 3e15); // Admin has verified score
        mockScorer.setScore(user1, 1.5e15); // Regular user score
        mockScorer.setScore(user2, 2.5e15); // Verified user score
        mockScorer.setScore(user3, 0.5e15); // Below min score
        mockScorer.setScore(user4, 0); // No score

        vm.prank(admin);
        factory = new Factory(address(mockScorer));
    }

    function testFactoryInitialization() public {
        assertEq(factory.passportScorer(), address(mockScorer));
        assertEq(factory.owner(), admin);
    }

    function testCreateProject() public {
        vm.startPrank(admin);
        
        uint256 endTime = block.timestamp + 1 weeks;
        
        address projectAddr = factory.createProject(
            "Test Project",
            "Test Description",
            TEST_IPFS_HASH,
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            MIN_SCORE_JOIN,
            MIN_SCORE_VERIFY,
            endTime
        );
        
        assertTrue(projectAddr != address(0));
        assertEq(factory.getProjects()[0], projectAddr);
        
        QuadraticVoting project = QuadraticVoting(projectAddr);
        QuadraticVoting.ProjectDetails memory info = project.getProjectInfo();
        
        assertEq(info.name, "Test Project");
        assertEq(info.description, "Test Description");
        assertEq(info.ipfsHash, TEST_IPFS_HASH);
        assertEq(info.tokensPerUser, TOKENS_REGULAR);
        assertEq(info.tokensPerVerifiedUser, TOKENS_VERIFIED);
        assertEq(info.minScoreToJoin, MIN_SCORE_JOIN);
        assertEq(info.minScoreToVerify, MIN_SCORE_VERIFY);
        assertEq(info.endTime, endTime);
        assertEq(info.owner, admin);
        assertEq(info.totalParticipants, 0);
        assertEq(info.totalPolls, 0);
        
        vm.stopPrank();
    }

    function testCreateProjectWithInvalidParams() public {
        vm.startPrank(admin);
        
        uint256 endTime = block.timestamp + 1 weeks;
        
        // Test empty name
        vm.expectRevert("Name required");
        factory.createProject(
            "",
            "Description",
            TEST_IPFS_HASH,
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            MIN_SCORE_JOIN,
            MIN_SCORE_VERIFY,
            endTime
        );
        
        // Test empty IPFS hash
        vm.expectRevert("IPFS hash required");
        factory.createProject(
            "Test Project",
            "Description",
            "",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            MIN_SCORE_JOIN,
            MIN_SCORE_VERIFY,
            endTime
        );
        
        // Test invalid token amounts
        vm.expectRevert("Invalid token amounts");
        factory.createProject(
            "Test Project",
            "Description",
            TEST_IPFS_HASH,
            TOKENS_VERIFIED,
            TOKENS_REGULAR,
            MIN_SCORE_JOIN,
            MIN_SCORE_VERIFY,
            endTime
        );
        
        vm.stopPrank();
    }

    function testPollOperations() public {
        vm.startPrank(admin);
        
        address projectAddr = factory.createProject(
            "Test Project",
            "Description",
            TEST_IPFS_HASH,
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            MIN_SCORE_JOIN,
            MIN_SCORE_VERIFY,
            block.timestamp + 1 weeks
        );
        QuadraticVoting project = QuadraticVoting(projectAddr);
        
        // Join project first
        project.joinProject();
        
        // Create poll
        uint256 pollId = project.createPoll(
            "Test Poll",
            "Description",
            TEST_POLL_IPFS_HASH
        );
        
        // Verify poll creation
        QuadraticVoting.PollView memory pollInfo = project.getPollInfo(pollId);
        assertEq(pollInfo.name, "Test Poll");
        assertEq(pollInfo.description, "Description");
        assertEq(pollInfo.creator, admin);
        assertTrue(pollInfo.isActive);
        
        // Toggle poll status
        project.togglePollStatus(pollId);
        pollInfo = project.getPollInfo(pollId);
        assertFalse(pollInfo.isActive);
        
        vm.stopPrank();
    }

    function testUserJoinAndVoting() public {
        // Create project
        vm.startPrank(admin);
        address projectAddr = factory.createProject(
            "Test Project",
            "Description",
            TEST_IPFS_HASH,
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            MIN_SCORE_JOIN,
            MIN_SCORE_VERIFY,
            block.timestamp + 1 weeks
        );
        QuadraticVoting project = QuadraticVoting(projectAddr);
        
        // Admin joins and creates poll
        project.joinProject();
        uint256 pollId = project.createPoll(
            "Admin Poll",
            "Description",
            TEST_POLL_IPFS_HASH
        );
        vm.stopPrank();

        // Test user1 joining (regular user)
        vm.startPrank(user1);
        project.joinProject();
        
        // Vote on admin's poll
        project.castVote(pollId, 1);
        
        // Verify vote
        (uint256 votingPower, bool hasVoted, bool isVerified,) = project.getVoteInfo(pollId, user1);
        assertTrue(hasVoted);
        assertEq(votingPower, 1);
        assertFalse(isVerified);
        vm.stopPrank();

        // Test user2 joining (verified user)
        vm.startPrank(user2);
        project.joinProject();
        
        // Verified users can cast stronger votes
        project.castVote(pollId, 2);
        
        (votingPower, hasVoted, isVerified,) = project.getVoteInfo(pollId, user2);
        assertTrue(hasVoted);
        assertEq(votingPower, 2);
        assertTrue(isVerified);
        vm.stopPrank();

        // Test user3 (should fail to join due to low score)
        vm.startPrank(user3);
        vm.expectRevert("Score too low to join");
        project.joinProject();
        vm.stopPrank();
    }

    function testProjectInfo() public {
        vm.startPrank(admin);
        
        // Create project
        address projectAddr = factory.createProject(
            "Test Project",
            "Description",
            TEST_IPFS_HASH,
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            MIN_SCORE_JOIN,
            MIN_SCORE_VERIFY,
            block.timestamp + 1 weeks
        );
        
        QuadraticVoting project = QuadraticVoting(projectAddr);
        
        // Admin joins and creates polls
        project.joinProject();
        project.createPoll("Poll 1", "Description 1", TEST_POLL_IPFS_HASH);
        project.createPoll("Poll 2", "Description 2", TEST_POLL_IPFS_HASH);
        
        vm.stopPrank();
        
        // User1 joins (has sufficient score)
        vm.prank(user1);
        project.joinProject();
        
        // User2 joins (has sufficient score)
        vm.prank(user2);
        project.joinProject();
        
        // Verify project info
        QuadraticVoting.ProjectDetails memory info = project.getProjectInfo();
        assertEq(info.totalPolls, 2);
        assertEq(info.totalParticipants, 3); // admin + user1 + user2
    }
}

contract MockPassportScorer {
    mapping(address => uint256) private scores;

    function setScore(address user, uint256 score) external {
        scores[user] = score;
    }

    function getScore(address account) external view returns (uint256) {
        return scores[account];
    }
}