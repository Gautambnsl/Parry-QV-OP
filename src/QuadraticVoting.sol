// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

interface IEAS {
    struct AttestationRequestData {
        address recipient;
        uint64 expirationTime;
        bool revocable;
        bytes32 refUID;
        bytes data;
        uint256 value;
    }

    struct AttestationRequest {
        bytes32 schema;
        AttestationRequestData data;
    }

    function attest(AttestationRequest calldata request) external payable returns (bytes32);
}

contract ProjectVotingToken is ERC20 {
    address public projectSystem;
    
    constructor(string memory name, string memory symbol, address _projectSystem) 
        ERC20(name, symbol) 
    {
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
        uint256 tokensPerUser;        // Maximum tokens a user gets when joining
        bytes32 schemaId;
        bool isActive;
        uint256 endTime;
        address admin;
        mapping(bytes32 => address) attestationToUser;
    }

    struct Pool {
        string name;
        string description;
        uint256 projectId;
        address creator;
        bool isActive;
        uint256 totalVotesCast;       // Total number of votes cast (not tokens spent)
        mapping(address => uint256) votes;     // Number of votes cast by user
        mapping(address => bool) hasVoted;
    }

    struct UserInfo {
        bool isRegistered;
        mapping(uint256 => bool) projectJoined;
        mapping(uint256 => uint256) tokensLeft;    // Remaining tokens for voting
        mapping(uint256 => bytes32) projectAttestations;
    }

    IEAS public immutable easContract;
    Project[] public projects;
    mapping(uint256 => Pool[]) public projectPools;
    mapping(address => UserInfo) public users;

    event ProjectCreated(uint256 indexed projectId, string name, address admin, bytes32 schemaId);
    event UserJoinedProject(address indexed user, uint256 indexed projectId, bytes32 attestationId);
    event PoolCreated(uint256 indexed projectId, uint256 indexed poolId, string name, address creator);
    event VoteCast(
        address indexed user, 
        uint256 indexed projectId, 
        uint256 indexed poolId, 
        uint256 numVotes,         // Number of votes cast
        uint256 tokensCost        // Tokens spent (numVotes^2)
    );

    constructor(address _easContract) Ownable(msg.sender) {
        easContract = IEAS(_easContract);
    }

    function createProject(
        string memory name,
        string memory description,
        uint256 tokensPerUser,
        bytes32 schemaId,
        uint256 endTime
    ) external onlyOwner returns (uint256) {
        require(endTime > block.timestamp, "End time must be future");
        
        string memory tokenName = string(abi.encodePacked("Vote ", name));
        string memory tokenSymbol = string(abi.encodePacked("v", name));
        ProjectVotingToken votingToken = new ProjectVotingToken(tokenName, tokenSymbol, address(this));
        
        uint256 projectId = projects.length;
        Project storage newProject = projects.push();
        newProject.name = name;
        newProject.description = description;
        newProject.votingToken = address(votingToken);
        newProject.tokensPerUser = tokensPerUser;
        newProject.schemaId = schemaId;
        newProject.isActive = true;
        newProject.endTime = endTime;
        newProject.admin = msg.sender;
        
        emit ProjectCreated(projectId, name, msg.sender, schemaId);
        return projectId;
    }

    function joinProject(uint256 projectId) external payable {
        require(projectId < projects.length, "Project does not exist");
        Project storage project = projects[projectId];
        
        require(project.isActive, "Project not active");
        require(block.timestamp <= project.endTime, "Project ended");
        
        UserInfo storage user = users[msg.sender];
        require(!user.projectJoined[projectId], "Already joined project");

        bytes memory attestationData = abi.encode(project.name, uint256(1));
        
        IEAS.AttestationRequestData memory requestData = IEAS.AttestationRequestData({
            recipient: msg.sender,
            expirationTime: uint64(project.endTime),
            revocable: true,
            refUID: bytes32(0),
            data: attestationData,
            value: 0
        });

        IEAS.AttestationRequest memory request = IEAS.AttestationRequest({
            schema: project.schemaId,
            data: requestData
        });

        bytes32 attestationId = easContract.attest{value: msg.value}(request);
        
        project.attestationToUser[attestationId] = msg.sender;
        user.projectAttestations[projectId] = attestationId;

        if (!user.isRegistered) {
            user.isRegistered = true;
        }
        
        user.projectJoined[projectId] = true;
        user.tokensLeft[projectId] = project.tokensPerUser;
        
        ProjectVotingToken(project.votingToken).mint(msg.sender, project.tokensPerUser);
        
        emit UserJoinedProject(msg.sender, projectId, attestationId);
    }

    function createPool(
        uint256 projectId,
        string memory name,
        string memory description
    ) external returns (uint256) {
        require(projectId < projects.length, "Project does not exist");
        Project storage project = projects[projectId];
        
        require(users[msg.sender].projectJoined[projectId], "Must join project first");
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
        uint256 numVotes          // Number of votes to cast (will cost numVotes^2 tokens)
    ) external {
        require(projectId < projects.length, "Project does not exist");
        require(poolId < projectPools[projectId].length, "Pool does not exist");
        
        Project storage project = projects[projectId];
        Pool storage pool = projectPools[projectId][poolId];
        
        require(project.isActive && pool.isActive, "Project/pool not active");
        require(block.timestamp <= project.endTime, "Project ended");
        require(!pool.hasVoted[msg.sender], "Already voted in pool");
        
        UserInfo storage user = users[msg.sender];
        require(user.projectJoined[projectId], "Not joined project");
        
        // Calculate quadratic cost
        uint256 tokenCost = numVotes * numVotes;
        require(tokenCost <= user.tokensLeft[projectId], "Insufficient tokens");
        
        pool.votes[msg.sender] = numVotes;          // Store the number of votes cast
        pool.totalVotesCast += numVotes;
        pool.hasVoted[msg.sender] = true;
        user.tokensLeft[projectId] -= tokenCost;    // Deduct the squared token cost
        
        ProjectVotingToken(project.votingToken).burn(msg.sender, tokenCost);
        
        emit VoteCast(msg.sender, projectId, poolId, numVotes, tokenCost);
    }

    function getProject(uint256 projectId) external view returns (
        string memory name,
        string memory description,
        address votingToken,
        uint256 tokensPerUser,
        bytes32 schemaId,
        bool isActive,
        uint256 endTime,
        address admin
    ) {
        require(projectId < projects.length, "Project does not exist");
        Project storage project = projects[projectId];
        return (
            project.name,
            project.description,
            project.votingToken,
            project.tokensPerUser,
            project.schemaId,
            project.isActive,
            project.endTime,
            project.admin
        );
    }

    function getPoolCount(uint256 projectId) external view returns (uint256) {
        return projectPools[projectId].length;
    }

    function getPoolVotes(uint256 projectId, uint256 poolId, address voter) external view returns (uint256) {
        return projectPools[projectId][poolId].votes[voter];
    }

    function getUserTokensLeft(uint256 projectId, address user) external view returns (uint256) {
        return users[user].tokensLeft[projectId];
    }
}