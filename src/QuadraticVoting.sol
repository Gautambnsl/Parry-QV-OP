// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./Factory.sol";
import "./ProjectVotingToken.sol";

interface IGitcoinPassport {
    function getScore(address account) external view returns (uint256);
}

contract QuadraticVoting is Ownable {
    struct Poll {
        string name;
        string description;
        address creator;
        bool isActive;
        uint256 totalVotes;
        uint256 totalParticipants;
        mapping(address => Vote) userVotes;
    }

    struct Vote {
        uint256 votingPower;
        bool hasVoted;
        bool isVerified;
        uint256 timestamp;
    }

    struct UserInfo {
        bool isRegistered;
        bool isVerified;
        uint256 tokensLeft;
        uint256[] votedPolls;
        uint256 lastScoreCheck;
    }

    // Project Configuration
    string public name;
    string public description;
    address public immutable votingToken;
    uint256 public immutable tokensPerUser;
    uint256 public immutable tokensPerVerifiedUser;
    uint256 public immutable minScoreToJoin;
    uint256 public immutable minScoreToVerify;
    uint256 public immutable endTime;

    // Constants
    uint256 private constant MAX_VOTING_POWER = 1000;
    uint256 private constant SCORE_CHECK_TIMEOUT = 1 hours;
    uint256 private constant MAX_POLLS_PER_USER = 100;
    uint256 private constant MAX_VOTED_POLLS = 1000;

    // State
    IGitcoinPassport public immutable passportScorer;
    Poll[] public polls;
    mapping(address => UserInfo) public users;
    uint256 public totalParticipants;

    // Events
    event UserJoined(address indexed user, bool isVerified, uint256 tokens);
    event PollCreated(uint256 indexed pollId, string name, address indexed creator);
    event VoteCast(
        address indexed user, 
        uint256 indexed pollId, 
        uint256 votingPower, 
        bool isVerified,
        uint256 cost
    );
    event VoteRemoved(address indexed user, uint256 indexed pollId, uint256 tokensReturned);
    event UserVerificationUpdated(address indexed user, bool isVerified, uint256 additionalTokens);
    event PollStatusChanged(uint256 indexed pollId, bool isActive);

    constructor(
        string memory _name,
        string memory _description,
        uint256 _tokensPerUser,
        uint256 _tokensPerVerifiedUser,
        uint256 _minScoreToJoin,
        uint256 _minScoreToVerify,
        uint256 _endTime,
        address _passportScorer,
        address _admin
    ) Ownable(_admin) {
        require(bytes(_name).length > 0, "Name required");
        require(_tokensPerVerifiedUser > _tokensPerUser, "Invalid token amounts");
        require(_minScoreToJoin > 0, "Min score must be > 0");
        require(_minScoreToVerify > _minScoreToJoin, "Invalid score thresholds");
        require(_endTime > block.timestamp, "Invalid end time");
        require(_passportScorer != address(0), "Invalid passport scorer");
        
        name = _name;
        description = _description;
        tokensPerUser = _tokensPerUser;
        tokensPerVerifiedUser = _tokensPerVerifiedUser;
        minScoreToJoin = _minScoreToJoin;
        minScoreToVerify = _minScoreToVerify;
        endTime = _endTime;
        passportScorer = IGitcoinPassport(_passportScorer);

        string memory tokenName = string(abi.encodePacked("Vote ", _name));
        string memory tokenSymbol = string(abi.encodePacked("v", _name));
        votingToken = address(new ProjectVotingToken(tokenName, tokenSymbol, address(this)));
    }

  

    function joinProject() external  {
        require(!users[msg.sender].isRegistered, "Already joined");
        require(totalParticipants < type(uint256).max - 1, "Too many participants");

        uint256 score = passportScorer.getScore(msg.sender);
        require(score >= minScoreToJoin, "Score too low to join");

        bool isVerified = score >= minScoreToVerify;
        uint256 tokens = isVerified ? tokensPerVerifiedUser : tokensPerUser;

        UserInfo storage user = users[msg.sender];
        user.isRegistered = true;
        user.isVerified = isVerified;
        user.tokensLeft = tokens;
        user.lastScoreCheck = block.timestamp;

        totalParticipants++;
        ProjectVotingToken(votingToken).mint(msg.sender, tokens);
        
        emit UserJoined(msg.sender, isVerified, tokens);
    }

    function createPoll(
        string memory _name,
        string memory _description
    ) external returns (uint256) {
        require(users[msg.sender].isRegistered, "Must join first");
        require(bytes(_name).length > 0, "Name required");
        require(polls.length < type(uint256).max - 1, "Too many polls");
        
        Poll storage newPoll = polls.push();
        newPoll.name = _name;
        newPoll.description = _description;
        newPoll.creator = msg.sender;
        newPoll.isActive = true;
        
        uint256 pollId = polls.length - 1;
        emit PollCreated(pollId, _name, msg.sender);
        return pollId;
    }

    function _checkAndUpdateVerification(UserInfo storage user) internal returns (bool) {
        if (!user.isVerified && 
            block.timestamp >= user.lastScoreCheck + SCORE_CHECK_TIMEOUT) {
            
            uint256 score = passportScorer.getScore(msg.sender);
            user.lastScoreCheck = block.timestamp;
            
            if (score >= minScoreToVerify) {
                user.isVerified = true;
                uint256 additionalTokens = tokensPerVerifiedUser - tokensPerUser;
                user.tokensLeft += additionalTokens;
                ProjectVotingToken(votingToken).mint(msg.sender, additionalTokens);
                emit UserVerificationUpdated(msg.sender, true, additionalTokens);
                return true;
            }
        }
        return false;
    }

    function castVote(
        uint256 pollId, 
        uint256 votingPower
    ) external  {
        require(pollId < polls.length, "Poll does not exist");
        require(votingPower > 0 && votingPower <= MAX_VOTING_POWER, "Invalid voting power");

        UserInfo storage user = users[msg.sender];
        require(user.isRegistered, "Not joined");
        require(user.votedPolls.length < MAX_VOTED_POLLS, "Too many votes");

        // Check for verification upgrade
        _checkAndUpdateVerification(user);

        Poll storage poll = polls[pollId];
        require(poll.isActive, "Poll not active");
        require(poll.creator != msg.sender, "Cannot vote on own poll");

        Vote storage userVote = poll.userVotes[msg.sender];

        // Handle previous vote refund
        if (userVote.hasVoted) {
            uint256 refundAmount = userVote.isVerified ? 
                userVote.votingPower * userVote.votingPower : 1;
                
            user.tokensLeft += refundAmount;
            poll.totalVotes -= userVote.votingPower;
            ProjectVotingToken(votingToken).mint(msg.sender, refundAmount);
        }

        // Calculate new vote cost
        uint256 voteCost;
        if (!user.isVerified) {
            require(votingPower == 1, "Regular users can only cast 1 vote");
            voteCost = 1;
        } else {
            voteCost = votingPower * votingPower;
        }

        require(user.tokensLeft >= voteCost, "Insufficient tokens");

        // Apply vote
        if (!userVote.hasVoted) {
            poll.totalParticipants++;
            user.votedPolls.push(pollId);
        }

        userVote.votingPower = votingPower;
        userVote.hasVoted = true;
        userVote.isVerified = user.isVerified;
        userVote.timestamp = block.timestamp;
        
        user.tokensLeft -= voteCost;
        poll.totalVotes += votingPower;
        
        ProjectVotingToken(votingToken).burn(msg.sender, voteCost);

        emit VoteCast(msg.sender, pollId, votingPower, user.isVerified, voteCost);
    }

    function removeVote(
        uint256 pollId
    ) external {
        require(pollId < polls.length, "Poll does not exist");
        
        UserInfo storage user = users[msg.sender];
        Poll storage poll = polls[pollId];
        Vote storage userVote = poll.userVotes[msg.sender];
        
        require(userVote.hasVoted, "No vote to remove");

        uint256 refundAmount = userVote.isVerified ? 
            userVote.votingPower * userVote.votingPower : 1;

        user.tokensLeft += refundAmount;
        poll.totalVotes -= userVote.votingPower;
        poll.totalParticipants--;
        ProjectVotingToken(votingToken).mint(msg.sender, refundAmount);

        removeFromArray(user.votedPolls, pollId);
        delete poll.userVotes[msg.sender];
        
        emit VoteRemoved(msg.sender, pollId, refundAmount);
    }

    // Admin functions
    function togglePollStatus(uint256 pollId) external onlyOwner {
        require(pollId < polls.length, "Poll does not exist");
        polls[pollId].isActive = !polls[pollId].isActive;
        emit PollStatusChanged(pollId, polls[pollId].isActive);
    }


    // View functions
    function getPollInfo(uint256 pollId) external view returns (
        string memory _name,
        string memory _description,
        address _creator,
        bool _isActive,
        uint256 _totalVotes,
        uint256 _totalParticipants
    ) {
        require(pollId < polls.length, "Poll does not exist");
        Poll storage poll = polls[pollId];
        return (
            poll.name,
            poll.description,
            poll.creator,
            poll.isActive,
            poll.totalVotes,
            poll.totalParticipants
        );
    }

    function getVoteInfo(
        uint256 pollId, 
        address voter
    ) external view returns (
        uint256 votingPower,
        bool hasVoted,
        bool isVerified,
        uint256 timestamp
    ) {
        require(pollId < polls.length, "Poll does not exist");
        Vote storage vote = polls[pollId].userVotes[voter];
        return (
            vote.votingPower,
            vote.hasVoted,
            vote.isVerified,
            vote.timestamp
        );
    }

    function getUserVotedPolls(
        address user
    ) external view returns (uint256[] memory) {
        return users[user].votedPolls;
    }

    function getPollCount() external view returns (uint256) {
        return polls.length;
    }

    // Internal helpers
    function removeFromArray(
        uint256[] storage arr, 
        uint256 value
    ) internal {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == value) {
                arr[i] = arr[arr.length - 1];
                arr.pop();
                break;
            }
        }
    }
}