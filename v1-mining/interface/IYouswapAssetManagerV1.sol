// SPDX-License-Identifier: MIT

pragma solidity 0.7.4;

interface IYouswapAssetManagerV1 {
    
    function mint(address, address, uint256) external;
    
    function setMinter(address, bool) external;

    /**
    修改OWNER
     */
    function transferOwnership(address) external;
    
}