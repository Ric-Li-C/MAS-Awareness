// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC721A} from "./lib/ERC721A.sol";
import {IERC2981, ERC2981} from "./lib/ERC2981.sol";
import {Strings} from "./lib/Strings.sol";

contract Mas_Bsc is ERC721A, ERC2981 {
    using Strings for uint256;

    address public immutable OWNER;
    RoyaltyInfo private _royaltyStruct;
    string private _strBaseURI;
    bool public isRevealed;
    uint256 public constant MAX_SUPPLY = 10000;
    uint256 public constant MINT_PRICE = 0.09 ether;
    mapping(address => bool) public isWhitelisted;
    mapping(address => uint256) public referralAmount;

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
        address _newReceiver,
        uint96 _newPoints
    ) external onlyOwner {
        require(_newPoints <= 10000, "Invalid royalty points");

        address _receiver = _newReceiver;

        if (_newReceiver == address(0)) {
            _receiver = msg.sender;
        }
        _royaltyStruct = RoyaltyInfo(_receiver, _newPoints);

        emit RoyaltyUpdated(_receiver, _newPoints);
    }

    function revealImage(string memory _newbaseURI) external onlyOwner {
        _strBaseURI = _newbaseURI;
        isRevealed = true;

        emit ImageRevealed(_newbaseURI);
    }

    /* ========== Main Functions ========== */
    function batchMint(address _referral, uint256 _numNfts) external payable {
        uint256 totalMinted = totalSupply();
        uint256 remaining = MAX_SUPPLY - totalMinted;
        require(totalMinted < MAX_SUPPLY, "All minted");
        require(
            _numNfts > 0 && _numNfts <= remaining,
            "Invalid number of NFTs"
        );

        uint256 mintFee = _numNfts * MINT_PRICE;
        require(msg.value >= mintFee, "Insufficient value");

        if (_referral != address(0)) {
            referralAmount[_referral] += mintFee / 3;
        }

        _mint(msg.sender, _numNfts);

        emit NftMinted(msg.sender, _numNfts);
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
    function adminWithdraw(address payable _recipient) external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "Contract balance is zero");

        if (_recipient == address(0)) {
            _recipient = payable(OWNER);
        }

        (bool success, ) = payable(_recipient).call{value: balance}("");
        require(success, "Withdrawal failed");
    }

    /* ========== Override Functions ========== */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        if (!_exists(tokenId)) _revert(URIQueryForNonexistentToken.selector);

        string memory image_url;
        string memory json;

        if (!isRevealed) {
            image_url = "https://raw.githubusercontent.com/0xacme/pandora/main/3.gif";
        } else {
            image_url = string(
                abi.encodePacked(_strBaseURI, tokenId.toString(), ".png")
            );
        }

        json = string(
            abi.encodePacked(
                '{"name": "Awareness #',
                tokenId.toString(),
                '","description":"This is #',
                tokenId.toString(),
                ' NFT in MAS Awareness NFT Project (BSC).",',
                '"external_url":"https://mas_awareness.top",',
                '"image":"',
                image_url,
                '"}'
            )
        );

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
