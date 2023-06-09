// *************************************************************************************************************************************
// *************************************************************************************************************************************
// *****************.     .,*/**********************************************************************************************************
// ************                 ,*******************************************************************************************************
// *********.          .         **********************************************************************/********************************
// ********      ############ ,**********&@@@@@@@@@@@@@@@@/****@@@@@@@@@@@@@@@@@@%/**%@&*************/@@****&@@@@@@@@@@@@@@@@@@@&/******
// *******     #############*   ********@@***************/*****@@**************/*@@**%@&**************@@*************%@&****************
// *****/     #####**(###(**    .*******@@@********************@@****************%@@*%@&**************@@*************%@&****************
// ******     ####********/##     *********&@@@@@#/************@@***************/@@**%@&**************@@*************%@&****************
// ******.    ###***/****/####    *****************%@@@@@/*****@@@@@@@@@@@@@@@@@@****%@&**************@@*************%@&****************
// *******     /**####**(###%.    ***********************@@@***@@********************%@&**************@@*************%@&****************
// ********,  .(############,     ************************@@***@@*********************@@**************@@*************%@&****************
// ********** (###########..     *******@@@@@@@@@@@@@@@@@@@****@@**********************@@@@@@@@@%(****@@*************%@&****************
// *******,           .       .*************/((((((((/*********//*************************************/*********************************
// ********.                .***********************************************************************************************************
// *************.     .,****************************************************************************************************************
// *************************************************************************************************************************************
// *************************************************************************************************************************************

