// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./Interfaces/IBERA721.sol";
import "./Interfaces/IBERA20.sol";

contract router {
    // --- Enum for NFT Rarity ---
    enum Rarity { Common, Rare, Legendary }

    // --- Structs ---
    struct Offer {
        Rarity nftRarity;
        uint256 bribeAmount; // In UBA token
        address offerCreator;
        bool isActive;
    }

    // --- Structs ---
    struct Range {
        uint256 startId;
        uint256 endId;
        Rarity rarity;
    }

    // --- State Variables ---
    address public admin;
    IBERA721 public nftContract;
    IBERA20 public gToken; // G-Token Interface
    IBERA20 public ubaToken; // UBA Token Interface

    mapping(uint256 => Offer) public offers; // Offer ID => Offer struct
    mapping(Rarity => uint256) public rarityPrices; // Price in G-Token for each rarity
    mapping(address => uint256[]) private userOffers; // Tracks offer IDs for each user
    
    Range[] public rarityRanges; // Array to store ranges for rarities
    
    uint256 public offerCounter;

    // --- Modifiers ---
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    modifier onlyNFTContractOwner(uint256 tokenId) {
        require(nftContract.ownerOf(tokenId) == msg.sender, "Not the NFT owner");
        _;
    }

    // --- Events ---
    event OfferCreated(uint256 indexed offerId, address indexed creator, Rarity nftRarity, uint256 bribeAmount);
    event OfferAccepted(uint256 indexed offerId, address indexed accepter, uint256 tokenId);
    event RarityPriceSet(Rarity rarity, uint256 price);
    event RarityRangeSet(uint256 startId, uint256 endId, Rarity rarity);

    // --- Constructor ---
    constructor(address _nftContract, address _gToken, address _ubaToken) {
        admin = msg.sender;
        nftContract = IBERA721(_nftContract);
        gToken = IBERA20(_gToken);
        ubaToken = IBERA20(_ubaToken);
        offerCounter = 0;
    }

    // --- Admin Functions ---
    function setRarityPrice(Rarity _rarity, uint256 _price) external onlyAdmin {
        rarityPrices[_rarity] = _price;
        emit RarityPriceSet(_rarity, _price);
    }

    // --- Admin Functions ---
    function setNFTsRange(uint256 startId, uint256 endId, Rarity _rarity) external onlyAdmin {
        require(startId < endId, "Invalid range");
        
        // Add a new range
        rarityRanges.push(Range({
            startId: startId,
            endId: endId,
            rarity: _rarity
        }));
        
        emit RarityRangeSet(startId, endId, _rarity);
    }

    // --- Helper Function ---
    function getRarity(uint256 tokenId) public view returns (Rarity) {
        for (uint256 i = 0; i < rarityRanges.length; i++) {
            if (tokenId >= rarityRanges[i].startId && tokenId <= rarityRanges[i].endId) {
                return rarityRanges[i].rarity;
            }
        }
        revert("NFT ID does not match any defined rarity range");
    }

    // --- User Functions ---
    function createOffer(Rarity _rarity, uint256 _bribeAmount) external {
        uint256 price = rarityPrices[_rarity];
        require(price > 0, "Invalid rarity price");

        // Transfer G-Token and UBA tokens to contract
        require(gToken.transferFrom(msg.sender, address(this), price), "G-Token transfer failed");
        require(ubaToken.transferFrom(msg.sender, address(this), _bribeAmount), "UBA token transfer failed");

        // Create Offer
        offers[offerCounter] = Offer({
            nftRarity: _rarity,
            bribeAmount: _bribeAmount,
            offerCreator: msg.sender,
            isActive: true
        });

        // Track offer ID in userOffers
        userOffers[msg.sender].push(offerCounter);

        emit OfferCreated(offerCounter, msg.sender, _rarity, _bribeAmount);
        offerCounter++;
    }

    function acceptOffer(uint256 offerId, uint256 tokenId) external onlyNFTContractOwner(tokenId) {
        Offer storage offer = offers[offerId];
        require(offer.isActive, "Offer is not active");
        require(getRarity(tokenId) == offer.nftRarity, "NFT rarity mismatch");

        // Transfer NFT to offer creator
        nftContract.transferFrom(msg.sender, offer.offerCreator, tokenId);

        // Transfer G-Token and UBA tokens to NFT owner
        require(gToken.transfer(msg.sender, rarityPrices[offer.nftRarity]), "G-Token transfer failed");
        require(ubaToken.transfer(msg.sender, offer.bribeAmount), "UBA token transfer failed");

        // Mark offer as completed
        offer.isActive = false;

        emit OfferAccepted(offerId, msg.sender, tokenId);
    }

    function getOffersByUser(address user) external view returns (Offer[] memory) {
        uint256[] memory offerIds = userOffers[user];
        Offer[] memory userOffersArray = new Offer[](offerIds.length);

        for (uint256 i = 0; i < offerIds.length; i++) {
            userOffersArray[i] = offers[offerIds[i]];
        }

        return userOffersArray;
    }
}
