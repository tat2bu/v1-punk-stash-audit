// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IWETH} from "../../src/interfaces/IWETH.sol";

contract MockWETH9 is IWETH {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    receive() external payable {}

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        uint256 bal = balanceOf[msg.sender];
        require(bal >= amount, "WETH: underflow");
        balanceOf[msg.sender] = bal - amount;
        payable(msg.sender).transfer(amount);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "WETH: allowance");
        allowance[from][msg.sender] = allowed - value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }
}
