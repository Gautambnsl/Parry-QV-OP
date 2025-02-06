// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/access/Ownable.sol";
// import "./QuadraticVoting.sol";
// contract Factory is Ownable {
//     address public immutable passportScorer;
//     address[] public projects;
    
//     event ProjectCreated(
//         address indexed projectAddress, 
//         string name, 
//         address indexed admin,
//         uint256 minScoreToJoin,
//         uint256 minScoreToVerify,
//         string ipfsHash
//     );

//     constructor(address _passportScorer) Ownable(msg.sender) {
//         passportScorer = _passportScorer;
//     }

//     function createProject(
//         string calldata name,
//         string calldata description,
//         string calldata ipfsHash,
//         uint256 tokensPerUser,
//         uint256 tokensPerVerifiedUser,
//         uint256 minScoreToJoin,
//         uint256 minScoreToVerify,
//         uint256 endTime
//     ) external returns (address projectAddress) {
//         if (bytes(name).length == 0) revert("Name required");
//         if (bytes(ipfsHash).length == 0) revert("IPFS hash required");
//         if (tokensPerVerifiedUser <= tokensPerUser) revert("Invalid token amounts");
//         if (minScoreToJoin == 0) revert("Min score must be > 0");
//         if (minScoreToVerify <= minScoreToJoin) revert("Invalid score thresholds");
//         if (endTime <= block.timestamp) revert("Invalid end time");
        
//         projectAddress = address(new QuadraticVoting(
//             name,
//             description,
//             ipfsHash,
//             tokensPerUser,
//             tokensPerVerifiedUser,
//             minScoreToJoin,
//             minScoreToVerify,
//             endTime,
//             passportScorer,
//             msg.sender
//         ));
        
//         projects.push(projectAddress);
        
//         emit ProjectCreated(
//             projectAddress, 
//             name, 
//             msg.sender,
//             minScoreToJoin,
//             minScoreToVerify,
//             ipfsHash
//         );
//     }

//     function getProjects() external view returns (address[] memory) {
//         return projects;
//     }

//     function getProjectCount() external view returns (uint256) {
//         return projects.length;
//     }
// }
