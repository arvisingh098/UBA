// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

interface IUBADexFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function migrator() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);
    function tradeFee() external view returns (uint256);
    function gToken() external view returns (address);
    function isPair(address _pair) external view returns (bool);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
    function setMigrator(address) external;
    function setGToken(address _gToken) external;
    function setTradeFee(uint256 _tradeFee) external;
    function setGTokenFee(uint256 _gFee) external;
    function isWhitelistBurnAddress(address) external view returns (bool);
}
