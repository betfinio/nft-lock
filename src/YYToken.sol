// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract YYToken is ERC20 {
    address public lockContract;

    constructor() ERC20("YYToken", "YYT") {}

    function setLockContract(address _lockContract) external {
        require(lockContract == address(0), "Lock contract already set");
        lockContract = _lockContract;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == lockContract, "Only lock contract can mint");
        _mint(to, amount);
    }
}
