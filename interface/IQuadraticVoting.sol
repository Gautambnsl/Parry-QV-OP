interface IQuadraticVoting {
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

    struct PollView {
        string name;
        string description;
        address creator;
        bool isActive;
        uint256 totalVotes;
        uint256 totalParticipants;
    }

    function getProjectInfo() external view returns (ProjectDetails memory);
    function getPollInfo(uint256 pollId) external view returns (PollView memory);
    function createPoll(string calldata name, string calldata description, string calldata ipfsHash) external returns (uint256);
    function getVoteInfo(uint256 pollId, address voter) external view returns (uint256 votingPower, bool hasVoted, bool isVerified, uint256 timestamp);
    function joinProject() external;
    function castVote(uint256 pollId, uint256 votingPower) external;
}
