// SPDX-License-Identifier: MIT

pragma solidity 0.7.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import './../library/ErrorCode.sol';

contract XToken is ERC20 {

    constructor (string memory _name, string memory _symbol, uint256 _amount) ERC20(_name, _symbol) {
        mint(0xbF395508fB2409dbD6c5C2f7cF8824AC79017939, _amount);//leeqiang
        mint(0x07346765D6063180dc2a09B1774E3Cd34cA38CC3, _amount);//leeqiang
        mint(0x25735337fE8cd56CD91944F2Ef8aC65c5Cf68426, _amount);//leeqiang        
        mint(0x9C92cC086D594743B0b9f99298Aeae572EE46579, _amount);//leeqiang
        mint(0xf4e1D63fCf3064B56734969F22665b862522E3a4, _amount);//leeqiang
        mint(0xC230a0138DAaA6767b60e6A49EeC72961723247b, _amount);//leeqiang
        mint(0x3763bbc2aD21afAa743fe61E3114925Db26b0311, _amount);//zhang zhan nan
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        return true;
    }

    function mint(address _address, uint256 _amount) public {
        _mint(_address, _amount);
    }

}