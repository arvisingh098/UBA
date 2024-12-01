// SPDX-License-Identifier: GPL-3.0

pragma solidity =0.6.12;

import './interfaces/IUBADexFactory.sol';
import './UBADexPair.sol';

contract UBADexFactory is IUBADexFactory {
    address public override feeTo;
    address public override feeToSetter;
    address public override migrator;
    address public override gToken;

    mapping(address => mapping(address => address)) public override getPair;
    mapping(address => bool) public override isPair;
    address[] public override allPairs;
    mapping(address => bool) public override isWhitelistBurnAddress;

    uint256 public override tradeFee;
    uint256 public gTokenFee;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external override view returns (uint) {
        return allPairs.length;
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(UBADexPair).creationCode);
    }

    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        require(tokenA != tokenB, 'UBADex: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UBADex: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'UBADex: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(UBADexPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        UBADexPair(pair).initialize(token0, token1, gTokenFee);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        isPair[pair] = true;
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeToSetter, 'UBADex: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setGTokenFee(uint256 _gFee) external override {
        require(msg.sender == feeToSetter, 'UBADex: FORBIDDEN');
        gTokenFee = _gFee;
    }

    function setTradeFee(uint256 _tradeFee) external override {
        require(msg.sender == feeToSetter, 'UBADex: FORBIDDEN');
        tradeFee = _tradeFee;
    }

    function setGToken(address _gToken) external override {
        require(msg.sender == feeToSetter, 'UBADex: FORBIDDEN');
        gToken = _gToken;
    }

    function setMigrator(address _migrator) external override {
        require(msg.sender == feeToSetter, 'UBADex: FORBIDDEN');
        migrator = _migrator;
    }

    function setFeeToSetter(address _feeToSetter) external override {
        require(msg.sender == feeToSetter, 'UBADex: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }

    // Function to add an address to the whitelist
    function whitelistBurnAddress(address account, bool status) public  {
        require(msg.sender == feeToSetter, 'UBADex: FORBIDDEN');
        require(isWhitelistBurnAddress[account] != status, "Factory: Already in same status");
        isWhitelistBurnAddress[account] = status;
    }
}