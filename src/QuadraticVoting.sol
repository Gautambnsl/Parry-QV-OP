// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";


interface IEAS {
    struct AttestationRequestData {
        address recipient;    // The recipient of the attestation
        uint64 expirationTime;    // The time when the attestation expires (Unix timestamp)
        bool revocable;      // Whether the attestation is revocable
        bytes32 refUID;      // The UID of the related attestation
        bytes data;          // Custom attestation data
        uint256 value;       // An explicit ETH value to send to the resolver
    }

    struct AttestationRequest {
        bytes32 schema;    // The schema UID
        AttestationRequestData data;  // The attestation data
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
        uint256 tokensPerUser;
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
        uint256 totalVotes;
        mapping(address => uint256) votes;
        mapping(address => bool) hasVoted;
    }

    struct UserInfo {
        bool isRegistered;
        mapping(uint256 => bool) projectJoined;
        mapping(uint256 => uint256) votingPowerLeft;
        mapping(uint256 => bytes32) projectAttestations;
    }

    IEAS public immutable easContract;
    Project[] public projects;
    mapping(uint256 => Pool[]) public projectPools;
    mapping(address => UserInfo) public users;

    event ProjectCreated(uint256 indexed projectId, string name, address admin, bytes32 schemaId);
    event UserJoinedProject(address indexed user, uint256 indexed projectId, bytes32 attestationId);
    event PoolCreated(uint256 indexed projectId, uint256 indexed poolId, string name, address creator);
    event VoteCast(address indexed user, uint256 indexed projectId, uint256 indexed poolId, uint256 votingPower, uint256 cost);

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

    function encodeSchemaData(
        string memory projectName, 
        uint256 allowedToJoin
    ) public pure returns (bytes memory) {
        return abi.encode(
            // First parameter: string projectName
            projectName,
            // Second parameter: uint256 allowedToJoin
            allowedToJoin
        );
    }

   function joinProject(uint256 projectId) external payable {
        require(projectId < projects.length, "Project does not exist");
        Project storage project = projects[projectId];
        
        require(project.isActive, "Project not active");
        require(block.timestamp <= project.endTime, "Project ended");
        
        UserInfo storage user = users[msg.sender];
        require(!user.projectJoined[projectId], "Already joined project");

        // Direct encoding
        bytes memory attestationData = abi.encode(
            bytes(project.name),  // encode string as bytes
            uint256(1)           // allowedToJoin
        );

        IEAS.AttestationRequestData memory requestData = IEAS.AttestationRequestData({
            recipient: msg.sender,
            expirationTime: uint64(project.endTime),
            revocable: true,
            refUID: bytes32(0),
            data: attestationData,
            value: msg.value // forward value
        });



        console.log("data is",requestData.data);




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
        user.votingPowerLeft[projectId] = project.tokensPerUser;
        
        ProjectVotingToken(project.votingToken).mint(msg.sender, project.tokensPerUser);
        
        emit UserJoinedProject(msg.sender, projectId, attestationId);
    }


    // Helper function to create tuple for schema data
    function tuple(string memory projectName, uint256 allowedToJoin) internal pure returns (bytes memory) {
        return abi.encodePacked(
            bytes(projectName),
            allowedToJoin
        );
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
        uint256 votingPower
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
        
        uint256 voteCost = Math.sqrt(votingPower);
        require(voteCost <= user.votingPowerLeft[projectId], "Insufficient voting power");
        
        pool.votes[msg.sender] = votingPower;
        pool.totalVotes += votingPower;
        pool.hasVoted[msg.sender] = true;
        user.votingPowerLeft[projectId] -= voteCost;
        
        ProjectVotingToken(project.votingToken).burn(msg.sender, voteCost);
        
        emit VoteCast(msg.sender, projectId, poolId, votingPower, voteCost);
    }

    // View functions
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

    function getUserVotingPower(uint256 projectId, address user) external view returns (uint256) {
        return users[user].votingPowerLeft[projectId];
    }
}