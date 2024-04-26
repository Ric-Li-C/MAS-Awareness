// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC721A} from "./lib/ERC721A.sol";
import {IERC2981, ERC2981} from "./lib/ERC2981.sol";
import {Strings} from "./lib/Strings.sol";

interface ERC20Token {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract Mas_Bsc is ERC721A, ERC2981 {
    using Strings for uint256;

    address public immutable OWNER;
    RoyaltyInfo private _royaltyStruct;
    string private _strBaseURI;
    bool public isRevealed;
    uint256 public constant MAX_SUPPLY = 10000;
    uint256 public constant MINT_PRICE = 0.09 ether;
    uint256 public donorCount;
    uint256 public referrerCount;
    mapping(address => bool) public isDonor;
    mapping(address => bool) public isReferrer;
    mapping(address => bool) public isWhitelisted;
    mapping(address => uint256) public referralAmount;
    ERC20Token private _tokenContract;

    event RoyaltyUpdated(address receiver, uint96 points);
    event ImageRevealed(string baseURI);
    event NftMinted(address minter, uint256 amount);

    /* ========== Set Up Functions ========== */
    // Royalty is in 10000, so 1000 means 10%
    constructor() ERC721A("MAS Awareness Project (BSC)", "MAP") {
        OWNER = msg.sender;
        _royaltyStruct = RoyaltyInfo(msg.sender, 1000);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function _checkOwner() internal view {
        require(msg.sender == OWNER, "Not owner");
    }

    function _baseURI() internal view override returns (string memory) {
        return _strBaseURI;
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    /* ========== Admin Setting Function ========== */
    // Royalty is in 10000, so 500 means 5%, 1000 means 10%, etc
    function setRoyalty(
        address newReceiver,
        uint96 newPoints
    ) external onlyOwner {
        require(newPoints <= 10000, "Invalid royalty points");

        address _receiver = newReceiver;

        if (newReceiver == address(0)) {
            _receiver = msg.sender;
        }
        _royaltyStruct = RoyaltyInfo(_receiver, newPoints);

        emit RoyaltyUpdated(_receiver, newPoints);
    }

    function revealImage(string memory newbaseURI) external onlyOwner {
        _strBaseURI = newbaseURI;
        isRevealed = true;

        emit ImageRevealed(newbaseURI);
    }

    /* ========== Main Functions ========== */
    function batchMint(address referral, uint256 numNfts) external payable {
        uint256 totalMinted = totalSupply();
        uint256 remaining = MAX_SUPPLY - totalMinted;
        require(totalMinted < MAX_SUPPLY, "All minted");
        require(numNfts > 0 && numNfts <= remaining, "Invalid number of NFTs");

        uint256 mintFee = numNfts * MINT_PRICE;
        require(msg.value >= mintFee, "Insufficient value");

        _mint(msg.sender, numNfts);
        if (!isDonor[msg.sender]) {
            donorCount++;
            isDonor[msg.sender] = true;
        }

        if (referral != address(0)) {
            if (!isReferrer[referral]) {
                referrerCount++;
                isReferrer[referral] = true;
            }
            referralAmount[referral] += mintFee / 3;
        }

        emit NftMinted(msg.sender, numNfts);
    }

    /* ========== Whitelist Functions ========== */
    function addWhitelist(address[] memory addressArray) external onlyOwner {
        for (uint256 i; i < addressArray.length; i++) {
            isWhitelisted[addressArray[i]] = true;
        }
    }

    function claim() external {
        require(isWhitelisted[msg.sender], "Not in whitelist");

        isWhitelisted[msg.sender] = false;
        _mint(msg.sender, 1);

        emit NftMinted(msg.sender, 1);
    }

    /* ========== Withdraw Functions ========== */
    // Total referral amount will be withdrawn at once
    function referralWithdraw() external {
        uint256 balance = address(this).balance;
        uint256 amountToWithdraw = referralAmount[msg.sender];
        require(amountToWithdraw > 0, "No referral amount");
        require(balance >= amountToWithdraw, "Insufficient contract balance");

        // Set `referralAmount[msg.sender]` to `0` before withdraw action to prevent reentrancy attack
        referralAmount[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amountToWithdraw}(
            ""
        );
        require(success, "Withdrawal failed");
    }

    // Total contract balance will be withdrawn at once
    function adminWithdraw(address payable recipient) external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "Contract balance is zero");

        if (recipient == address(0)) {
            recipient = payable(OWNER);
        }

        (bool success, ) = payable(recipient).call{value: balance}("");
        require(success, "Withdrawal failed");
    }

    /* ========== ERC20 Token Transfer Functions ========== */
    // This function serves two purposes:
    // 1. To handle airdrops received by the contract;
    // 2. To assist in recovering ERC20 tokens mistakenly transferred to this contract address.
    function transferERC20Token(
        address tokenAddress,
        address to,
        uint256 amount
    ) external returns (bool) {
        _tokenContract = ERC20Token(tokenAddress);
        return _tokenContract.transfer(to, amount);
    }

    /* ========== Override Functions ========== */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        if (!_exists(tokenId)) _revert(URIQueryForNonexistentToken.selector);

        string memory json;

        if (!isRevealed) {
            json = string(
                abi.encodePacked(
                    '{"name": "Awareness #',
                    tokenId.toString(),
                    '","description":"This is #',
                    tokenId.toString(),
                    ' NFT in MAS Awareness NFT Project (BSC).",',
                    '"external_url":"https://mas_awareness.top",',
                    '"image":"https://raw.githubusercontent.com/Ric-Li-C/MAS_Awareness/main/image/nft.png"}'
                )
            );
        } else {
            json = string(
                abi.encodePacked(_strBaseURI, tokenId.toString(), ".json")
            );
        }

        return json;
    }

    function royaltyInfo(
        uint256,
        uint256 salePrice
    ) public view override returns (address, uint256) {
        uint256 royaltyAmount = (salePrice * _royaltyStruct.royaltyFraction) /
            _feeDenominator();

        return (_royaltyStruct.receiver, royaltyAmount);
    }

    // Override required because both contracts have same function
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721A, ERC2981) returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 interface ID for ERC165.
            interfaceId == 0x80ac58cd || // ERC165 interface ID for ERC721.
            interfaceId == 0x5b5e139f || // ERC165 interface ID for ERC721Metadata.
            interfaceId == type(IERC2981).interfaceId;
    }
}
