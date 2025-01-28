// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

interface IGitcoinPassport {
    function getScore(address account) external view returns (uint256);
}

contract ProjectVotingToken is ERC20 {
    address public projectSystem;

    constructor(
        string memory name,
        string memory symbol,
        address _projectSystem
    ) ERC20(name, symbol) {
        projectSystem = _projectSystem;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == projectSystem, "Only project system can mint");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == projectSystem, "Only project system can burn");
        _burn(from, amount);
    }
}

contract QuadraticVotingSystem is Ownable {
    struct Project {
        string name;
        string description;
        address votingToken;
        uint256 tokensPerUser; // Tokens for regular users
        uint256 tokensPerVerifiedUser; // Tokens for verified users
        bool isActive;
        uint256 endTime;
        address admin;
    }

    struct Pool {
        string name;
        string description;
        uint256 projectId;
        address creator;
        bool isActive;
        uint256 totalVotes;
        mapping(address => Vote) userVotes;
    }

    struct Vote {
        uint256 votingPower; // Actual voting power (1 for non-verified, quadratic for verified)
        uint256 tokensCost; // Tokens spent
        bool isVerified; // Whether vote was cast as verified user
    }

    struct UserInfo {
        bool isRegistered;
        bool isVerified; // Whether user has high passport score
        mapping(uint256 => bool) projectJoined;
        mapping(uint256 => uint256) tokensLeft;
    }

    IGitcoinPassport public immutable passportScorer;

    // Constants for score thresholds (considering 4 decimals)
    uint256 public constant MIN_SCORE = 5000; // 0.5000
    uint256 public constant VERIFIED_SCORE =  15000; // 1.5000

    Project[] public projects;
    mapping(uint256 => Pool[]) public projectPools;
    mapping(address => UserInfo) public users;

    event ProjectCreated(uint256 indexed projectId, string name, address admin);
    event UserJoinedProject(
        address indexed user,
        uint256 indexed projectId,
        bool isVerified
    );
    event PoolCreated(
        uint256 indexed projectId,
        uint256 indexed poolId,
        string name,
        address creator
    );
    event VoteCast(
        address indexed user,
        uint256 indexed projectId,
        uint256 indexed poolId,
        uint256 votingPower,
        uint256 tokensCost
    );
    event VoteRemoved(
        address indexed user,
        uint256 indexed projectId,
        uint256 indexed poolId,
        uint256 tokensReturned
    );

    constructor(address _passportScorer) Ownable(msg.sender) {
        passportScorer = IGitcoinPassport(_passportScorer);
    }

    function createProject(
        string memory name,
        string memory description,
        uint256 tokensPerUser,
        uint256 tokensPerVerifiedUser,
        uint256 endTime
    ) external onlyOwner returns (uint256) {
        require(endTime > block.timestamp, "End time must be future");

        string memory tokenName = string(abi.encodePacked("Vote ", name));
        string memory tokenSymbol = string(abi.encodePacked("v", name));
        ProjectVotingToken votingToken = new ProjectVotingToken(
            tokenName,
            tokenSymbol,
            address(this)
        );

        uint256 projectId = projects.length;
        Project storage newProject = projects.push();
        newProject.name = name;
        newProject.description = description;
        newProject.votingToken = address(votingToken);
        newProject.tokensPerUser = tokensPerUser;
        newProject.tokensPerVerifiedUser = tokensPerVerifiedUser;
        newProject.isActive = true;
        newProject.endTime = endTime;
        newProject.admin = msg.sender;

        emit ProjectCreated(projectId, name, msg.sender);
        return projectId;
    }

    function joinProject(uint256 projectId) external {
        require(projectId < projects.length, "Project does not exist");
        Project storage project = projects[projectId];

        require(project.isActive, "Project not active");
        require(block.timestamp <= project.endTime, "Project ended");

        UserInfo storage user = users[msg.sender];
        require(!user.projectJoined[projectId], "Already joined project");

        // Check Gitcoin Passport score
        uint256 score = passportScorer.getScore(msg.sender);
        require(score >= MIN_SCORE, "Score must be at least 2.0000");

        // Set verified status if score >= 5.0000
        bool isVerified = score >= VERIFIED_SCORE;
        user.isVerified = isVerified;

        if (!user.isRegistered) {
            user.isRegistered = true;
        }

        // Give appropriate amount of tokens
        uint256 tokens = isVerified
            ? project.tokensPerVerifiedUser
            : project.tokensPerUser;
        user.projectJoined[projectId] = true;
        user.tokensLeft[projectId] = tokens;

        ProjectVotingToken(project.votingToken).mint(msg.sender, tokens);

        emit UserJoinedProject(msg.sender, projectId, isVerified);
    }

    function createPool(
        uint256 projectId,
        string memory name,
        string memory description
    ) external returns (uint256) {
        require(projectId < projects.length, "Project does not exist");
        Project storage project = projects[projectId];

        require(
            users[msg.sender].projectJoined[projectId],
            "Must join project first"
        );
        require(project.isActive, "Project not active");
        require(block.timestamp <= project.endTime, "Project ended");

        Pool storage newPool = projectPools[projectId].push();
        newPool.name = name;
        newPool.description = description;
        newPool.projectId = projectId;
        newPool.creator = msg.sender;
        newPool.isActive = true;

        uint256 poolId = projectPools[projectId].length - 1;
        emit PoolCreated(projectId, poolId, name, msg.sender);
        return poolId;
    }

    function castVote(
        uint256 projectId,
        uint256 poolId,
        uint256 numVotes
    ) external {
        require(projectId < projects.length, "Project does not exist");
        require(poolId < projectPools[projectId].length, "Pool does not exist");
        require(numVotes > 0, "Must vote at least once");

        Project storage project = projects[projectId];
        Pool storage pool = projectPools[projectId][poolId];
        UserInfo storage user = users[msg.sender];

        require(project.isActive && pool.isActive, "Project/pool not active");
        require(block.timestamp <= project.endTime, "Project ended");
        require(user.projectJoined[projectId], "Not joined project");

        // Non-verified users can only cast 1 vote per pool
        if (!user.isVerified) {
            require(numVotes == 1, "Non-verified users can only cast 1 vote");
        }

        // Calculate cost and voting power
        uint256 tokenCost;
        uint256 votingPower;

        if (user.isVerified) {
            tokenCost = numVotes * numVotes; // Quadratic cost
            votingPower = numVotes; // Direct voting power
        } else {
            tokenCost = 1; // Fixed cost for non-verified
            votingPower = 1; // Fixed voting power
        }

        require(tokenCost <= user.tokensLeft[projectId], "Insufficient tokens");

        // If user has voted before, return their tokens first
        if (pool.userVotes[msg.sender].votingPower > 0) {
            user.tokensLeft[projectId] += pool.userVotes[msg.sender].tokensCost;
            ProjectVotingToken(project.votingToken).mint(
                msg.sender,
                pool.userVotes[msg.sender].tokensCost
            );
            pool.totalVotes -= pool.userVotes[msg.sender].votingPower;
        }

        // Update vote
        pool.userVotes[msg.sender] = Vote({
            votingPower: votingPower,
            tokensCost: tokenCost,
            isVerified: user.isVerified
        });

        pool.totalVotes += votingPower;
        user.tokensLeft[projectId] -= tokenCost;

        ProjectVotingToken(project.votingToken).burn(msg.sender, tokenCost);

        emit VoteCast(msg.sender, projectId, poolId, votingPower, tokenCost);
    }

    function removeVote(uint256 projectId, uint256 poolId) external {
        require(projectId < projects.length, "Project does not exist");
        require(poolId < projectPools[projectId].length, "Pool does not exist");

        Project storage project = projects[projectId];
        Pool storage pool = projectPools[projectId][poolId];
        UserInfo storage user = users[msg.sender];

        require(project.isActive, "Project not active");
        require(
            pool.userVotes[msg.sender].votingPower > 0,
            "No vote to remove"
        );

        uint256 tokensToReturn = pool.userVotes[msg.sender].tokensCost;

        // Return tokens
        user.tokensLeft[projectId] += tokensToReturn;
        ProjectVotingToken(project.votingToken).mint(
            msg.sender,
            tokensToReturn
        );

        // Update pool
        pool.totalVotes -= pool.userVotes[msg.sender].votingPower;
        delete pool.userVotes[msg.sender];

        emit VoteRemoved(msg.sender, projectId, poolId, tokensToReturn);
    }

    // View functions
    function getVoteInfo(
        uint256 projectId,
        uint256 poolId,
        address voter
    )
        external
        view
        returns (uint256 votingPower, uint256 tokensCost, bool isVerified)
    {
        Vote memory vote = projectPools[projectId][poolId].userVotes[voter];
        return (vote.votingPower, vote.tokensCost, vote.isVerified);
    }

    function getUserTokensLeft(
        uint256 projectId,
        address user
    ) external view returns (uint256) {
        return users[user].tokensLeft[projectId];
    }

    function getUserInfo(
        address user
    ) external view returns (bool isRegistered, bool isVerified) {
        UserInfo storage userInfo = users[user];
        return (userInfo.isRegistered, userInfo.isVerified);
    }
}
