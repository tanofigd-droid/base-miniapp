// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/logic.sol";

// Simple mock ERC20 to simulate USDC
contract MockUSDC is IERC20 {
    string public name = "Mock USDC";
    string public symbol = "mUSDC";
    uint8 public decimals = 6;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        require(balanceOf[sender] >= amount, "Insufficient balance");
        require(allowance[sender][msg.sender] >= amount, "Not allowed");
        balanceOf[sender] -= amount;
        allowance[sender][msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
}

// Test contract
contract BountyQnATest is Test {
    MockUSDC usdc;
    BountyQnA qna;

    address asker = address(0xA11CE);
    address responder1 = address(0xB0B);
    address responder2 = address(0x123);
    address platform = address(0xD3b);

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockUSDC();

        // Deploy QnA contract (30% fee)
        qna = new BountyQnA(address(usdc), platform, 30);

        // Mint USDC to users
        usdc.mint(asker, 1000e6);      // 1000 USDC
        usdc.mint(responder1, 100e6);  // 100 USDC
        usdc.mint(responder2, 100e6);  // 100 USDC

        // Label addresses for readability in traces
        vm.label(asker, "Asker");
        vm.label(responder1, "Responder1");
        vm.label(responder2, "Responder2");
        vm.label(platform, "Platform");
    }

    function test_FullFlow() public {
        vm.startPrank(asker);

        // Approve QnA contract to take bounty
        usdc.approve(address(qna), 100e6);

        // Post a question
        string[] memory tags = new string[](2);
        tags[0] = "Aerospace";
        tags[1] = "DeFi";
        qna.postQuestion("What is the max altitude for a CubeSat?", tags, 100e6);

        vm.stopPrank();

        // Responder1 posts an answer
        vm.startPrank(responder1);
        qna.postAnswer(1, "Around 600 km in LEO.");
        vm.stopPrank();

        // Responder2 posts another answer
        vm.startPrank(responder2);
        qna.postAnswer(1, "Usually below 700 km, depending on orbit decay rate.");
        vm.stopPrank();

        // Asker accepts responder2’s answer
        vm.startPrank(asker);
        qna.acceptAnswer(1, 2);
        vm.stopPrank();

        // Assert: Question is closed
        (, address askerAddr,,,, bool closed) = qna.questions(1);
        assertTrue(closed, "Question should be closed");
        assertEq(askerAddr, asker, "Asker mismatch");

        // Assert: USDC balances
        // 100e6 bounty -> 70e6 to responder2, 30e6 to platform
        assertEq(usdc.balanceOf(platform), 30e6, "Platform should get 30%");
        assertEq(usdc.balanceOf(responder2), 170e6, "Responder2 should get reward");

        // Assert: Trust score incremented for tags
        uint256 aeroScore = qna.getTrustScore(responder2, "Aerospace");
        uint256 defiScore = qna.getTrustScore(responder2, "DeFi");
        assertEq(aeroScore, 1, "Aerospace score should be +1");
        assertEq(defiScore, 1, "DeFi score should be +1");
    }
}
