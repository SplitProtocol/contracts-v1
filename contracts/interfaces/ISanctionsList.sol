pragma solidity 0.8.13;

interface ISanctionsList {
    function isSanctioned(address addr) external view returns (bool);
}