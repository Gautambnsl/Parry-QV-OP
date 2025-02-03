// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./QuadraticVoting.sol";

contract Factory is Ownable {
    address public immutable passportScorer;
    address[] public projects;
    
    event ProjectCreated(
        address indexed projectAddress, 
        string name, 
        address indexed admin,
        uint256 minScoreToJoin,
        uint256 minScoreToVerify
    );

    constructor(address _passportScorer) Ownable(msg.sender) {
        passportScorer = _passportScorer;
    }

    function createProject(
        string memory name,
        string memory description,
        uint256 tokensPerUser,
        uint256 tokensPerVerifiedUser,
        uint256 minScoreToJoin,
        uint256 minScoreToVerify,
        uint256 endTime
    ) external returns (address) {
        require(bytes(name).length > 0, "Name required");
        require(tokensPerVerifiedUser > tokensPerUser, "Invalid token amounts");
        require(minScoreToJoin > 0, "Min score must be > 0");
        require(minScoreToVerify > minScoreToJoin, "Invalid score thresholds");
        require(endTime > block.timestamp, "Invalid end time");
        
        QuadraticVoting newProject = new QuadraticVoting(
            name,
            description,
            tokensPerUser,
            tokensPerVerifiedUser,
            minScoreToJoin,
            minScoreToVerify,
            endTime,
            passportScorer,
            msg.sender
        );
        
        address projectAddress = address(newProject);
        projects.push(projectAddress);
        
        emit ProjectCreated(
            projectAddress, 
            name, 
            msg.sender,
            minScoreToJoin,
            minScoreToVerify
        );
        
        return projectAddress;
    }

    function getProjects() external view returns (address[] memory) {
        return projects;
    }

    function getProjectCount() external view returns (uint256) {
        return projects.length;
    }
}