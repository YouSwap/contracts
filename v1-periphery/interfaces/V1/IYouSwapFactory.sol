pragma solidity >=0.5.0;

interface IYouSwapFactory {
    function getExchange(address) external view returns (address);
}