pragma solidity 0.8.13;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract VESPLXToken is ERC721 {

    struct Allocation {
        uint256 amount;
        uint256 veShare;
        uint256 unlockTimestamp;
        address token;
    }

    event MoveAlloc(address indexed oldClaimer, address indexed newClaimer, uint256 veShare);
    event Deposit(address indexed staker, address indexed token, uint256 lockTimestamp, uint256 unlockTimestamp, uint256 amount, uint256 veShare);
    event Withdrawal(address indexed staker, address indexed token, uint256 amount);
    event OwnershipTransferred(address indexed owner);

    uint256 private entryStatus;
    address private deployer;
    string private pictureUri;
    bool public diffTokens;
    uint256 public totalShare;
    uint256 public allocID = 1;
    mapping(uint256 => address) private _claimers;
    mapping(uint256 => Allocation) private _allocations;
    mapping(uint256 => uint256) private lockTimes;
    mapping(uint256 => uint256) private lockTimeMultiplier;
    mapping(address => bool) private possibleEscrowToken;
    address public immutable protocolToken;
    uint256 private constant ONE_MONTH = 31 days;
    address private constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    modifier onlyOwner() {
        require(msg.sender == deployer, "Split: Not allowed");
        _;
    }

    modifier nonReentrant() {
        require(entryStatus == 0, "Split: Re-entered");
        entryStatus = 1;
        _;
        entryStatus = 0;
    }

    constructor(address _protocolToken, string memory _pictureUri) ERC721("Split Voting Escrow", "veSPLX") {
        deployer = msg.sender;
        protocolToken = _protocolToken;
        pictureUri = _pictureUri;
        diffTokens = false;
        lockTimes[0] = ONE_MONTH;
        lockTimeMultiplier[0] = 10;
        lockTimes[1] = ONE_MONTH * 3;
        lockTimeMultiplier[1] = 25;
        lockTimes[2] = ONE_MONTH * 6;
        lockTimeMultiplier[2] = 50;
        lockTimes[3] = ONE_MONTH * 12;
        lockTimeMultiplier[3] = 100;
        possibleEscrowToken[_protocolToken] = true;
    }

    receive() external payable {

    }

    fallback() external payable {

    }

    function deposit(uint256 amount, uint256 lockTimestampID, address token) external nonReentrant {
        require(possibleEscrowToken[token], "Split: token not allowed for staking");
        require(amount > 0, "Split: zero amount");
        require(lockTimestampID <= 3, "Split: bad id");
        uint256 tokenAmount;
        address prtt = protocolToken;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, shl(0xe0, 0x23b872dd))
            mstore(add(ptr, 0x04), caller())
            mstore(add(ptr, 0x24), address())
            mstore(add(ptr, 0x44), amount)
            if iszero(call(gas(), token, 0, ptr, 0x64, 0, 0)) { revert(0, 0) }
            if eq(token, prtt) {
                tokenAmount := amount
            }
            if iszero(eq(token, prtt)) {
                mstore(ptr, shl(0xe0, 0x70a08231))
                mstore(add(ptr, 0x04), token)
                if iszero(staticcall(gas(), prtt, ptr, 0x24, ptr, 0x20)) { revert(0, 0) }
                let lpbalance := mload(ptr)
                mstore(ptr, shl(0xe0, 0x18160ddd))
                if iszero(staticcall(gas(), token, ptr, 0x04, ptr, 0x20)) { revert(0, 0) }
                let psupply := mload(ptr)
                tokenAmount := div(mul(amount, lpbalance), psupply)
            }
        }
        uint256 veShare = lockTimeMultiplier[lockTimestampID] * tokenAmount / 100;
        uint256 unlockTimestamp = block.timestamp + lockTimes[lockTimestampID];
        _allocations[allocID] = Allocation(amount, veShare, unlockTimestamp, token);
        _safeMint(msg.sender, allocID);
        allocID++;
        totalShare += veShare;
        emit Deposit(msg.sender, token, block.timestamp, unlockTimestamp, amount, veShare);
    }

    function withdraw(uint256 tokenId) external nonReentrant {
        require(_ownerOf(tokenId) == msg.sender, "Split: Not token owner");
        Allocation memory tokenAlloc = _allocations[tokenId];
        require(block.timestamp > tokenAlloc.unlockTimestamp, "Split: allocation not expired");
        _burn(tokenId);
        {
            uint256 tokenAllocAmount = tokenAlloc.amount;
            address tokenAllocToken = tokenAlloc.token;
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, shl(0xe0, 0xa9059cbb))
                mstore(add(ptr, 0x04), caller())
                mstore(add(ptr, 0x24), tokenAllocAmount)
                if iszero(call(gas(), tokenAllocToken, 0, ptr, 0x44, 0, 0)) { revert(0, 0) }
            }
        }
        totalShare -= tokenAlloc.veShare;
        emit Withdrawal(msg.sender, tokenAlloc.token, tokenAlloc.amount);
    }

    function rescueFunds(address token) external onlyOwner {
        require(!possibleEscrowToken[token], "Split: forbidden token");
        assembly {
            if eq(token, ETH) {
                if iszero(call(gas(), caller(), balance(address()), 0, 0, 0, 0)) { revert(0, 0) }
            }
            if iszero(eq(token, ETH)) {
                let ptr := mload(0x40)
                mstore(ptr, shl(0xe0, 0x70a08231))
                mstore(add(ptr, 0x04), address())
                if iszero(staticcall(gas(), token, ptr, 0x24, ptr, 0x20)) { revert(0, 0) }
                let amount := mload(ptr)
                mstore(ptr, shl(0xe0, 0xa9059cbb))
                mstore(add(ptr, 0x04), caller())
                mstore(add(ptr, 0x24), amount)
                if iszero(call(gas(), token, 0, ptr, 0x44, 0, 0)) { revert(0, 0) }
            }
        }
    }

    function destroySelf() external onlyOwner {
        assembly {
            selfdestruct(caller())
        }
    }

    function transferOwnership(address owner) external onlyOwner {
        deployer = owner;
        emit OwnershipTransferred(owner);
    }

    function changeURI(string memory picUri) external onlyOwner {
        pictureUri = picUri;
    }

    function changeDiff() external onlyOwner {
        diffTokens = !diffTokens;
    }

    function setPossibleTokenStatus(address[] calldata tokens, bool status) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            possibleEscrowToken[tokens[i]] = status;
        }
    }

    function claimerOf(uint256 tokenId) external view returns (address) {
        address claimer = _claimers[tokenId];
        require(claimer != address(0), "Split: claimer query for nonexistent token");
        return claimer;
    }

    function viewAllocation(uint256 tokenId) external view returns (uint256, uint256, uint256, address) {
        require(_exists(tokenId), "Split: allocation query for nonexistent token");
        Allocation memory tokenAlloc = _allocations[tokenId];
        return (tokenAlloc.amount, tokenAlloc.veShare, tokenAlloc.unlockTimestamp, tokenAlloc.token);
    }

    function getRewardLoopInfo() external view returns (uint256, uint256) {
        return (totalShare, allocID);
    }

    function getRewardInfo(uint256 tokenId) external view returns (uint256, address) {
        require(_exists(tokenId), "Split: allocation query for nonexistent token");
        address claimer = _claimers[tokenId];
        require(claimer != address(0), "Split: claimer query for nonexistent token");
        Allocation memory tokenAlloc = _allocations[tokenId];
        return (tokenAlloc.veShare, claimer);
    }

    function viewAllocations(address user, uint256 startID, uint256 len) external view returns (uint256[] memory out) {
        require(startID < allocID && startID > 0, "Split: out of bounds");
        uint256 finalLen = (startID + len <= allocID) ? len : allocID - startID;
        uint256[] memory outRaw = new uint256[](finalLen);
        uint256 outID = 0;
        for (uint256 i = startID; i < (startID + finalLen); i++) {
            if (_ownerOf(i) == user) {
                outRaw[outID] = i;
                outID++;
            }
        }
        require(outID > 0, "Split: no IDs found");
        out = new uint256[](outID);
        for (uint256 i = 0; i < outID; i++) {
            out[i] = outRaw[i];
        }
    }

    function isAllocationExpired(uint256 tokenId) external view returns (bool) {
        require(_exists(tokenId), "Split: allocation query for nonexistent token");
        Allocation memory tokenAlloc = _allocations[tokenId];
        return block.timestamp > tokenAlloc.unlockTimestamp;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);
        if (diffTokens) {
            return string(abi.encodePacked(pictureUri, Strings.toString(tokenId)));
        } else {
            return pictureUri;
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize) internal override {
        if (from == address(0)) {
            if (___isContract(to)) {
                (bool success, bytes memory data) = to.staticcall(abi.encodeWithSignature("getSplitRewardClaimer()"));
                if (!success) {
                    if (data.length == 0) {
                        revert("Split: no claimer for contract");
                    } else {
                        assembly {
                            revert(add(32, data), mload(data))
                        }
                    }
                }
                address claimer = abi.decode(data, (address));
                require(!___isContract(claimer), "Split: claimer must be address");
                _claimers[firstTokenId] = claimer;
            } else {
                _claimers[firstTokenId] = to;
            }
            Allocation memory tokenAlloc = _allocations[firstTokenId];
            emit MoveAlloc(from, _claimers[firstTokenId], tokenAlloc.veShare);
        } else if (to == address(0)) {
            Allocation memory tokenAlloc = _allocations[firstTokenId];
            emit MoveAlloc(_claimers[firstTokenId], to, tokenAlloc.veShare);
            delete _claimers[firstTokenId];
            delete _allocations[firstTokenId];
        } else {
            address oldClaimer = _claimers[firstTokenId];
            if (___isContract(to)) {
                (bool success, bytes memory data) = to.staticcall(abi.encodeWithSignature("getSplitRewardClaimer()"));
                if (!success) {
                    if (data.length == 0) {
                        revert("Split: no claimer for contract");
                    } else {
                        assembly {
                            revert(add(32, data), mload(data))
                        }
                    }
                }
                address claimer = abi.decode(data, (address));
                require(!___isContract(claimer), "Split: claimer must be address");
                _claimers[firstTokenId] = claimer;
            } else {
                _claimers[firstTokenId] = to;
            }
            Allocation memory tokenAlloc = _allocations[firstTokenId];
            emit MoveAlloc(oldClaimer, _claimers[firstTokenId], tokenAlloc.veShare);
        }
    }

    function ___isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}