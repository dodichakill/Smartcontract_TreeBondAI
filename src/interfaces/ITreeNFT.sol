// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ITreeRegistry } from "./ITreeRegistry.sol";

interface ITreeNFT {
    function mint(address to, uint256 treeId) external returns (uint256 tokenId);

    function treeRegistry() external view returns (ITreeRegistry);
}
