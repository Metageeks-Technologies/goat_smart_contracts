// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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

    function authorizedMarkets(address market) external view returns (bool);

    function authorizeMarket(address market) external;

    function deauthorizeMarket(address market) external;
}
