// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NFTMarketplace is ERC721Enumerable, Ownable, ReentrancyGuard {
    uint256 public listingPrice;
    uint256 public royaltyFeePercentage;

    struct NFTListing {
        address seller;
        uint256 price;
        bool isActive;
    }

    struct Auction {
        address seller;
        uint256 startingPrice;
        uint256 highestBid;
        address highestBidder;
        uint256 endTime;
        bool isActive;
        mapping(address => uint256) bids;
    }

    mapping(uint256 => NFTListing) public nftListings;
    mapping(uint256 => Auction) public nftAuctions;
    uint256 public nftListingCounter;
    uint256 public nftAuctionCounter;

    event NFTListed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event NFTUnlisted(uint256 indexed tokenId, address indexed seller);
    event NFTSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);
    event AuctionStarted(uint256 indexed tokenId, address indexed seller, uint256 startingPrice, uint256 endTime);
    event NewBid(uint256 indexed tokenId, address indexed bidder, uint256 amount);
    event BidWithdrawn(uint256 indexed tokenId, address indexed bidder);
    event AuctionEnded(uint256 indexed tokenId, address indexed winner, uint256 amount);

    constructor(string memory name_, string memory symbol_, uint256 _listingPrice, uint256 _royaltyFeePercentage) ERC721(name_, symbol_) {
        listingPrice = _listingPrice;
        royaltyFeePercentage = _royaltyFeePercentage;
    }

    function listNFT(uint256 _tokenId, uint256 _price) external {
        require(ownerOf(_tokenId) == msg.sender, "You do not own this NFT");
        require(_price > 0, "Price must be greater than zero");

        safeTransferFrom(msg.sender, address(this), _tokenId);

        nftListings[nftListingCounter] = NFTListing({
            seller: msg.sender,
            price: _price,
            isActive: true
        });

        emit NFTListed(_tokenId, msg.sender, _price);
        nftListingCounter++;
    }

    function unlistNFT(uint256 _tokenId) external {
        NFTListing storage listing = nftListings[_tokenId];
        require(msg.sender == listing.seller, "You are not the seller of this NFT");

        safeTransferFrom(address(this), msg.sender, _tokenId);
        delete nftListings[_tokenId];

        emit NFTUnlisted(_tokenId, msg.sender);
    }

    function startAuction(uint256 _tokenId, uint256 _startingPrice, uint256 _duration) external {
        require(ownerOf(_tokenId) == msg.sender, "You do not own this NFT");
        require(_startingPrice > 0, "Starting price must be greater than zero");
        require(_duration > 0, "Auction duration must be greater than zero");

        Auction storage newAuction = nftAuctions[nftAuctionCounter];
        newAuction.seller = msg.sender;
        newAuction.startingPrice = _startingPrice;
        newAuction.highestBid = 0;
        newAuction.highestBidder = address(0);
        newAuction.endTime = block.timestamp + _duration;
        newAuction.isActive = true;

        emit AuctionStarted(_tokenId, msg.sender, _startingPrice, newAuction.endTime);
        nftAuctionCounter++;
    }

    function placeBid(uint256 _tokenId) external payable nonReentrant {
        Auction storage auction = nftAuctions[_tokenId];
        require(auction.isActive, "Auction is not active");
        require(block.timestamp < auction.endTime, "Auction has ended");
        require(msg.value > auction.highestBid, "Bid must be higher than current highest bid");

        if (auction.highestBidder != address(0)) {
            payable(auction.highestBidder).transfer(auction.highestBid);
        }

        auction.bids[msg.sender] = msg.value;
        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;

        emit NewBid(_tokenId, msg.sender, msg.value);
    }

    function withdrawBid(uint256 _tokenId) external nonReentrant {
        Auction storage auction = nftAuctions[_tokenId];
        require(auction.isActive, "Auction is not active");
        require(block.timestamp < auction.endTime, "Auction has ended");

        uint256 bidAmount = auction.bids[msg.sender];
        require(bidAmount > 0, "You have not placed a bid");

        auction.bids[msg.sender] = 0;
        payable(msg.sender).transfer(bidAmount);

        emit BidWithdrawn(_tokenId, msg.sender);
    }

    function endAuction(uint256 _tokenId) external {
        Auction storage auction = nftAuctions[_tokenId];
        require(auction.isActive, "Auction is not active");
        require(block.timestamp >= auction.endTime, "Auction has not ended yet");

        address seller = auction.seller;
        address winner = auction.highestBidder;
        uint256 winningBid = auction.highestBid;

        // Calculate royalty fee
        uint256 royaltyFee = (winningBid * royaltyFeePercentage) / 100;
        uint256 saleProceeds = winningBid - royaltyFee;

        safeTransferFrom(address(this), winner, _tokenId);
        payable(seller).transfer(saleProceeds);
        payable(ownerOf(_tokenId)).transfer(royaltyFee);

        auction.isActive = false;

        emit NFTSold(_tokenId, seller, winner, winningBid);
        emit AuctionEnded(_tokenId, winner, winningBid);
    }

    function setListingPrice(uint256 _price) external onlyOwner {
        listingPrice = _price;
    }

    function setRoyaltyFeePercentage(uint256 _percentage) external onlyOwner {
        require(_percentage <= 100, "Royalty fee percentage cannot exceed 100%");
        royaltyFeePercentage = _percentage;
    }
}