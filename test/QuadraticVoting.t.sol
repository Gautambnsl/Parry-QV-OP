// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/QuadraticVoting.sol";

contract QuadraticVotingTest is Test {
    Factory public factory;
    QuadraticVoting public project;

    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address public user2 = 0xb974C9Aaf445ba8ABEe973E36781F658c98743Fa; // Score: 5160
    address public user3 = 0xFCF07cf03599cBBAfB90ee179fc6F5b198B67474; // Score: 18790
    address public user4 = makeAddr("user4");

    // Constants adjusted for real scores
    uint256 constant TOKENS_REGULAR = 100 ether;
    uint256 constant TOKENS_VERIFIED = 1000 ether;
    uint256 constant MIN_SCORE_JOIN = 1000; // Below user2's score
    uint256 constant MIN_SCORE_VERIFY = 10000; // Between user2 and user3 scores
    string constant TEST_IPFS_HASH = "QmTest...";
    string constant TEST_POLL_IPFS_HASH = "QmPoll...";

    // OP Testnet passport scorer
    address constant PASSPORT_SCORER =
        0xe53C60F8069C2f0c3a84F9B3DB5cf56f3100ba56;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("optimism_sepolia"));

        // Fund accounts
        vm.deal(admin, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(user4, 100 ether);

        // Use user3 (high score) as admin
        vm.prank(user3);
        factory = new Factory(PASSPORT_SCORER);

        // Create a test project
        vm.prank(user3);
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
        project = QuadraticVoting(projectAddr);

        // Setup initial user and poll
        vm.startPrank(user3);
        project.joinProject();
        project.createPoll("Initial Poll", "Description", TEST_POLL_IPFS_HASH);
        vm.stopPrank();
    }

    function testFactoryInitialization() public {
        assertEq(factory.passportScorer(), PASSPORT_SCORER);
        assertEq(factory.owner(), user3);

        address[] memory projects = factory.getProjects();
        assertEq(projects.length, 1);
        assertEq(projects[0], address(project));
    }

    function testProjectCreation() public {
        vm.startPrank(user3);

        string memory name = "New Project";
        uint256 endTime = block.timestamp + 1 weeks;

        address projectAddr = factory.createProject(
            name,
            "Description",
            TEST_IPFS_HASH,
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            MIN_SCORE_JOIN,
            MIN_SCORE_VERIFY,
            endTime
        );

        QuadraticVoting newProject = QuadraticVoting(projectAddr);
        QuadraticVoting.ProjectDetails memory info = newProject
            .getProjectInfo();

        assertEq(info.name, name);
        assertEq(info.ipfsHash, TEST_IPFS_HASH);
        assertEq(info.tokensPerUser, TOKENS_REGULAR);
        assertEq(info.tokensPerVerifiedUser, TOKENS_VERIFIED);
        assertEq(info.minScoreToJoin, MIN_SCORE_JOIN);
        assertEq(info.minScoreToVerify, MIN_SCORE_VERIFY);
        assertEq(info.endTime, endTime);
        assertEq(info.owner, user3);

        vm.stopPrank();
    }

    function testInvalidProjectCreation() public {
        vm.startPrank(user3);

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
            block.timestamp + 1 weeks
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
            block.timestamp + 1 weeks
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
            block.timestamp + 1 weeks
        );

        vm.stopPrank();
    }

    function testVotingMechanics() public {
        // Use user2 to test voting on admin's poll
        vm.startPrank(user2);
        project.joinProject();

        // Test voting
        project.castVote(0, 1);

        // Verify vote
        (uint256 votingPower, bool hasVoted, bool isVerified, ) = project
            .getVoteInfo(0, user2);
        assertEq(votingPower, 1);
        assertTrue(hasVoted);
        assertFalse(isVerified);

        // Test vote removal via 0 vote
        project.castVote(0, 0);

        // Verify vote removed
        (votingPower, hasVoted, , ) = project.getVoteInfo(0, user2);
        assertEq(votingPower, 0);
        assertFalse(hasVoted);

        vm.stopPrank();
    }

    function testVerifiedUserVoting() public {
        // Use user2 to vote on admin's poll
        vm.startPrank(user2);
        project.joinProject();

        // Regular user can only vote with power 1
        project.castVote(0, 1);

        // Verify vote
        (uint256 votingPower, , bool isVerified, ) = project.getVoteInfo(
            0,
            user2
        );
        assertEq(votingPower, 1);
        assertFalse(isVerified);

        // Try voting with higher power
        vm.expectRevert("Regular users can only cast 1 vote");
        project.castVote(0, 2);

        vm.stopPrank();
    }

    function testTokenDepletion() public {
        vm.startPrank(user3);
        address projectAddr = factory.createProject(
            "Token Test Project",
            "Description",
            TEST_IPFS_HASH,
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            MIN_SCORE_JOIN,
            MIN_SCORE_VERIFY,
            block.timestamp + 1 weeks
        );
        QuadraticVoting testProject = QuadraticVoting(projectAddr);
        vm.stopPrank();

        vm.startPrank(user2);
        testProject.joinProject();
        uint256 pollId = testProject.createPoll(
            "Test Poll",
            "Description",
            TEST_POLL_IPFS_HASH
        );
        vm.stopPrank();

        vm.startPrank(user3);
        testProject.joinProject();

        testProject.castVote(pollId, 20); // Costs 400 tokens
        testProject.castVote(pollId, 24); // Replaces previous vote, costs 576 tokens
        testProject.castVote(pollId, 5); // Replaces previous vote, costs 25 tokens



        vm.stopPrank();
    }

    function testUserJoining() public {
        // Create new factory with direct mocked calls
        vm.startPrank(user3);
        address mockScorer = makeAddr("mockScorer");
        Factory testFactory = new Factory(mockScorer);

        address projectAddr = testFactory.createProject(
            "Test Project",
            "Description",
            TEST_IPFS_HASH,
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            MIN_SCORE_JOIN,
            MIN_SCORE_VERIFY,
            block.timestamp + 1 weeks
        );
        QuadraticVoting testProject = QuadraticVoting(projectAddr);
        vm.stopPrank();

        // Test user with insufficient score
        vm.mockCall(
            mockScorer,
            abi.encodeWithSelector(IGitcoinPassport.getScore.selector, user1),
            abi.encode(0)
        );

        vm.prank(user1);
        vm.expectRevert("Score too low to join");
        testProject.joinProject();

        // Test user with sufficient score
        vm.mockCall(
            mockScorer,
            abi.encodeWithSelector(IGitcoinPassport.getScore.selector, user2),
            abi.encode(MIN_SCORE_JOIN + 1)
        );

        vm.startPrank(user2);
        testProject.joinProject();

        // Test double joining
        vm.expectRevert("Already joined");
        testProject.joinProject();
        vm.stopPrank();
    }

    function testProjectExpiration() public {
        // Move time to just before expiration
        vm.warp(block.timestamp + 1 weeks - 1 hours);

        // Can still join and vote
        vm.startPrank(user2);
        project.joinProject();
        project.castVote(0, 1);
        vm.stopPrank();

        // Move time past expiration
        vm.warp(block.timestamp + 2 hours);

        // Cannot join after expiration
        vm.startPrank(user1);
        vm.expectRevert("Project ended");
        project.joinProject();
        vm.stopPrank();
    }
}

contract MockPassportScorer {
    function getScore(address account) external view returns (uint256) {
        return uint256(0);
    }
}
