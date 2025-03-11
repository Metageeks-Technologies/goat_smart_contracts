// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./GoatCastMarket.sol";

interface IGoatCastToken {
    function authorizeMarket(address market) external;
    function deauthorizeMarket(address market) external;
}

contract GoatCastFactory is
    AccessControlEnumerableUpgradeable,
    UUPSUpgradeable
{
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");
    bytes32 public constant ROLE_MANAGER = keccak256("ROLE_MANAGER");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant WEATHER_ORACLE_ROLE =
        keccak256("WEATHER_ORACLE_ROLE");

    // State variables
    address public implementation;
    address public goatCastToken;

    mapping(address => bool) public isMarket;
    address[] public allMarkets;

    // address public lockerContract;

    // Events
    event MarketDeployed(address indexed market, string name, address creator);
    event ImplementationUpdated(
        address indexed oldImpl,
        address indexed newImpl
    );
    event MarketRemoved(address indexed market);
    event CreatorAdded(address indexed newCreator, address indexed addedBy);
    event CreatorRemoved(address indexed creator, address indexed removedBy);
    event RoleManagerAdded(address indexed manager, address indexed addedBy);
    event RoleManagerRemoved(
        address indexed manager,
        address indexed removedBy
    );
    event GoatCastTokenUpdated(
        address indexed oldToken,
        address indexed newToken
    );
    event GoatCastTokenLock(
        address indexed oldLocker,
        address indexed newLocker
    );
    event LockerContractSet(
        address indexed oldLocker,
        address indexed newLocker
    );

    address public tokenLock;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _implementation,
        address _goatCastToken
    ) public initializer {
        __AccessControlEnumerable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ROLE_MANAGER, msg.sender);
        _grantRole(CREATOR_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(RESOLVER_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, msg.sender);
        _grantRole(WEATHER_ORACLE_ROLE, msg.sender);

        _setRoleAdmin(CREATOR_ROLE, ROLE_MANAGER);

        require(_implementation != address(0), "Invalid implementation");
        require(_goatCastToken != address(0), "Invalid GoatCast token");

        implementation = _implementation;
        goatCastToken = _goatCastToken;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // Updated deployMarket function with fixes
    function deployMarket(
        string memory name,
        uint256 minBet,
        uint256 maxBet,
        address[] memory operators,
        GoatCastMarket.MarketCategory category
    ) external onlyRole(CREATOR_ROLE) returns (address) {
        require(implementation != address(0), "No implementation");
        require(operators.length > 0, "No operators");
        require(tokenLock != address(0), "Token lock not set");

        bytes32 salt = keccak256(
            abi.encodePacked(name, block.timestamp, msg.sender)
        );
        address payable clone = payable(
            Clones.cloneDeterministic(implementation, salt)
        );

        // Initialize market
        GoatCastMarket(clone).initialize(goatCastToken, tokenLock);

        // Setup roles
        GoatCastMarket(clone).grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        GoatCastMarket(clone).grantRole(ADMIN_ROLE, msg.sender);

        for (uint i = 0; i < operators.length; i++) {
            GoatCastMarket(clone).grantRole(OPERATOR_ROLE, operators[i]);
            GoatCastMarket(clone).grantRole(RESOLVER_ROLE, operators[i]);
            GoatCastMarket(clone).grantRole(ORACLE_ROLE, operators[i]);
        }

        // Create initial market
        GoatCastMarket(clone).createMarket(name, category, minBet, maxBet);

        // Authorize market in both token and locker
        IGoatCastToken(goatCastToken).authorizeMarket(clone);
        IGoatCastLocker(tokenLock).authorizeMarket(clone);

        // Track the market
        isMarket[address(clone)] = true;
        allMarkets.push(address(clone));

        emit MarketDeployed(address(clone), name, msg.sender);
        return address(clone);
    }

    // GoatCastToken management
    function updateGoatCastToken(
        address newToken
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newToken != address(0), "Invalid token address");
        address oldToken = goatCastToken;
        goatCastToken = newToken;
        emit GoatCastTokenUpdated(oldToken, newToken);
    }

    // Role management functions
    function addCreator(address newCreator) external onlyRole(ROLE_MANAGER) {
        require(newCreator != address(0), "Invalid address");
        require(!hasRole(CREATOR_ROLE, newCreator), "Already a creator");

        grantRole(CREATOR_ROLE, newCreator);
        emit CreatorAdded(newCreator, msg.sender);
    }

    function removeCreator(address creator) external onlyRole(ROLE_MANAGER) {
        require(hasRole(CREATOR_ROLE, creator), "Not a creator");
        require(creator != msg.sender, "Cannot remove self");

        revokeRole(CREATOR_ROLE, creator);
        emit CreatorRemoved(creator, msg.sender);
    }

    function addRoleManager(
        address newManager
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newManager != address(0), "Invalid address");
        require(!hasRole(ROLE_MANAGER, newManager), "Already a manager");

        grantRole(ROLE_MANAGER, newManager);
        emit RoleManagerAdded(newManager, msg.sender);
    }

    function removeRoleManager(
        address manager
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(hasRole(ROLE_MANAGER, manager), "Not a manager");
        require(manager != msg.sender, "Cannot remove self");

        revokeRole(ROLE_MANAGER, manager);
        emit RoleManagerRemoved(manager, msg.sender);
    }

    function addMultipleCreators(
        address[] calldata newCreators
    ) external onlyRole(ROLE_MANAGER) {
        for (uint i = 0; i < newCreators.length; i++) {
            require(newCreators[i] != address(0), "Invalid address");
            if (!hasRole(CREATOR_ROLE, newCreators[i])) {
                grantRole(CREATOR_ROLE, newCreators[i]);
                emit CreatorAdded(newCreators[i], msg.sender);
            }
        }
    }

    // Implementation management
    function setImplementation(
        address _newImplementation
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newImplementation != address(0), "Invalid implementation");
        emit ImplementationUpdated(implementation, _newImplementation);
        implementation = _newImplementation;
    }

    // Market management
    function removeMarket(
        address market
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isMarket[market], "Not a valid market");

        isMarket[market] = false;

        for (uint i = 0; i < allMarkets.length; i++) {
            if (allMarkets[i] == market) {
                allMarkets[i] = allMarkets[allMarkets.length - 1];
                allMarkets.pop();
                break;
            }
        }

        emit MarketRemoved(market);
    }

    // Function to set/update locker contract
    function setLockerContract(
        address _lockerContract
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_lockerContract != address(0), "Invalid locker address");
        address oldLocker = tokenLock;
        tokenLock = _lockerContract;
        emit LockerContractSet(oldLocker, _lockerContract);
    }

    // Function to get current locker contract
    function getLockerContract() external view returns (address) {
        return tokenLock;
    }

    // Function to authorize a newly deployed market in the locker
    function authorizeMarketInLocker(
        address market
    ) public onlyRole(ADMIN_ROLE) {
        require(isMarket[market], "Not a valid market");
        IGoatCastLocker(tokenLock).authorizeMarket(market);
    }

    function reauthorizeMarket(address market) external onlyRole(ADMIN_ROLE) {
        require(isMarket[market], "Not a valid market");

        // Reauthorize in both contracts
        IGoatCastToken(goatCastToken).authorizeMarket(market);
        IGoatCastLocker(tokenLock).authorizeMarket(market);
    }

    // View functions
    function getAllMarkets() external view returns (address[] memory) {
        return allMarkets;
    }

    function getMarketCount() external view returns (uint256) {
        return allMarkets.length;
    }

    function getMarketAt(uint256 index) external view returns (address) {
        require(index < allMarkets.length, "Index out of bounds");
        return allMarkets[index];
    }

    function isValidMarket(address market) external view returns (bool) {
        return isMarket[market];
    }

    function isCreator(address account) external view returns (bool) {
        return hasRole(CREATOR_ROLE, account);
    }

    function isRoleManager(address account) external view returns (bool) {
        return hasRole(ROLE_MANAGER, account);
    }

    function getCreatorCount() external view returns (uint256) {
        return getRoleMemberCount(CREATOR_ROLE);
    }

    function getCreatorAt(uint256 index) external view returns (address) {
        return getRoleMember(CREATOR_ROLE, index);
    }

    function predictMarketAddress(
        string memory name
    ) external view returns (address) {
        bytes32 salt = keccak256(
            abi.encodePacked(name, block.timestamp, msg.sender)
        );
        return Clones.predictDeterministicAddress(implementation, salt);
    }
}
