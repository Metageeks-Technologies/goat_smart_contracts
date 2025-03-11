// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract GoatCastToken is
    ERC20Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public tokenPrice; // Price in BTC per token (with 18 decimals)

    event TokensPurchased(address indexed buyer, uint256 amount, uint256 price);
    event PriceUpdated(uint256 oldPrice, uint256 newPrice);
    event MarketAuthorized(address indexed market);
    event MarketDeauthorized(address indexed market);
    mapping(address => bool) public authorizedMarkets;

    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        address admin,
        uint256 initialPrice,
        address factoryAddress
    ) public initializer {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(FACTORY_ROLE, factoryAddress);

        tokenPrice = initialPrice;
    }

    function mint(address to, uint256 amount) external payable {
        uint256 totalPrice = (amount * tokenPrice) / (10 ** decimals());
        require(msg.value >= totalPrice, "Insufficient payment");

        _mint(to, amount);
        emit TokensPurchased(to, amount, msg.value);

        if (msg.value > totalPrice) {
            payable(msg.sender).transfer(msg.value - totalPrice);
        }
    }

    function mintByMinter(
        address to,
        uint256 amount
    ) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(
            from == msg.sender || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Not authorized to burn"
        );
        _burn(from, amount);
    }

    function authorizeMarket(address market) external {
        require(
            hasRole(FACTORY_ROLE, msg.sender) || owner() == msg.sender,
            "Not authorized"
        );
        authorizedMarkets[market] = true;
        emit MarketAuthorized(market);
    }

    function deauthorizeMarket(address market) external {
        require(
            hasRole(FACTORY_ROLE, msg.sender) || owner() == msg.sender,
            "Not authorized"
        );
        authorizedMarkets[market] = false;
        emit MarketDeauthorized(market);
    }

    function updatePrice(
        uint256 newPrice
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit PriceUpdated(tokenPrice, newPrice);
        tokenPrice = newPrice;
    }

    function getTokenPrice() external view returns (uint256) {
        return tokenPrice;
    }

    function withdrawFunds(
        address payable recipient,
        uint256 amount
    ) external onlyOwner {
        require(
            amount <= address(this).balance,
            "Insufficient contract balance"
        );
        recipient.transfer(amount);
    }

    function withdrawAllFunds(address payable recipient) external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        recipient.transfer(balance);
    }

    receive() external payable {}

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
