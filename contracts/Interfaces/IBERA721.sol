// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IBERA721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}