// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockUSDC is ERC20, Ownable {
    // Decimals for USDC is 6
    uint8 private constant _decimals = 6;

    constructor() ERC20("USD Coin", "USDC") Ownable(msg.sender) {
        // Mint 1 million USDC to deployer (with 6 decimals)
        _mint(msg.sender, 1_000_000 * 10**_decimals);
    }

    function decimals() public pure override returns (uint8) {
        return _decimals;
    }

    // Function to mint tokens for testing
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // Function to let anyone get test tokens
    function faucet() external {
        // Mint 1000 USDC to caller
        _mint(msg.sender, 1_000 * 10**_decimals);
    }

    // Function to let specific amount of test tokens
    function faucetAmount(uint256 amount) external {
        require(amount <= 10_000 * 10**_decimals, "Amount too large");
        _mint(msg.sender, amount);
    }

    // Function to burn tokens
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}