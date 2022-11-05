// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

contract NFTEscrow is UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    struct Escrow {
        address nft;
        uint256 tokenId;
        address payable seller;
        address buyer;
        uint256 amount;
    }

    // 500 = 0.05%
    uint256 constant PROTOCOL_FEE = 500;
    uint256 constant PROTOCOL_FEE_DIVIDER = 1000000;

    address payable treasury;
    uint256 nextEscrowId;

    mapping(address => uint256) sellerToEscrowId;
    mapping(address => uint256) buyerToEscrowId;
    mapping(uint256 => Escrow) escrowIdToEscrow;

    event EscrowCreated(
        address nft,
        uint256 tokenId,
        address seller,
        address buyer,
        uint256 amount
    );
    event EscrowFinalized(
        address nft,
        uint256 tokenId,
        address seller,
        address buyer,
        uint256 amount
    );
    event EscrowCanceled(address nft, uint256 tokenId, address seller);

    function initialize(address payable _treasury) external initializer {
        treasury = _treasury;
        nextEscrowId = 1;

        __ReentrancyGuard_init_unchained();
        __Ownable_init_unchained();
    }

    // seller can create escrow by tranfer NFT to contract
    function createEscrow(address nft, uint256 tokenId, address buyer, uint256 amount) external {
        require(sellerToEscrowId[msg.sender] == 0, 'escrow already exist');

        // seller transfer nft to this contract
        IERC721(nft).transferFrom(msg.sender, address(this), tokenId);

        uint256 escrowId = _getNextEscrowIdAndIncrement();
        sellerToEscrowId[msg.sender] = escrowId;
        buyerToEscrowId[buyer] = escrowId;

        Escrow memory escrow;
        escrow.nft = nft;
        escrow.tokenId = tokenId;
        escrow.seller = payable(msg.sender);
        escrow.buyer = buyer;
        escrow.amount = amount;
        escrowIdToEscrow[escrowId] = escrow;

        emit EscrowCreated(nft, tokenId, msg.sender, buyer, amount);
    }

    // buyer can accept escrow by send tokens to contract
    function finalizeEscrow() external payable nonReentrant {
        uint256 escrowId = buyerToEscrowId[msg.sender];
        require(escrowId != 0, 'escrow not exist');

        Escrow memory escrow = escrowIdToEscrow[escrowId];
        require(msg.value >= escrow.amount);
        // send protocol fee to treasury
        uint256 protocolFee = (escrow.amount * PROTOCOL_FEE) / PROTOCOL_FEE_DIVIDER;
        (bool sendTreasury, ) = treasury.call{ value: protocolFee }('');
        require(sendTreasury, 'fail to send eth');
        // send seller rev to seller
        (bool sendSeller, ) = escrow.seller.call{ value: escrow.amount - protocolFee }('');
        require(sendSeller, 'fail to send eth');
        // refund ecessive amount to buyer
        if (msg.value > escrow.amount) {
            (bool sendBuyer, ) = payable(msg.sender).call{ value: msg.value - escrow.amount }('');
            require(sendBuyer, 'fail to send eth');
        }

        // this contract transfer nft to buyer
        IERC721(escrow.nft).approve(msg.sender, escrow.tokenId);
        IERC721(escrow.nft).transferFrom(address(this), msg.sender, escrow.tokenId);

        // delete escrow data
        delete sellerToEscrowId[escrow.seller];
        delete buyerToEscrowId[msg.sender];
        delete escrowIdToEscrow[escrowId];

        emit EscrowFinalized(
            escrow.nft,
            escrow.tokenId,
            escrow.seller,
            escrow.buyer,
            escrow.amount
        );
    }

    // seller can cancel escrow befor buyer finalize escrow
    function cancelEscrow() external {
        uint256 escrowId = sellerToEscrowId[msg.sender];
        require(escrowId != 0, 'escrow not exist');

        // this contract transfer nft to seller
        Escrow memory escrow = escrowIdToEscrow[escrowId];
        IERC721(escrow.nft).approve(msg.sender, escrow.tokenId);
        IERC721(escrow.nft).transferFrom(address(this), msg.sender, escrow.tokenId);

        delete sellerToEscrowId[msg.sender];
        delete buyerToEscrowId[escrow.buyer];
        delete escrowIdToEscrow[escrowId];

        emit EscrowCanceled(escrow.nft, escrow.tokenId, msg.sender);
    }

    function _getNextEscrowIdAndIncrement() private returns (uint256 escrowId) {
        escrowId = nextEscrowId++;
    }

    // for upgrade by uups format
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
