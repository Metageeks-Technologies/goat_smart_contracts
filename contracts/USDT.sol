// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract USDTTokenUpgradeable is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) public initializer {
        __ERC20_init("USD Tether", "USDT");
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        
        // Mint initial supply to owner (1 million USDT)
        _mint(initialOwner, 1_000_000 * (10 ** decimals()));
    }

    function decimals() public pure override returns (uint8) {
        return 6; // USDT uses 6 decimal places
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

