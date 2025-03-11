// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "./interface/OracleInterface.sol";
import {IGoatCastLocker} from "./interface/IGoatCastLocker.sol";

contract GoatCastMarket is
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // Enhanced Market Categories
    enum MarketCategory {
        CRYPTO,
        SPORTS,
        POLITICS,
        WEATHER,
        ENTERTAINMENT,
        OTHER
    }

    // New Prediction Type Enums
    enum CryptoPredictionType {
        PRICE_ABOVE,
        PRICE_BELOW,
        PRICE_RANGE,
        PERCENTAGE_CHANGE
    }

    enum SportsPredictionType {
        WINNER,
        SCORE_RANGE,
        OVER_UNDER,
        MARGIN_RANGE,
        PLAYER_STATS
    }

    enum PoliticsPredictionType {
        WINNER,
        VOTE_PERCENTAGE,
        SEAT_COUNT,
        TURNOUT_RANGE,
        MARGIN_VICTORY
    }

    enum WeatherPredictionType {
        TEMPERATURE_RANGE,
        RAINFALL_AMOUNT,
        EXTREME_EVENT,
        WIND_SPEED,
        HUMIDITY_RANGE
    }

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant WEATHER_ORACLE_ROLE =
        keccak256("WEATHER_ORACLE_ROLE");

    // Payment token
    IGoatCastLocker public tokenLock;

    // Constants
    uint256 public constant SHARE_PRICE_DECIMALS = 18;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant PROTOCOL_FEE = 50; // 0.5%

    // Enhanced Share Position Tracking
    struct SharePosition {
        uint256 yesShares; // Number of YES shares held
        uint256 noShares; // Number of NO shares held
        uint256 avgYesPrice; // Average purchase price of YES shares
        uint256 avgNoPrice; // Average purchase price of NO shares
    }

    // Share Management for Events
    struct EventShares {
        uint256 totalYesShares; // Total YES shares created
        uint256 totalNoShares; // Total NO shares created
        uint256 availableYesShares; // Available YES shares for purchase
        uint256 availableNoShares; // Available NO shares for purchase
        uint256 yesSharePrice; // Current YES share price
        uint256 noSharePrice; // Current NO share price
        uint256 initialSharePrice; // Initial price per share
        mapping(address => SharePosition) userPositions;
    }

    // Category-Specific Event Structs
    struct SportsEvent {
        string homeTeam;
        string awayTeam;
        SportsPredictionType predictionType;
        uint256 line; // Spread/total line
        uint256 homeScore;
        uint256 awayScore;
        bool scoreSubmitted;
    }

    struct PoliticalEvent {
        string election;
        string[] candidates;
        mapping(string => uint256) voteResults;
        PoliticsPredictionType predictionType;
        uint256 totalVotes;
        uint256 targetValue; // Target for percentage/seat predictions
        bool resultsSubmitted;
    }

    struct WeatherEvent {
        string location;
        string weatherDataFeed;
        WeatherPredictionType predictionType;
        int256 targetValue;
        int256 tolerance;
        int256 actualValue;
        bool dataSubmitted;
        address weatherOracle;
    }

    struct CryptoAsset {
        address priceFeed;
        uint8 decimals;
        bool isSupported;
        string symbol;
    }

    // Event Struct
    struct Event {
        string name;
        MarketCategory category;
        bytes32 eventData; // Encoded event-specific data
        EventShares shares; // Share management
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        bool isResolved;
        string winner; // "YES" or "NO"
        uint256 protocolFee; // Fee taken on trades (basis points)
    }

    // Market Struct
    struct Market {
        string name;
        MarketCategory category;
        bool isActive;
        mapping(uint256 => Event) events;
        uint256 eventCount;
        uint256 minBetAmount;
        uint256 maxBetAmount;
        uint256 totalValueLocked;
        bool isPaused;
    }

    // State Variables
    mapping(uint256 => Market) public markets;
    uint256 public marketCount;

    // Category-Specific Mappings
    mapping(uint256 => mapping(string => CryptoAsset)) public cryptoAssets;
    mapping(uint256 => mapping(uint256 => SportsEvent)) public sportsEvents;
    mapping(uint256 => mapping(uint256 => PoliticalEvent))
        public politicalEvents;
    mapping(uint256 => mapping(uint256 => WeatherEvent)) public weatherEvents;

    // Volume tracking and pricing parameters
    mapping(uint256 => mapping(uint256 => uint256)) public eventVolumes; // marketId => eventId => volume
    uint256 public constant CURVE_START_THRESHOLD = 1000; // 1000 tokens
    uint256 public constant INITIAL_SCALE = 100; // 1x
    uint256 public constant STANDARD_SCALE = 100; // 1x

    // Events
    event MarketCreated(
        uint256 indexed marketId,
        string name,
        MarketCategory category
    );
    event EventCreated(
        uint256 indexed marketId,
        uint256 indexed eventId,
        string name,
        uint256 initialSharePrice,
        uint256 yesShares,
        uint256 noShares
    );
    event SharesPurchased(
        uint256 indexed marketId,
        uint256 indexed eventId,
        address user,
        bool isYesShares,
        uint256 shares,
        uint256 cost,
        bool istokenLock
    );
    event SharesSold(
        uint256 indexed marketId,
        uint256 indexed eventId,
        address user,
        bool isYesShares,
        uint256 shares,
        uint256 received,
        bool istokenLock
    );
    event EventResolved(
        uint256 indexed marketId,
        uint256 indexed eventId,
        string winner
    );
    event WinningsClaimed(
        uint256 indexed marketId,
        uint256 indexed eventId,
        address user,
        uint256 amount,
        bool istokenLock
    );
    event MarketPaused(uint256 indexed marketId);
    event MarketUnpaused(uint256 indexed marketId);

    // Category-Specific Events
    event CryptoAssetAdded(
        uint256 indexed marketId,
        string symbol,
        address priceFeed
    );
    event SportsEventCreated(
        uint256 indexed marketId,
        uint256 indexed eventId,
        string homeTeam,
        string awayTeam,
        SportsPredictionType predictionType
    );
    event PoliticalEventCreated(
        uint256 indexed marketId,
        uint256 indexed eventId,
        string election,
        PoliticsPredictionType predictionType
    );
    event WeatherEventCreated(
        uint256 indexed marketId,
        uint256 indexed eventId,
        string location,
        WeatherPredictionType predictionType,
        int256 targetValue
    );

    event EmergencyEventResolved(
        uint256 indexed marketId,
        uint256 indexed eventId,
        string reason
    );
    event EmergencyWithdrawal(
        uint256 indexed marketId,
        uint256 indexed eventId,
        address token,
        address user
    );
    event OracleAdded(address indexed oracle);
    event OracleRemoved(address indexed oracle);
    event WeatherOracleAdded(address indexed oracle);
    event WeatherDataSubmitted(
        uint256 indexed marketId,
        uint256 indexed eventId,
        int256 actualValue
    );
    event ScoresSubmitted(
        uint256 indexed marketId,
        uint256 indexed eventId,
        uint256 homeScore,
        uint256 awayScore
    );
    event VoteResultsSubmitted(
        uint256 indexed marketId,
        uint256 indexed eventId,
        uint256 totalVotes
    );

    // Modifiers
    modifier whenMarketNotPaused(uint256 marketId) {
        require(!markets[marketId].isPaused, "Market is paused");
        _;
    }

    modifier eventActive(uint256 marketId, uint256 eventId) {
        require(markets[marketId].events[eventId].isActive, "Event not active");
        require(
            !markets[marketId].events[eventId].isResolved,
            "Event resolved"
        );
        _;
    }

    constructor() {
        _disableInitializers();
    }

    // Initialize function
    function initialize(
        address goatCastToken,
        address _tokenLock
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(RESOLVER_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, msg.sender);
        _grantRole(WEATHER_ORACLE_ROLE, msg.sender);

        tokenLock = IGoatCastLocker(_tokenLock);
    }

    // Market Creation Function
    function createMarket(
        string memory name,
        MarketCategory category,
        uint256 minBet,
        uint256 maxBet
    ) external onlyRole(OPERATOR_ROLE) returns (uint256) {
        require(minBet > 0 && maxBet > minBet, "Invalid bet limits");

        uint256 marketId = marketCount++;
        Market storage market = markets[marketId];
        market.name = name;
        market.category = category;
        market.isActive = true;
        market.minBetAmount = minBet;
        market.maxBetAmount = maxBet;
        market.isPaused = false;

        emit MarketCreated(marketId, name, category);
        return marketId;
    }

    function calculateSharePrice(
        uint256 marketId,
        uint256 eventId,
        bool isYesShares,
        uint256 sharesToTrade
    ) public view returns (uint256) {
        Event storage event_ = markets[marketId].events[eventId];
        EventShares storage shares = event_.shares;

        uint256 availableShares = isYesShares
            ? shares.availableYesShares
            : shares.availableNoShares;
        uint256 totalInitialShares = isYesShares
            ? shares.totalYesShares
            : shares.totalNoShares;

        // If this is the first trade (pool is untouched), use initial price
        if (availableShares == totalInitialShares) {
            return shares.initialSharePrice;
        }

        // For subsequent trades, use constant product formula
        uint256 currentPrice = isYesShares
            ? shares.yesSharePrice
            : shares.noSharePrice;
        uint256 k = currentPrice * availableShares;
        uint256 newShares = availableShares - sharesToTrade;
        return k / newShares;
    }

    // Buying Shares Function
    function buyShares(
        uint256 marketId,
        uint256 eventId,
        bool isYesShares,
        uint256 shares,
        bool useLockedTokens
    )
        external
        payable
        nonReentrant
        whenMarketNotPaused(marketId)
        eventActive(marketId, eventId)
    {
        Market storage market = markets[marketId];
        Event storage event_ = market.events[eventId];
        EventShares storage eventShares = event_.shares;

        // Time window check
        require(
            block.timestamp >= event_.startTime &&
                block.timestamp < event_.endTime,
            "Not in trading window"
        );

        // Share availability check
        uint256 availableShares = isYesShares
            ? eventShares.availableYesShares
            : eventShares.availableNoShares;
        require(
            shares > 0 && shares <= availableShares,
            "Invalid shares amount"
        );

        // Get current price
        uint256 currentPrice = isYesShares
            ? eventShares.yesSharePrice
            : eventShares.noSharePrice;

        // Calculate total price for shares
        uint256 price = currentPrice * shares;
        uint256 protocolFee = (price * event_.protocolFee) / BASIS_POINTS;
        uint256 totalCost = price + protocolFee;

        // Bet limits check
        require(
            totalCost >= market.minBetAmount &&
                totalCost <= market.maxBetAmount,
            "Invalid bet amount"
        );

        // Update volume tracking
        eventVolumes[marketId][eventId] += totalCost;

        // Process payment
        if (useLockedTokens) {
            require(
                tokenLock.useTokensForMarket(msg.sender, totalCost),
                "Failed to use locked tokens"
            );
        } else {
            require(msg.value == totalCost, "Incorrect BTC amount");
        }

        // Update user position
        SharePosition storage position = eventShares.userPositions[msg.sender];
        if (isYesShares) {
            // Update YES position
            if (position.yesShares > 0) {
                position.avgYesPrice =
                    ((position.avgYesPrice * position.yesShares) +
                        (currentPrice * shares)) /
                    (position.yesShares + shares);
            } else {
                position.avgYesPrice = currentPrice;
            }
            position.yesShares += shares;
            eventShares.availableYesShares -= shares;
            eventShares.yesSharePrice = calculateSharePrice(
                marketId,
                eventId,
                true,
                1
            );
        } else {
            // Update NO position
            if (position.noShares > 0) {
                position.avgNoPrice =
                    ((position.avgNoPrice * position.noShares) +
                        (currentPrice * shares)) /
                    (position.noShares + shares);
            } else {
                position.avgNoPrice = currentPrice;
            }
            position.noShares += shares;
            eventShares.availableNoShares -= shares;
            eventShares.noSharePrice = calculateSharePrice(
                marketId,
                eventId,
                false,
                1
            );
        }

        // Update market stats
        market.totalValueLocked += totalCost;

        emit SharesPurchased(
            marketId,
            eventId,
            msg.sender,
            isYesShares,
            shares,
            totalCost,
            useLockedTokens
        );
    }

    // Selling Shares Function
    function sellShares(
        uint256 marketId,
        uint256 eventId,
        bool isYesShares,
        uint256 shares,
        bool useLockedTokens
    )
        external
        nonReentrant
        whenMarketNotPaused(marketId)
        eventActive(marketId, eventId)
    {
        Market storage market = markets[marketId];
        Event storage event_ = market.events[eventId];
        EventShares storage eventShares = event_.shares;
        SharePosition storage position = eventShares.userPositions[msg.sender];

        // Check user has enough shares
        uint256 userShares = isYesShares
            ? position.yesShares
            : position.noShares;
        require(userShares >= shares, "Insufficient shares");

        // Get current price and calculate value
        uint256 currentPrice = isYesShares
            ? eventShares.yesSharePrice
            : eventShares.noSharePrice;

        // Calculate share value
        uint256 shareValue = shares * currentPrice;
        uint256 protocolFee = (shareValue * event_.protocolFee) / BASIS_POINTS;
        uint256 payout = shareValue - protocolFee;

        // Update volume tracking
        eventVolumes[marketId][eventId] += shareValue;

        // Update positions
        if (isYesShares) {
            position.yesShares -= shares;
            eventShares.availableYesShares += shares;
            // Update price after selling
            eventShares.yesSharePrice = calculateSharePrice(
                marketId,
                eventId,
                true,
                1
            );
        } else {
            position.noShares -= shares;
            eventShares.availableNoShares += shares;
            // Update price after selling
            eventShares.noSharePrice = calculateSharePrice(
                marketId,
                eventId,
                false,
                1
            );
        }

        // Process payment
        if (useLockedTokens) {
            require(
                tokenLock.transfer(msg.sender, payout),
                "GoatCast transfer failed"
            );
        } else {
            // Handle native BTC
            (bool sent, ) = payable(msg.sender).call{value: payout}("");
            require(sent, "BTC transfer failed");
        }

        // Update market stats
        market.totalValueLocked = market.totalValueLocked > shareValue
            ? market.totalValueLocked - shareValue
            : 0;

        emit SharesSold(
            marketId,
            eventId,
            msg.sender,
            isYesShares,
            shares,
            payout,
            useLockedTokens
        );
    }

    // Crypto Event Creation
    function createCryptoEvent(
        uint256 marketId,
        string memory name,
        string memory baseAsset,
        CryptoPredictionType predictionType,
        uint256 targetPrice,
        uint256 additionalParam,
        uint256 initialShares, // New: number of shares to create
        uint256 initialSharePrice, // New: price per share
        uint256 startTime,
        uint256 endTime
    ) external onlyRole(OPERATOR_ROLE) whenMarketNotPaused(marketId) {
        require(
            markets[marketId].category == MarketCategory.CRYPTO,
            "Not a crypto market"
        );
        require(
            cryptoAssets[marketId][baseAsset].isSupported,
            "Asset not supported"
        );
        require(initialShares > 0, "Invalid share amount");
        require(initialSharePrice > 0, "Invalid share price");
        bytes32 eventData = encodeCryptoEventData(
            baseAsset,
            targetPrice,
            predictionType,
            additionalParam
        );

        Market storage market = markets[marketId];
        uint256 eventId = market.eventCount++;
        Event storage newEvent = market.events[eventId];

        // Initialize event details
        newEvent.name = name;
        newEvent.category = MarketCategory.CRYPTO;
        newEvent.eventData = eventData;
        newEvent.startTime = startTime;
        newEvent.endTime = endTime;
        newEvent.isActive = true;
        newEvent.protocolFee = PROTOCOL_FEE;

        newEvent.shares.totalYesShares = initialShares;
        newEvent.shares.totalNoShares = initialShares;
        newEvent.shares.availableYesShares = initialShares;
        newEvent.shares.availableNoShares = initialShares;
        newEvent.shares.yesSharePrice = initialSharePrice;
        newEvent.shares.noSharePrice = initialSharePrice;
        newEvent.shares.initialSharePrice = initialSharePrice;

        emit EventCreated(
            marketId,
            eventId,
            name,
            initialSharePrice,
            initialShares,
            initialShares
        );
    }

    // Sports Event Creation
    function createSportsEvent(
        uint256 marketId,
        string memory name,
        string memory homeTeam,
        string memory awayTeam,
        SportsPredictionType predictionType,
        uint256 line,
        uint256 initialShares, // New
        uint256 initialSharePrice, // New
        uint256 startTime,
        uint256 endTime
    ) external onlyRole(OPERATOR_ROLE) whenMarketNotPaused(marketId) {
        require(
            markets[marketId].category == MarketCategory.SPORTS,
            "Not a sports market"
        );
        require(initialShares > 0, "Invalid share amount");
        require(initialSharePrice > 0, "Invalid share price");
        Market storage market = markets[marketId];
        uint256 eventId = market.eventCount++;
        Event storage newEvent = market.events[eventId];

        // Initialize event details
        newEvent.name = name;
        newEvent.category = MarketCategory.SPORTS;
        newEvent.startTime = startTime;
        newEvent.endTime = endTime;
        newEvent.isActive = true;
        newEvent.protocolFee = PROTOCOL_FEE;

        // Initialize shares
        newEvent.shares.totalYesShares = initialShares;
        newEvent.shares.totalNoShares = initialShares;
        newEvent.shares.availableYesShares = initialShares;
        newEvent.shares.availableNoShares = initialShares;
        newEvent.shares.yesSharePrice = initialSharePrice;
        newEvent.shares.noSharePrice = initialSharePrice;
        newEvent.shares.initialSharePrice = initialSharePrice;

        // Create Sports Event Details
        sportsEvents[marketId][eventId] = SportsEvent({
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            predictionType: predictionType,
            line: line,
            homeScore: 0,
            awayScore: 0,
            scoreSubmitted: false
        });

        emit SportsEventCreated(
            marketId,
            eventId,
            homeTeam,
            awayTeam,
            predictionType
        );
    }

    // Political Event Creation
    function createPoliticalEvent(
        uint256 marketId,
        string memory name,
        string memory election,
        string[] memory candidates,
        PoliticsPredictionType predictionType,
        uint256 initialShares, // New
        uint256 initialSharePrice, // New
        uint256 startTime,
        uint256 endTime
    ) external onlyRole(OPERATOR_ROLE) whenMarketNotPaused(marketId) {
        require(
            markets[marketId].category == MarketCategory.POLITICS,
            "Not a politics market"
        );
        require(initialShares > 0, "Invalid share amount");
        require(initialSharePrice > 0, "Invalid share price");

        Market storage market = markets[marketId];
        uint256 eventId = market.eventCount++;
        Event storage newEvent = market.events[eventId];

        // Initialize event details
        newEvent.name = name;
        newEvent.category = MarketCategory.POLITICS;
        newEvent.startTime = startTime;
        newEvent.endTime = endTime;
        newEvent.isActive = true;
        newEvent.protocolFee = PROTOCOL_FEE;

        // Initialize shares
        newEvent.shares.totalYesShares = initialShares;
        newEvent.shares.totalNoShares = initialShares;
        newEvent.shares.availableYesShares = initialShares;
        newEvent.shares.availableNoShares = initialShares;
        newEvent.shares.yesSharePrice = initialSharePrice;
        newEvent.shares.noSharePrice = initialSharePrice;
        newEvent.shares.initialSharePrice = initialSharePrice;

        // Create Political Event Details
        PoliticalEvent storage politicalEvent = politicalEvents[marketId][
            eventId
        ];
        politicalEvent.election = election;
        politicalEvent.candidates = candidates;
        politicalEvent.predictionType = predictionType;
        politicalEvent.resultsSubmitted = false;

        emit PoliticalEventCreated(marketId, eventId, election, predictionType);
    }

    // Weather Event Creation
    function createWeatherEvent(
        uint256 marketId,
        string memory name,
        string memory location,
        WeatherPredictionType predictionType,
        int256 targetValue,
        int256 tolerance,
        string memory weatherDataFeed,
        uint256 initialShares, // New
        uint256 initialSharePrice, // New
        uint256 startTime,
        uint256 endTime
    ) external onlyRole(OPERATOR_ROLE) whenMarketNotPaused(marketId) {
        require(
            markets[marketId].category == MarketCategory.WEATHER,
            "Not a weather market"
        );
        require(initialShares > 0, "Invalid share amount");
        require(initialSharePrice > 0, "Invalid share price");

        Market storage market = markets[marketId];
        uint256 eventId = market.eventCount++;
        Event storage newEvent = market.events[eventId];

        // Initialize event details
        newEvent.name = name;
        newEvent.category = MarketCategory.WEATHER;
        newEvent.startTime = startTime;
        newEvent.endTime = endTime;
        newEvent.isActive = true;
        newEvent.protocolFee = PROTOCOL_FEE;

        // Initialize shares
        newEvent.shares.totalYesShares = initialShares;
        newEvent.shares.totalNoShares = initialShares;
        newEvent.shares.availableYesShares = initialShares;
        newEvent.shares.availableNoShares = initialShares;
        newEvent.shares.yesSharePrice = initialSharePrice;
        newEvent.shares.noSharePrice = initialSharePrice;
        newEvent.shares.initialSharePrice = initialSharePrice;

        // Create Weather Event Details
        weatherEvents[marketId][eventId] = WeatherEvent({
            location: location,
            weatherDataFeed: weatherDataFeed,
            predictionType: predictionType,
            targetValue: targetValue,
            tolerance: tolerance,
            actualValue: 0,
            dataSubmitted: false,
            weatherOracle: msg.sender
        });

        emit WeatherEventCreated(
            marketId,
            eventId,
            location,
            predictionType,
            targetValue
        );
    }

    // Add Crypto Asset for Prediction
    function addCryptoAsset(
        uint256 marketId,
        string memory symbol,
        address priceFeed,
        uint8 decimals
    ) external onlyRole(ADMIN_ROLE) {
        require(priceFeed != address(0), "Invalid price feed");
        require(bytes(symbol).length > 0, "Invalid symbol");

        CryptoAsset storage asset = cryptoAssets[marketId][symbol];
        asset.priceFeed = priceFeed;
        asset.decimals = decimals;
        asset.isSupported = true;
        asset.symbol = symbol;

        emit CryptoAssetAdded(marketId, symbol, priceFeed);
    }

    // Submit Sports Scores
    function submitSportsScores(
        uint256 marketId,
        uint256 eventId,
        uint256 homeScore,
        uint256 awayScore
    ) external onlyRole(ORACLE_ROLE) {
        Event storage event_ = markets[marketId].events[eventId];
        require(!event_.isResolved, "Event already resolved");

        SportsEvent storage sportsEvent = sportsEvents[marketId][eventId];
        require(!sportsEvent.scoreSubmitted, "Scores already submitted");

        sportsEvent.homeScore = homeScore;
        sportsEvent.awayScore = awayScore;
        sportsEvent.scoreSubmitted = true;

        emit ScoresSubmitted(marketId, eventId, homeScore, awayScore);
    }

    // Submit Political Results
    function submitPoliticalResults(
        uint256 marketId,
        uint256 eventId,
        string[] memory candidates,
        uint256[] memory votes
    ) external onlyRole(ORACLE_ROLE) {
        Event storage event_ = markets[marketId].events[eventId];
        require(!event_.isResolved, "Event already resolved");

        PoliticalEvent storage politicalEvent = politicalEvents[marketId][
            eventId
        ];
        require(!politicalEvent.resultsSubmitted, "Results already submitted");
        require(candidates.length == votes.length, "Array length mismatch");

        uint256 totalVotes = 0;
        for (uint i = 0; i < candidates.length; i++) {
            politicalEvent.voteResults[candidates[i]] = votes[i];
            totalVotes += votes[i];
        }

        politicalEvent.totalVotes = totalVotes;
        politicalEvent.resultsSubmitted = true;

        emit VoteResultsSubmitted(marketId, eventId, totalVotes);
    }

    // Submit Weather Data
    function submitWeatherData(
        uint256 marketId,
        uint256 eventId,
        int256 actualValue
    ) external {
        Event storage event_ = markets[marketId].events[eventId];
        require(!event_.isResolved, "Event already resolved");

        WeatherEvent storage weatherEvent = weatherEvents[marketId][eventId];
        require(
            msg.sender == weatherEvent.weatherOracle,
            "Not authorized oracle"
        );
        require(!weatherEvent.dataSubmitted, "Data already submitted");

        weatherEvent.actualValue = actualValue;
        weatherEvent.dataSubmitted = true;

        emit WeatherDataSubmitted(marketId, eventId, actualValue);
    }

    // Price Feed Integration
    function normalizePrice(
        uint256 price,
        uint8 decimals
    ) internal pure returns (uint256) {
        if (decimals == 18) {
            return price;
        }
        if (decimals < 18) {
            return price * (10 ** (18 - decimals));
        }
        return price / (10 ** (decimals - 18));
    }

    // Get Current Crypto Price
    function getCurrentCryptoPrice(
        uint256 marketId,
        string memory asset
    ) public view returns (uint256) {
        CryptoAsset storage cryptoAsset = cryptoAssets[marketId][asset];
        require(cryptoAsset.isSupported, "Asset not supported");

        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            cryptoAsset.priceFeed
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");

        return normalizePrice(uint256(price), cryptoAsset.decimals);
    }

    // Crypto Event Data Encoding/Decoding
    function encodeCryptoEventData(
        string memory baseAsset,
        uint256 targetPrice,
        CryptoPredictionType predictionType,
        uint256 additionalParam
    ) internal pure returns (bytes32) {
        require(bytes(baseAsset).length <= 32, "Asset string too long");

        bytes memory assetBytes = new bytes(32);
        bytes memory asset = bytes(baseAsset);
        for (uint i = 0; i < asset.length; i++) {
            assetBytes[i] = asset[i];
        }

        bytes memory combined = abi.encodePacked(
            assetBytes,
            targetPrice,
            uint8(predictionType),
            additionalParam
        );

        return bytes32(uint256(keccak256(combined)));
    }

    function decodeCryptoEventData(
        bytes32 eventData
    )
        internal
        pure
        returns (
            string memory baseAsset,
            uint256 targetPrice,
            CryptoPredictionType predictionType,
            uint256 additionalParam
        )
    {
        bytes memory data = abi.encodePacked(eventData);

        bytes memory assetBytes = new bytes(32);
        for (uint i = 0; i < 32; i++) {
            assetBytes[i] = data[i];
        }

        uint length = 0;
        for (uint i = 0; i < 32; i++) {
            if (assetBytes[i] != 0) {
                length = i + 1;
            }
        }
        bytes memory trimmedAssetBytes = new bytes(length);
        for (uint i = 0; i < length; i++) {
            trimmedAssetBytes[i] = assetBytes[i];
        }
        baseAsset = string(trimmedAssetBytes);

        targetPrice = uint256(bytes32(data));
        predictionType = CryptoPredictionType(uint8(data[64]));
        additionalParam = uint256(bytes32(data));

        return (baseAsset, targetPrice, predictionType, additionalParam);
    }

    // Resolution for Different Event Types
    function resolveCryptoEvent(uint256 marketId, uint256 eventId) internal {
        Event storage event_ = markets[marketId].events[eventId];
        bytes32 eventData = event_.eventData;

        (
            string memory baseAsset,
            uint256 targetPrice,
            CryptoPredictionType predictionType,
            uint256 additionalParam
        ) = decodeCryptoEventData(eventData);

        uint256 finalPrice = getCurrentCryptoPrice(marketId, baseAsset);

        string memory outcome;
        if (predictionType == CryptoPredictionType.PRICE_ABOVE) {
            outcome = finalPrice >= targetPrice ? "YES" : "NO";
        } else if (predictionType == CryptoPredictionType.PRICE_BELOW) {
            outcome = finalPrice < targetPrice ? "YES" : "NO";
        } else if (predictionType == CryptoPredictionType.PRICE_RANGE) {
            outcome = (finalPrice >= targetPrice &&
                finalPrice <= additionalParam)
                ? "YES"
                : "NO";
        } else if (predictionType == CryptoPredictionType.PERCENTAGE_CHANGE) {
            uint256 percentageChange = ((finalPrice - targetPrice) * 100) /
                targetPrice;
            outcome = percentageChange >= additionalParam ? "YES" : "NO";
        }

        event_.winner = outcome;
        event_.isResolved = true;
        event_.isActive = false;
    }

    function resolveSportsEvent(uint256 marketId, uint256 eventId) internal {
        Event storage event_ = markets[marketId].events[eventId];
        SportsEvent storage sportsEvent = sportsEvents[marketId][eventId];

        require(sportsEvent.scoreSubmitted, "Scores not submitted");

        string memory outcome;
        if (sportsEvent.predictionType == SportsPredictionType.WINNER) {
            outcome = sportsEvent.homeScore > sportsEvent.awayScore
                ? "YES"
                : "NO";
        } else if (
            sportsEvent.predictionType == SportsPredictionType.OVER_UNDER
        ) {
            uint256 totalScore = sportsEvent.homeScore + sportsEvent.awayScore;
            outcome = totalScore > sportsEvent.line ? "YES" : "NO";
        }

        event_.winner = outcome;
        event_.isResolved = true;
        event_.isActive = false;
    }

    function resolvePoliticalEvent(uint256 marketId, uint256 eventId) internal {
        Event storage event_ = markets[marketId].events[eventId];
        PoliticalEvent storage politicalEvent = politicalEvents[marketId][
            eventId
        ];

        require(politicalEvent.resultsSubmitted, "Results not submitted");
        string memory outcome;

        if (politicalEvent.predictionType == PoliticsPredictionType.WINNER) {
            uint256 maxVotes = 0;
            string memory winner;
            for (uint i = 0; i < politicalEvent.candidates.length; i++) {
                if (
                    politicalEvent.voteResults[politicalEvent.candidates[i]] >
                    maxVotes
                ) {
                    maxVotes = politicalEvent.voteResults[
                        politicalEvent.candidates[i]
                    ];
                    winner = politicalEvent.candidates[i];
                }
            }
            outcome = keccak256(bytes(winner)) ==
                keccak256(bytes(abi.encodePacked(politicalEvent.candidates[0])))
                ? "YES"
                : "NO";
        } else if (
            politicalEvent.predictionType ==
            PoliticsPredictionType.VOTE_PERCENTAGE
        ) {
            uint256 totalCandidateVotes = 0;
            for (uint i = 0; i < politicalEvent.candidates.length; i++) {
                totalCandidateVotes += politicalEvent.voteResults[
                    politicalEvent.candidates[i]
                ];
            }
            outcome = ((totalCandidateVotes * 100) /
                politicalEvent.totalVotes) >= politicalEvent.targetValue
                ? "YES"
                : "NO";
        }

        event_.winner = outcome;
        event_.isResolved = true;
        event_.isActive = false;
    }

    function resolveWeatherEvent(uint256 marketId, uint256 eventId) internal {
        Event storage event_ = markets[marketId].events[eventId];
        WeatherEvent storage weatherEvent = weatherEvents[marketId][eventId];

        require(weatherEvent.dataSubmitted, "Weather data not submitted");
        string memory outcome;

        if (
            weatherEvent.predictionType ==
            WeatherPredictionType.TEMPERATURE_RANGE
        ) {
            outcome = (weatherEvent.actualValue >=
                (weatherEvent.targetValue - weatherEvent.tolerance) &&
                weatherEvent.actualValue <=
                (weatherEvent.targetValue + weatherEvent.tolerance))
                ? "YES"
                : "NO";
        } else if (
            weatherEvent.predictionType == WeatherPredictionType.RAINFALL_AMOUNT
        ) {
            outcome = weatherEvent.actualValue >= weatherEvent.targetValue
                ? "YES"
                : "NO";
        } else if (
            weatherEvent.predictionType == WeatherPredictionType.EXTREME_EVENT
        ) {
            outcome = weatherEvent.actualValue >= weatherEvent.targetValue
                ? "YES"
                : "NO";
        } else if (
            weatherEvent.predictionType == WeatherPredictionType.WIND_SPEED
        ) {
            outcome = weatherEvent.actualValue >= weatherEvent.targetValue
                ? "YES"
                : "NO";
        } else if (
            weatherEvent.predictionType == WeatherPredictionType.HUMIDITY_RANGE
        ) {
            outcome = (weatherEvent.actualValue >=
                (weatherEvent.targetValue - weatherEvent.tolerance) &&
                weatherEvent.actualValue <=
                (weatherEvent.targetValue + weatherEvent.tolerance))
                ? "YES"
                : "NO";
        }

        event_.winner = outcome;
        event_.isResolved = true;
        event_.isActive = false;
    }

    // Main resolution function that routes to specific resolution methods
    function resolveEvent(
        uint256 marketId,
        uint256 eventId
    ) external onlyRole(RESOLVER_ROLE) {
        Event storage event_ = markets[marketId].events[eventId];

        require(!event_.isResolved, "Already resolved");
        require(block.timestamp > event_.endTime, "Event not ended");

        if (event_.category == MarketCategory.CRYPTO) {
            resolveCryptoEvent(marketId, eventId);
        } else if (event_.category == MarketCategory.SPORTS) {
            resolveSportsEvent(marketId, eventId);
        } else if (event_.category == MarketCategory.POLITICS) {
            resolvePoliticalEvent(marketId, eventId);
        } else if (event_.category == MarketCategory.WEATHER) {
            resolveWeatherEvent(marketId, eventId);
        } else {
            revert("Unsupported event category");
        }

        emit EventResolved(marketId, eventId, event_.winner);
    }

    // Claim Winnings Function
    function claimWinnings(
        uint256 marketId,
        uint256 eventId,
        bool useLockedTokens
    ) external nonReentrant {
        Event storage event_ = markets[marketId].events[eventId];
        require(event_.isResolved, "Event not resolved");

        EventShares storage eventShares = event_.shares;
        SharePosition storage position = eventShares.userPositions[msg.sender];

        bool isYesWinner = keccak256(bytes(event_.winner)) ==
            keccak256(bytes("YES"));
        uint256 winningShares = isYesWinner
            ? position.yesShares
            : position.noShares;

        require(winningShares > 0, "No winning shares");

        uint256 totalWinningShares = isYesWinner
            ? eventShares.totalYesShares
            : eventShares.totalNoShares;
        uint256 totalShareValue = isYesWinner
            ? eventShares.yesSharePrice * eventShares.totalYesShares
            : eventShares.noSharePrice * eventShares.totalNoShares;

        uint256 payout = (totalShareValue * winningShares) / totalWinningShares;

        // Reset position
        if (isYesWinner) {
            position.yesShares = 0;
        } else {
            position.noShares = 0;
        }

        if (useLockedTokens) {
            require(
                tokenLock.transfer(msg.sender, payout),
                "GoatCast transfer failed"
            );
        } else {
            // Handle native BTC
            (bool sent, ) = payable(msg.sender).call{value: payout}("");
            require(sent, "BTC transfer failed");
        }

        emit WinningsClaimed(
            marketId,
            eventId,
            msg.sender,
            payout,
            useLockedTokens
        );
    }

    // Admin Functions
    function pauseMarket(uint256 marketId) external onlyRole(ADMIN_ROLE) {
        Market storage market = markets[marketId];
        require(!market.isPaused, "Already paused");
        market.isPaused = true;
        emit MarketPaused(marketId);
    }

    function unpauseMarket(uint256 marketId) external onlyRole(ADMIN_ROLE) {
        Market storage market = markets[marketId];
        require(market.isPaused, "Not paused");
        market.isPaused = false;
        emit MarketUnpaused(marketId);
    }

    function updateTokens(address newtokenLock) external onlyRole(ADMIN_ROLE) {
        require(newtokenLock != address(0), "Invalid token locker address");
        tokenLock = IGoatCastLocker(newtokenLock); // Changed from IERC20 to IGoatCastLocker
    }

    // Emergency Functions
    function emergencyResolveEvent(
        uint256 marketId,
        uint256 eventId,
        string memory reason
    ) external onlyRole(ADMIN_ROLE) {
        Event storage event_ = markets[marketId].events[eventId];
        require(!event_.isResolved, "Already resolved");

        event_.isResolved = true;
        event_.isActive = false;
        event_.winner = "EMERGENCY_RESOLVED";

        emit EmergencyEventResolved(marketId, eventId, reason);
    }

    function emergencyWithdraw(
        uint256 marketId,
        uint256 eventId
    ) external onlyRole(ADMIN_ROLE) {
        require(markets[marketId].isPaused, "Market must be paused");

        // Withdraw GoatCast tokens
        uint256 goatCastBalance = tokenLock.balanceOf(address(this));
        if (goatCastBalance > 0) {
            require(
                tokenLock.transfer(msg.sender, goatCastBalance),
                "GoatCast token transfer failed"
            );
            emit EmergencyWithdrawal(
                marketId,
                eventId,
                address(tokenLock),
                msg.sender
            );
        }

        // Withdraw native BTC
        uint256 btcBalance = address(this).balance;
        if (btcBalance > 0) {
            (bool sent, ) = payable(msg.sender).call{value: btcBalance}("");
            require(sent, "BTC transfer failed");
            emit EmergencyWithdrawal(marketId, eventId, address(0), msg.sender);
        }
    }

    // Role Management Functions
    function addOracle(address oracle) external onlyRole(ADMIN_ROLE) {
        grantRole(ORACLE_ROLE, oracle);
        emit OracleAdded(oracle);
    }

    function removeOracle(address oracle) external onlyRole(ADMIN_ROLE) {
        revokeRole(ORACLE_ROLE, oracle);
        emit OracleRemoved(oracle);
    }

    function addWeatherOracle(address oracle) external onlyRole(ADMIN_ROLE) {
        grantRole(WEATHER_ORACLE_ROLE, oracle);
        emit WeatherOracleAdded(oracle);
    }

    // View Functions for Event Details
    function getEventDetails(
        uint256 marketId,
        uint256 eventId
    )
        external
        view
        returns (
            string memory name,
            MarketCategory category,
            uint256 yesSharePrice,
            uint256 noSharePrice,
            uint256 yesAvailable,
            uint256 noAvailable,
            uint256 startTime,
            uint256 endTime,
            bool isActive,
            bool isResolved,
            string memory winner,
            uint256 protocolFee,
            uint256 volume // New return value
        )
    {
        Event storage event_ = markets[marketId].events[eventId];
        EventShares storage shares = event_.shares;

        return (
            event_.name,
            event_.category,
            shares.yesSharePrice,
            shares.noSharePrice,
            shares.availableYesShares,
            shares.availableNoShares,
            event_.startTime,
            event_.endTime,
            event_.isActive,
            event_.isResolved,
            event_.winner,
            event_.protocolFee,
            eventVolumes[marketId][eventId] // Return volume
        );
    }

    function getUserPosition(
        uint256 marketId,
        uint256 eventId,
        address user
    )
        external
        view
        returns (
            uint256 yesShares,
            uint256 noShares,
            uint256 yesValue,
            uint256 noValue
        )
    {
        Event storage event_ = markets[marketId].events[eventId];
        SharePosition storage position = event_.shares.userPositions[user];

        return (
            position.yesShares,
            position.noShares,
            position.yesShares * event_.shares.yesSharePrice,
            position.noShares * event_.shares.noSharePrice
        );
    }

    // Market and Event Statistics
    function getMarketCount(
        MarketCategory category
    ) external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < marketCount; i++) {
            if (markets[i].category == category && markets[i].isActive) {
                count++;
            }
        }
        return count;
    }

    function getActiveEvents(
        uint256 marketId
    ) external view returns (uint256[] memory) {
        Market storage market = markets[marketId];
        uint256[] memory activeEvents = new uint256[](market.eventCount);
        uint256 count = 0;

        for (uint256 i = 0; i < market.eventCount; i++) {
            if (market.events[i].isActive) {
                activeEvents[count] = i;
                count++;
            }
        }

        // Resize array to actual count
        assembly {
            mstore(activeEvents, count)
        }

        return activeEvents;
    }

    function getMarketStats(
        uint256 marketId
    )
        external
        view
        returns (
            uint256 totalEvents,
            uint256 activeEvents,
            uint256 resolvedEvents,
            uint256 totalValueLocked
        )
    {
        Market storage market = markets[marketId];
        uint256 active = 0;
        uint256 resolved = 0;

        for (uint256 i = 0; i < market.eventCount; i++) {
            if (market.events[i].isActive) active++;
            if (market.events[i].isResolved) resolved++;
        }

        return (market.eventCount, active, resolved, market.totalValueLocked);
    }

    // Upgrade Authorization
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(ADMIN_ROLE) {}

    // Add this with other view functions
    function getEventVolume(
        uint256 marketId,
        uint256 eventId
    ) external view returns (uint256) {
        return eventVolumes[marketId][eventId];
    }

    // Required receive function to accept native BTC
    receive() external payable {}

    // Required fallback function
    fallback() external payable {}
}
