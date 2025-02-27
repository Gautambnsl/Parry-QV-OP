// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IGitcoinPassport {
    function getScore(address account) external view returns (uint256);
}

contract Factory is Ownable {
    address public immutable passportScorer;
    address[] public projects;
    address public currentSender;
    address public paymaster;


    function getMsgSender() public view returns (address) {
        address value = (
            currentSender != address(0) ? currentSender : msg.sender
        );
        return value;
    }

    event ProjectCreated(
        address indexed projectAddress,
        string name,
        address indexed admin,
        string ipfsHash
    );

    constructor(address _passportScorer,address _paymaster) Ownable(msg.sender) {
        passportScorer = _passportScorer;
        paymaster = _paymaster;
    }

    modifier onlyPaymaster() {
        require(msg.sender == paymaster, "Only paymaster can execute this");
        _;
    }

    function updatePaymaster(address _newPaymaster) external onlyOwner() {
        require(_newPaymaster != address(0), "Invalid new paymaster address");
        paymaster = _newPaymaster;
    }

    function createProject(
        string calldata name,
        string calldata description,
        string calldata ipfsHash,
        uint256 tokensPerUser,
        uint256 tokensPerVerifiedUser,
        uint256 minScoreToJoin,
        uint256 minScoreToVerify,
        uint256 endTime
    ) external returns (address projectAddress) {
        if (bytes(name).length == 0) revert("Name required");
        if (bytes(ipfsHash).length == 0) revert("IPFS hash required");
        if (tokensPerVerifiedUser <= tokensPerUser)
            revert("Invalid token amounts");
        if (endTime <= block.timestamp) revert("Invalid end time");

        projectAddress = address(
            new QuadraticVoting(
                name,
                description,
                ipfsHash,
                tokensPerUser,
                tokensPerVerifiedUser,
                minScoreToJoin,
                minScoreToVerify,
                endTime,
                passportScorer,
                address(this)
            )
        );

        projects.push(projectAddress);
        emit ProjectCreated(projectAddress, name, getMsgSender(), ipfsHash);
    }

    function getProjects() external view returns (address[] memory) {
        return projects;
    }

    function executeMetaTransaction(
        address sender,
        bytes memory txData
    ) public onlyPaymaster {
        require(sender != address(0), "Invalid sender");
        currentSender = sender;

        // Directly pass the entire txData to call
        (bool success, ) = address(this).call(txData);
        require(success, "Transaction execution failed");

        currentSender = address(0);
    }
}

