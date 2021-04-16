pragma solidity >=0.5.0;

interface ISwapMining {
    function swap(address account, address input, address output, uint256 amount) external returns (bool);
}
