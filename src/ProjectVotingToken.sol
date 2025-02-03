// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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