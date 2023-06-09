pragma solidity 0.8.13;

interface IFlashLender {
    function flashLoan(address receiver, address token, uint256 amount, bytes calldata data) external returns (bool);
}