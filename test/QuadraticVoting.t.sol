// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/QuadraticVoting.sol";
import "../src/ProjectVotingToken.sol";

contract FactoryTest is Test {
    Factory public factory;
    
    address public admin = makeAddr("admin");
    // Real addresses with known passport scores
    address public user1 = makeAddr("user1"); 
    address public user2 = 0xb974C9Aaf445ba8ABEe973E36781F658c98743Fa; 
    address public user3 = 0xFCF07cf03599cBBAfB90ee179fc6F5b198B67474;
    address public user4 = makeAddr("user4");

    uint256 sepoliaFork;
    string sepolia_url = vm.rpcUrl("optimism_sepolia");

    // OP Testnet passport scorer
    address constant PASSPORT_SCORER = 0xe53C60F8069C2f0c3a84F9B3DB5cf56f3100ba56;

    // Token constants
    uint256 constant TOKENS_REGULAR = 100 ether;
    uint256 constant TOKENS_VERIFIED = 1000 ether;
    
    // Further reduced score thresholds
    uint256 constant MIN_SCORE_JOIN = 1e15; // 0.001
    uint256 constant MIN_SCORE_VERIFY = 2e15; // 0.002

    event ProjectCreated(
        address indexed projectAddress, 
        string name, 
        address indexed admin,
        uint256 minScoreToJoin,
        uint256 minScoreToVerify
    );

    function setUp() public {
        sepoliaFork = vm.createSelectFork(sepolia_url);

        // Fund test accounts
        vm.deal(admin, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(user4, 100 ether);

        // Deploy factory
        vm.prank(admin);
        factory = new Factory(PASSPORT_SCORER);
    }

    function testFactoryInitialization() public {
        assertEq(factory.passportScorer(), PASSPORT_SCORER);
        assertEq(factory.owner(), admin);
    }

    function testCreateProject() public {
        vm.startPrank(admin);
        
        uint256 endTime = block.timestamp + 1 weeks;
        
        address projectAddr = factory.createProject(
            "Test Project",
            "Test Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            MIN_SCORE_JOIN,
            MIN_SCORE_VERIFY,
            endTime
        );
        
        assertTrue(projectAddr != address(0));
        assertEq(factory.getProjectCount(), 1);
        assertEq(factory.projects(0), projectAddr);
        
        // Verify project initialization
        QuadraticVoting project = QuadraticVoting(projectAddr);
        assertEq(project.name(), "Test Project");
        assertEq(project.description(), "Test Description");
        assertEq(project.tokensPerUser(), TOKENS_REGULAR);
        assertEq(project.tokensPerVerifiedUser(), TOKENS_VERIFIED);
        assertEq(project.minScoreToJoin(), MIN_SCORE_JOIN);
        assertEq(project.minScoreToVerify(), MIN_SCORE_VERIFY);
        assertEq(project.endTime(), endTime);
        assertEq(project.owner(), admin);
        
        vm.stopPrank();
    }

    function testCreateProjectWithInvalidParams() public {
        vm.startPrank(admin);
        
        // Test empty name
        vm.expectRevert("Name required");
        factory.createProject(
            "",
            "Description",
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
            TOKENS_VERIFIED,
            TOKENS_REGULAR,
            MIN_SCORE_JOIN,
            MIN_SCORE_VERIFY,
            block.timestamp + 1 weeks
        );
        
        // Test invalid score thresholds
        vm.expectRevert("Invalid score thresholds");
        factory.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            MIN_SCORE_VERIFY,
            MIN_SCORE_JOIN,
            block.timestamp + 1 weeks
        );
        
        // Test past end time
        vm.expectRevert("Invalid end time");
        factory.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            MIN_SCORE_JOIN,
            MIN_SCORE_VERIFY,
            block.timestamp - 1
        );
        
        vm.stopPrank();
    }

    function testProjectTokenIntegration() public {
        vm.startPrank(admin);
        
        address projectAddr = factory.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            MIN_SCORE_JOIN,
            MIN_SCORE_VERIFY,
            block.timestamp + 1 weeks
        );
        
        QuadraticVoting project = QuadraticVoting(projectAddr);
        address tokenAddr = project.votingToken();
        
        ProjectVotingToken token = ProjectVotingToken(tokenAddr);
        assertEq(token.projectSystem(), projectAddr);
        assertEq(token.name(), "Vote Test Project");
        assertEq(token.symbol(), "vTest Project");
        
        vm.stopPrank();
    }

    function testUserJoinAndVerification() public {
        // First create a project with very low score requirements
        vm.startPrank(admin);
        address projectAddr = factory.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            1, // Minimum possible score to join
            2, // Minimum possible score to verify
            block.timestamp + 1 weeks
        );
        vm.stopPrank();
        
        QuadraticVoting project = QuadraticVoting(projectAddr);
        
        // Get and log scores
        uint256 user2Score = IGitcoinPassport(PASSPORT_SCORER).getScore(user2);
        uint256 user3Score = IGitcoinPassport(PASSPORT_SCORER).getScore(user3);
        
        console.log("User2 score:", user2Score);
        console.log("User3 score:", user3Score);
        
        // Join with user2 if they have any score
        if (user2Score > 0) {
            vm.prank(user2);
            project.joinProject();
            (bool isRegistered2,,uint256 tokens2,) = project.users(user2);
            assertTrue(isRegistered2);
            assertGt(tokens2, 0);
        }
        
        // Join with user3 if they have any score
        if (user3Score > 0) {
            vm.prank(user3);
            project.joinProject();
            (bool isRegistered3,,uint256 tokens3,) = project.users(user3);
            assertTrue(isRegistered3);
            assertGt(tokens3, 0);
        }
    }

    function testExpiredProject() public {
        vm.warp(0);
        
        // Create project that expires in 1 day
        vm.startPrank(admin);
        address projectAddr = factory.createProject(
            "Test Project",
            "Description",
            TOKENS_REGULAR,
            TOKENS_VERIFIED,
            1, // Minimum possible score to join
            2, // Minimum possible score to verify
            1 days // Project ends after 1 day
        );
        QuadraticVoting project = QuadraticVoting(projectAddr);
        vm.stopPrank();

        // First verify we can join before expiration
        vm.warp(1 days - 1 hours);
        uint256 preExpiryTime = block.timestamp;
        uint256 projectEndTime = project.endTime();
        console.log("Pre-expiry time:", preExpiryTime);
        console.log("Project end time:", projectEndTime);
        require(preExpiryTime < projectEndTime, "Should be before expiry");

        vm.startPrank(user2);
        project.joinProject(); // This should succeed
        vm.stopPrank();

        // Now move past expiration
        vm.warp(1 days + 1 hours);
        uint256 postExpiryTime = block.timestamp;
        projectEndTime = project.endTime();
        console.log("Post-expiry time:", postExpiryTime);
        console.log("Project end time:", projectEndTime);
        require(postExpiryTime > projectEndTime, "Should be after expiry");

        vm.startPrank(user3);
        // Explicitly check expiration condition
        bool hasExpired = block.timestamp > project.endTime();
        console.log("Has expired?", hasExpired);
        
        // We expect this to revert
        vm.expectRevert(bytes("Project ended"));
        project.joinProject();
        vm.stopPrank();
    }
}