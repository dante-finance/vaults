// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface DanteStrategy {
    function pause() external;
    function unpause() external;
    function panic() external;
}