contract QuadraticVoting is Ownable {
    struct PollCore {
        string name;
        string description;
        string ipfsHash; // Added IPFS hash
        address creator;
        bool isActive;
    }

    struct PollView {
        string name;
        string description;
        string ipfsHash; // Added IPFS hash
        address creator;
        bool isActive;
        uint256 totalVotes;
        uint256 totalParticipants;
    }

    struct PollStats {
        uint256 totalVotes;
        uint256 totalParticipants;
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
    struct ProjectConfig {
        string name;
        string description;
        string ipfsHash;
        uint256 tokensPerUser;
        uint256 tokensPerVerifiedUser;
        uint256 minScoreToJoin;
        uint256 minScoreToVerify;
        uint256 endTime;
    }

    ProjectConfig public config;

    // Constants
    uint256 private constant MAX_VOTING_POWER = 1000;
    uint256 private constant SCORE_CHECK_TIMEOUT = 1 hours;
    uint256 private constant MAX_VOTED_POLLS = 1000;

    // State
    IGitcoinPassport public immutable passportScorer;
    mapping(uint256 => PollCore) public pollsCore;
    mapping(uint256 => PollStats) public pollsStats;
    mapping(uint256 => mapping(address => Vote)) public votes;
    mapping(address => UserInfo) public users;
    uint256 public totalParticipants;
    uint256 public pollCount;
    address public currentSender;

    modifier onlyPaymaster() {
        require(msg.sender == Factory(owner()).paymaster(), "Only paymaster can execute this");
        _;
    }


    function getMsgSender() public view returns (address) {
        address value = (
            currentSender != address(0) ? currentSender : msg.sender
        );
        return value;
    }

    event UserJoined(address indexed user, bool isVerified, uint256 tokens);
    event PollCreated(
        uint256 indexed pollId,
        string name,
        address indexed creator,
        string ipfsHash
    );
    event VoteCast(
        address indexed user,
        uint256 indexed pollId,
        uint256 votingPower,
        bool isVerified,
        uint256 cost
    );
    event VoteRemoved(
        address indexed user,
        uint256 indexed pollId,
        uint256 tokensReturned
    );
    event UserVerificationUpdated(
        address indexed user,
        bool isVerified,
        uint256 additionalTokens
    );
    event PollStatusChanged(uint256 indexed pollId, bool isActive);

    constructor(
        string memory _name,
        string memory _description,
        string memory _ipfsHash,
        uint256 _tokensPerUser,
        uint256 _tokensPerVerifiedUser,
        uint256 _minScoreToJoin,
        uint256 _minScoreToVerify,
        uint256 _endTime,
        address _passportScorer,
        address _admin
    ) Ownable(_admin) {
        if (_passportScorer == address(0)) revert("Invalid passport scorer");

        config = ProjectConfig({
            name: _name,
            description: _description,
            ipfsHash: _ipfsHash,
            tokensPerUser: _tokensPerUser,
            tokensPerVerifiedUser: _tokensPerVerifiedUser,
            minScoreToJoin: _minScoreToJoin,
            minScoreToVerify: _minScoreToVerify,
            endTime: _endTime
        });

        passportScorer = IGitcoinPassport(_passportScorer);
    }

    function joinProject() external {
        if (users[getMsgSender()].isRegistered) revert("Already joined");
        if (totalParticipants >= type(uint256).max - 1)
            revert("Too many participants");
        if (block.timestamp > config.endTime) revert("Project ended");

        uint256 score = passportScorer.getScore(getMsgSender());
        if (score < config.minScoreToJoin) revert("Score too low to join");

        bool isVerified = score >= config.minScoreToVerify;
        uint256 tokens = isVerified
            ? config.tokensPerVerifiedUser
            : config.tokensPerUser;

        users[getMsgSender()] = UserInfo({
            isRegistered: true,
            isVerified: isVerified,
            tokensLeft: tokens,
            votedPolls: new uint256[](0),
            lastScoreCheck: block.timestamp
        });

        totalParticipants++;
        emit UserJoined(getMsgSender(), isVerified, tokens);
    }

    function createPoll(
        string calldata _name,
        string calldata _description,
        string calldata _ipfsHash
    ) external returns (uint256 pollId) {
        if (!users[getMsgSender()].isRegistered) revert("Must join first");
        if (bytes(_name).length == 0) revert("Name required");
        if (bytes(_ipfsHash).length == 0) revert("IPFS hash required");

        pollId = pollCount++;

        pollsCore[pollId] = PollCore({
            name: _name,
            description: _description,
            ipfsHash: _ipfsHash, // Store IPFS hash
            creator: getMsgSender(),
            isActive: true
        });

        pollsStats[pollId] = PollStats({totalVotes: 0, totalParticipants: 0});

        emit PollCreated(pollId, _name, getMsgSender(), _ipfsHash);
    }

    function _checkAndUpdateVerification(
        UserInfo storage user
    ) internal returns (bool) {
        if (
            !user.isVerified &&
            block.timestamp >= user.lastScoreCheck + SCORE_CHECK_TIMEOUT
        ) {
            uint256 score = passportScorer.getScore(getMsgSender());
            user.lastScoreCheck = block.timestamp;

            if (score >= config.minScoreToVerify) {
                user.isVerified = true;
                uint256 additionalTokens = config.tokensPerVerifiedUser -
                    config.tokensPerUser;
                user.tokensLeft += additionalTokens;
                emit UserVerificationUpdated(
                    getMsgSender(),
                    true,
                    additionalTokens
                );
                return true;
            }
        }
        return false;
    }

    function castVote(uint256 pollId, uint256 votingPower) external {
        if (pollId >= pollCount) revert("Poll does not exist");
        if (votingPower > MAX_VOTING_POWER) revert("Invalid voting power");

        UserInfo storage user = users[getMsgSender()];
        if (!user.isRegistered) revert("Not joined");
        if (
            user.votedPolls.length >= MAX_VOTED_POLLS &&
            !votes[pollId][getMsgSender()].hasVoted
        ) revert("Too many votes");

        PollCore storage core = pollsCore[pollId];
        if (!core.isActive) revert("Poll not active");

        _checkAndUpdateVerification(user);
        _processVote(pollId, votingPower, user);
    }

    function _processVote(
        uint256 pollId,
        uint256 votingPower,
        UserInfo storage user
    ) internal {
        Vote storage userVote = votes[pollId][getMsgSender()];
        PollStats storage stats = pollsStats[pollId];

        // Handle previous vote refund if exists
        if (userVote.hasVoted) {
            uint256 refundAmount = userVote.isVerified
                ? userVote.votingPower * userVote.votingPower
                : 1;

            user.tokensLeft += refundAmount;
            stats.totalVotes -= userVote.votingPower;

            if (votingPower == 0) {
                // If setting to 0, remove from voted polls array and delete vote
                if (stats.totalParticipants > 0) {
                    stats.totalParticipants--;
                }
                removeFromArray(user.votedPolls, pollId);
                delete votes[pollId][getMsgSender()];
                emit VoteCast(getMsgSender(), pollId, 0, user.isVerified, 0);
                return;
            }
        }

        // Calculate new vote cost (only if not removing vote)
        uint256 voteCost;
        if (!user.isVerified) {
            if (votingPower != 1) revert("Regular users can only cast 1 vote");
            voteCost = 1;
        } else {
            voteCost = votingPower * votingPower;
        }

        if (user.tokensLeft < voteCost) revert("Insufficient tokens");

        // Apply new vote
        if (!userVote.hasVoted) {
            stats.totalParticipants++;
            user.votedPolls.push(pollId);
        }

        userVote.votingPower = votingPower;
        userVote.hasVoted = true;
        userVote.isVerified = user.isVerified;
        userVote.timestamp = block.timestamp;

        user.tokensLeft -= voteCost;
        stats.totalVotes += votingPower;

        emit VoteCast(
            getMsgSender(),
            pollId,
            votingPower,
            user.isVerified,
            voteCost
        );
    }

    function togglePollStatus(uint256 pollId) external onlyOwner {
        if (pollId >= pollCount) revert("Poll does not exist");
        pollsCore[pollId].isActive = !pollsCore[pollId].isActive;
        emit PollStatusChanged(pollId, pollsCore[pollId].isActive);
    }

    function removeFromArray(uint256[] storage arr, uint256 value) internal {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == value) {
                arr[i] = arr[arr.length - 1];
                arr.pop();
                break;
            }
        }
    }

    function getPollInfo(
        uint256 pollId
    ) external view returns (PollView memory) {
        if (pollId >= pollCount) revert("Poll does not exist");

        PollCore storage core = pollsCore[pollId];
        PollStats storage stats = pollsStats[pollId];

        return
            PollView({
                name: core.name,
                description: core.description,
                ipfsHash: core.ipfsHash, // Include IPFS hash
                creator: core.creator,
                isActive: core.isActive,
                totalVotes: stats.totalVotes,
                totalParticipants: stats.totalParticipants
            });
    }

    function getUserVotedPolls(
        address user
    ) external view returns (uint256[] memory) {
        return users[user].votedPolls;
    }

    function getVoteInfo(
        uint256 pollId,
        address voter
    )
        external
        view
        returns (
            uint256 votingPower,
            bool hasVoted,
            bool isVerified,
            uint256 timestamp
        )
    {
        if (pollId >= pollCount) revert("Poll does not exist");
        Vote storage vote = votes[pollId][voter];
        return (
            vote.votingPower,
            vote.hasVoted,
            vote.isVerified,
            vote.timestamp
        );
    }

    function getAllPolls() external view returns (PollView[] memory) {
        PollView[] memory allPolls = new PollView[](pollCount);

        for (uint256 i = 0; i < pollCount; i++) {
            PollCore storage core = pollsCore[i];
            PollStats storage stats = pollsStats[i];

            allPolls[i] = PollView({
                name: core.name,
                description: core.description,
                ipfsHash: core.ipfsHash,
                creator: core.creator,
                isActive: core.isActive,
                totalVotes: stats.totalVotes,
                totalParticipants: stats.totalParticipants
            });
        }

        return allPolls;
    }

    struct UserInfoView {
        bool isRegistered;
        bool isVerified;
        uint256 tokensLeft;
        uint256 lastScoreCheck;
        uint256 passportScore;
        uint256 totalVotesCast;
    }
    // Add these two new functions to the QuadraticVoting contract
    function getUserInfo(
        address user
    ) external view returns (UserInfoView memory) {
        UserInfo storage userInfo = users[user];
        uint256 passportScore = passportScorer.getScore(user);

        // Count total votes cast by the user
        uint256 totalVotesCast = 0;
        for (uint256 i = 0; i < userInfo.votedPolls.length; i++) {
            uint256 pollId = userInfo.votedPolls[i];
            if (votes[pollId][user].hasVoted) {
                totalVotesCast += votes[pollId][user].votingPower;
            }
        }

        return
            UserInfoView({
                isRegistered: userInfo.isRegistered,
                isVerified: userInfo.isVerified,
                tokensLeft: userInfo.tokensLeft,
                lastScoreCheck: userInfo.lastScoreCheck,
                passportScore: passportScore,
                totalVotesCast: totalVotesCast
            });
    }

    function getPassportScore(address user) external view returns (uint256) {
        return passportScorer.getScore(user);
    }

    struct ProjectDetails {
        string name;
        string description;
        string ipfsHash;
        uint256 tokensPerUser;
        uint256 tokensPerVerifiedUser;
        uint256 minScoreToJoin;
        uint256 minScoreToVerify;
        uint256 endTime;
        address owner;
        uint256 totalParticipants;
        uint256 totalPolls;
    }

    function getProjectInfo() external view returns (ProjectDetails memory) {
        return
            ProjectDetails({
                name: config.name,
                description: config.description,
                ipfsHash: config.ipfsHash,
                tokensPerUser: config.tokensPerUser,
                tokensPerVerifiedUser: config.tokensPerVerifiedUser,
                minScoreToJoin: config.minScoreToJoin,
                minScoreToVerify: config.minScoreToVerify,
                endTime: config.endTime,
                owner: owner(),
                totalParticipants: totalParticipants,
                totalPolls: pollCount
            });
    }

    function executeMetaTransaction(
        address sender,
        bytes memory txData
    ) public onlyPaymaster {
        require(sender != address(0), "Invalid sender");
        currentSender = sender;

        // Directly pass the entire txData to call
        (bool success, ) = address(this).call(txData);
        require(success, "Transaction execution failed");

        currentSender = address(0);
    }
}


//test
