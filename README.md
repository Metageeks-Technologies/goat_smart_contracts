# GoatCast

GoatCast is a decentralized platform deployed on the Goat Network. Below are the deployed contract addresses with clickable links for easy access to the blockchain explorer.

## Deployed Contracts

- **GoatCastToken:** [0x1A9b32bFeF5aA57daA3475673a46a907b245F9c2](https://explorer.testnet3.goat.network/address/0x1A9b32bFeF5aA57daA3475673a46a907b245F9c2)
- **GoatCastLocker:** [0x573187B167fD4d834FC961083c8C84d605c6c920](https://explorer.testnet3.goat.network/address/0x573187B167fD4d834FC961083c8C84d605c6c920)
- **Market Implementation:** [0x742E8f419Aa58a9228C1a740cBdB924a41b31fB0](https://explorer.testnet3.goat.network/address/0x742E8f419Aa58a9228C1a740cBdB924a41b31fB0)
- **GoatCastFactory:** [0x8f33EE10159f713540D10DBcDA5f953022a9e2dd](https://explorer.testnet3.goat.network/address/0x8f33EE10159f713540D10DBcDA5f953022a9e2dd)

## Contract Descriptions

### GoatCastFactory
A factory contract that serves as the central hub for deploying and managing prediction markets. It handles:
- Creation of new market instances using a cloning mechanism
- Role-based access control for creators, operators, and administrators
- Tracking all deployed markets
- Authorization of markets in the token and locker contracts
- Management of implementation addresses for upgradeable contracts

### GoatCastToken
An ERC20 token contract that serves as the platform's native currency:
- Implements standard ERC20 functionality with added access control
- Supports minting tokens through direct purchase with BTC
- Maintains a list of authorized markets that can use tokens
- Includes configurable token pricing and withdrawal functionality
- Implements UUPS upgradeability pattern

### GoatCastLocker
A token locking mechanism that enables users to participate in prediction markets:
- Allows users to lock/unlock their GoatCast tokens
- Provides interfaces for markets to access locked tokens for betting
- Implements strict access control for authorized markets only
- Tracks user participation and locked token amounts
- Includes emergency withdrawal functionality for admins
- Implements UUPS upgradeability pattern

### GoatCastMarket
The core prediction market contract with comprehensive functionality for various prediction types:
- Supports multiple market categories: Crypto, Sports, Politics, Weather, Entertainment
- Implements advanced AMM (Automated Market Maker) pricing mechanism
- Manages share positions, buying/selling, and winnings distribution
- Integrates with oracles for reliable resolution of events
- Includes specialized event types with category-specific parameters
- Features dynamic price scaling based on volume
- Implements various safety controls including emergency resolution
- Supports both GoatCast tokens and native BTC for transactions
- Implements UUPS upgradeability pattern

## Getting Started
To interact with GoatCast, follow these steps:
1. Visit the Goat Network explorer to verify contract transactions.
2. Use the provided contract addresses to integrate with the platform.
3. Follow the repository documentation for further details on how to interact with the smart contracts.

## License
This project is licensed under the MIT License.

`