// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

interface IGoatCastLocker {
    struct UserInfo {
        uint256 lockedAmount;
        bool isParticipating;
        uint256 lastDepositTime;
    }

    function lockTokens(uint256 amount) external;

    function unlockTokens() external;

    function useTokensForMarket(
        address user,
        uint256 amount
    ) external returns (bool);

    function getAvailableTokens(address user) external view returns (uint256);

    function getUserInfo(address user) external view returns (UserInfo memory);

    function isParticipating(address user) external view returns (bool);

    function getLockedAmount(address user) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

contract GoatCastLocker is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    IERC20,
    IGoatCastLocker,
    AccessControlEnumerableUpgradeable
{
    IERC20 public token;
    mapping(address => bool) public authorizedMarkets;
    mapping(address => UserInfo) private _userInfo;
    uint256 public totalLockedTokens;

    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    event TokensLocked(address indexed user, uint256 amount);
    event TokensUnlocked(address indexed user, uint256 amount);
    event ParticipationStarted(address indexed user, uint256 amount);
    event ParticipationEnded(address indexed user);
    event TokenAddressUpdated(
        address indexed oldToken,
        address indexed newToken
    );
    event MarketAuthorized(address indexed market);
    event MarketDeauthorized(address indexed market);
    event TokensUsedForMarket(
        address indexed user,
        address indexed market,
        uint256 amount
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _tokenAddress,
        address factoryAddress
    ) external initializer {
        require(_tokenAddress != address(0), "Invalid token address");
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FACTORY_ROLE, factoryAddress);

        token = IERC20(_tokenAddress);
    }

    function lockTokens(uint256 amount) external override nonReentrant {
        require(amount > 0, "Zero amount");

        UserInfo storage user = _userInfo[msg.sender];
        require(
            token.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        user.lockedAmount += amount;
        user.isParticipating = true;
        user.lastDepositTime = block.timestamp;

        totalLockedTokens += amount;

        emit TokensLocked(msg.sender, amount);
        emit ParticipationStarted(msg.sender, amount);
    }

    function unlockTokens() external override nonReentrant {
        UserInfo storage user = _userInfo[msg.sender];
        require(user.isParticipating, "Not participating");
        require(user.lockedAmount > 0, "No tokens locked");

        uint256 amountToUnlock = user.lockedAmount;
        user.lockedAmount = 0;
        user.isParticipating = false;
        totalLockedTokens -= amountToUnlock;

        require(token.transfer(msg.sender, amountToUnlock), "Transfer failed");

        emit TokensUnlocked(msg.sender, amountToUnlock);
        emit ParticipationEnded(msg.sender);
    }

    function partialUnlock(address to, uint256 amount) external nonReentrant {
        UserInfo storage user = _userInfo[msg.sender];
        require(user.isParticipating, "Not participating");
        require(user.lockedAmount >= amount, "Insufficient locked balance");

        user.lockedAmount -= amount;
        totalLockedTokens -= amount;

        // If all tokens are unlocked, set participating to false
        if (user.lockedAmount == 0) {
            user.isParticipating = false;
        }

        require(token.transfer(to, amount), "Transfer failed");

        emit TokensUnlocked(to, amount);
        if (!user.isParticipating) {
            emit ParticipationEnded(msg.sender);
        }
    }

    function useTokensForMarket(
        address user,
        uint256 amount
    ) external override returns (bool) {
        require(authorizedMarkets[msg.sender], "Not authorized");
        require(_userInfo[user].isParticipating, "Not participating");
        require(_userInfo[user].lockedAmount >= amount, "Insufficient balance");

        _userInfo[user].lockedAmount -= amount;
        totalLockedTokens -= amount;

        require(token.transfer(msg.sender, amount), "Transfer failed");
        emit TokensUsedForMarket(user, msg.sender, amount);
        return true;
    }

    function getAvailableTokens(
        address user
    ) external view override returns (uint256) {
        return _userInfo[user].lockedAmount;
    }

    function getUserInfo(
        address user
    ) external view override returns (UserInfo memory) {
        return _userInfo[user];
    }

    function isParticipating(
        address user
    ) external view override returns (bool) {
        return _userInfo[user].isParticipating;
    }

    function getLockedAmount(
        address user
    ) external view override returns (uint256) {
        return _userInfo[user].lockedAmount;
    }

    function balanceOf(
        address account
    ) external view override(IGoatCastLocker, IERC20) returns (uint256) {
        return _userInfo[account].lockedAmount;
    }

    function transfer(
        address to,
        uint256 amount
    ) external override(IGoatCastLocker, IERC20) returns (bool) {
        require(authorizedMarkets[msg.sender], "Not authorized");
        require(amount > 0, "Zero amount");
        require(to != address(0), "Zero address");

        require(token.transfer(to, amount), "Transfer failed");
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external override(IGoatCastLocker, IERC20) returns (bool) {
        require(authorizedMarkets[msg.sender], "Not authorized");
        require(amount > 0, "Zero amount");
        require(from != address(0) && to != address(0), "Zero address");

        require(token.transferFrom(from, to, amount), "Transfer failed");
        return true;
    }

    // Required IERC20 functions
    function totalSupply() external pure override returns (uint256) {
        revert("Not implemented");
    }

    function allowance(
        address owner,
        address spender
    ) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function approve(
        address spender,
        uint256 amount
    ) external pure override returns (bool) {
        revert("Not implemented");
    }

    // Admin functions
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

    function emergencyUnlock(
        address userAddress
    ) external onlyOwner nonReentrant {
        UserInfo storage user = _userInfo[userAddress];
        require(user.isParticipating, "Not participating");
        require(user.lockedAmount > 0, "No tokens locked");

        uint256 amount = user.lockedAmount;
        user.lockedAmount = 0;
        user.isParticipating = false;
        totalLockedTokens -= amount;

        require(token.transfer(userAddress, amount), "Transfer failed");

        emit TokensUnlocked(userAddress, amount);
        emit ParticipationEnded(userAddress);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function version() public pure returns (string memory) {
        return "1.0.0";
    }
}
