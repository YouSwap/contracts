// SPDX-License-Identifier: MIT

pragma solidity 0.7.4;

import './../interface/IYouswapAssetManagerV1.sol';
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract YouswapAssetManagerV1 is IYouswapAssetManagerV1 {
    
    using SafeERC20 for IERC20;
    
    uint256 public deployBlock;//合约部署块高
    address public owner;//所有权限
    mapping(address => bool) public minters;
    
    constructor () {
        deployBlock = block.number;
        owner = msg.sender;
        _setMinter(msg.sender, true);
    }
    
    function mint(address _token, address _to, uint256 _amount) override external {
        require(minters[msg.sender], 'YouSwap:FORBIDDEN');
        IERC20(_token).safeTransfer(_to, _amount);
    }
    
    function setMinter(address _account, bool _bool) override external {
        _setMinter(_account, _bool);
    }
    
    function _setMinter(address _account, bool _bool) internal {
        require(owner == msg.sender, 'YouSwap:FORBIDDEN');
        minters[_account] = _bool;
    }

    function transferOwnership(address _owner) override external {
        require(owner == msg.sender, 'YouSwap:FORBIDDEN');
        require((address(0) != _owner) && (owner != _owner), 'YouSwap:INVALID_ADDRESSES');
        _setMinter(owner, false);
        _setMinter(_owner, true);
        owner = _owner;
    }

}