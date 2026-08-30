// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title MockPunksV1
 * @notice Mock contract for CryptoPunks V1 for testing on Sepolia
 * @dev This is a simplified mock that implements the basic functions needed by PunksV1Wrapper
 */
contract MockPunksV1 {
    // Mapping from punk index to owner address
    mapping(uint256 => address) private _punkIndexToAddress;
    
    // Mapping from owner to balance
    mapping(address => uint256) private _balanceOf;
    
    // Struct for offers
    struct Offer {
        bool isForSale;
        uint256 punkIndex;
        address seller;
        uint256 minValue;
        address onlySellTo;
    }
    
    // Mapping from punk index to offer
    mapping(uint256 => Offer) public punksOfferedForSale;
    
    // Mapping for pending withdrawals
    mapping(address => uint256) public pendingWithdrawals;
    
    // Events
    event Assign(address indexed to, uint256 punkIndex);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event PunkTransfer(address indexed from, address indexed to, uint256 punkIndex);
    event PunkOffered(uint256 indexed punkIndex, uint256 minValue, address indexed toAddress);
    event PunkBought(uint256 indexed punkIndex, uint256 value, address indexed fromAddress, address indexed toAddress);
    event PunkNoLongerForSale(uint256 indexed punkIndex);
    
    /**
     * @notice Transfer a punk to another address
     * @param to The address to transfer to
     * @param punkIndex The punk index to transfer
     */
    function transferPunk(address to, uint256 punkIndex) external {
        require(_punkIndexToAddress[punkIndex] == msg.sender, "Not the owner (transfer punk from mock)");
        require(to != address(0), "Cannot transfer to zero address");
        
        // Cancel any existing offer
        if (punksOfferedForSale[punkIndex].isForSale) {
            punkNoLongerForSale(punkIndex);
        }
        
        address from = _punkIndexToAddress[punkIndex];
        _punkIndexToAddress[punkIndex] = to;
        
        if (from != address(0)) {
            _balanceOf[from]--;
        }
        _balanceOf[to]++;
        
        emit PunkTransfer(from, to, punkIndex);
        emit Transfer(from, to, 1);
    }
    
    /**
     * @notice Get the owner of a punk
     * @param punkIndex The punk index
     * @return The owner address
     */
    function punkIndexToAddress(uint256 punkIndex) external view returns (address) {
        return _punkIndexToAddress[punkIndex];
    }
    
    /**
     * @notice Mint a punk to an address (for testing)
     * @param to The address to mint to
     * @param punkIndex The punk index to mint
     */
    function mintPunk(address to, uint256 punkIndex) external {
        require(_punkIndexToAddress[punkIndex] == address(0), "Punk already exists");
        require(to != address(0), "Cannot mint to zero address");
        
        _punkIndexToAddress[punkIndex] = to;
        _balanceOf[to]++;
        
        emit Assign(to, punkIndex);
        emit Transfer(address(0), to, 1);
    }
    
    /**
     * @notice Get the balance of an address
     * @param owner The owner address
     * @return The balance
     */
    function balanceOf(address owner) external view returns (uint256) {
        return _balanceOf[owner];
    }
    
    /**
     * @notice Transfer a punk from an address to another (for script usage)
     * @param from The address to transfer from
     * @param to The address to transfer to
     * @param punkIndex The punk index to transfer
     * @dev This function allows the script to transfer punks on behalf of the owner
     *      It's used when the script needs to transfer punks that were minted to the deployer
     */
    function transferPunkFrom(address from, address to, uint256 punkIndex) external {
        require(_punkIndexToAddress[punkIndex] == from, "Not the owner (transfer punk from from mock)");
        require(to != address(0), "Cannot transfer to zero address");
        
        _punkIndexToAddress[punkIndex] = to;
        _balanceOf[from]--;
        _balanceOf[to]++;
        
        emit PunkTransfer(from, to, punkIndex);
        emit Transfer(from, to, 1);
    }
    
    /**
     * @notice Offer a punk for sale
     * @param punkIndex The punk index to offer
     * @param minSalePriceInWei The minimum sale price in wei
     */
    function offerPunkForSale(uint256 punkIndex, uint256 minSalePriceInWei) external {
        require(_punkIndexToAddress[punkIndex] == msg.sender, "Not the owner (offer punk for sale from mock)");
        punksOfferedForSale[punkIndex] = Offer(true, punkIndex, msg.sender, minSalePriceInWei, address(0));
        emit PunkOffered(punkIndex, minSalePriceInWei, address(0));
    }
    
    /**
     * @notice Offer a punk for sale to a specific address
     * @param punkIndex The punk index to offer
     * @param minSalePriceInWei The minimum sale price in wei
     * @param toAddress The address to sell to (address(0) means anyone can buy)
     */
    function offerPunkForSaleToAddress(uint256 punkIndex, uint256 minSalePriceInWei, address toAddress) external {
        require(_punkIndexToAddress[punkIndex] == msg.sender, "Not the owner (offer punk for sale to address from mock)");
        punksOfferedForSale[punkIndex] = Offer(true, punkIndex, msg.sender, minSalePriceInWei, toAddress);
        emit PunkOffered(punkIndex, minSalePriceInWei, toAddress);
    }
    
    /**
     * @notice Cancel an offer for sale
     * @param punkIndex The punk index to cancel the offer for
     */
    function punkNoLongerForSale(uint256 punkIndex) public {
        require(_punkIndexToAddress[punkIndex] == msg.sender, "Not the owner (cancel offer for sale from mock)");
        punksOfferedForSale[punkIndex] = Offer(false, punkIndex, msg.sender, 0, address(0));
        emit PunkNoLongerForSale(punkIndex);
    }
    
    /**
     * @notice Buy a punk that is offered for sale
     * @param punkIndex The punk index to buy
     */
    function buyPunk(uint256 punkIndex) external payable {
        Offer storage offer = punksOfferedForSale[punkIndex];
        require(offer.isForSale, "Punk not for sale");
        require(offer.onlySellTo == address(0) || offer.onlySellTo == msg.sender, "Punk not for sale to this address");
        require(msg.value >= offer.minValue, "Insufficient payment");
        require(offer.seller == _punkIndexToAddress[punkIndex], "Seller no longer owner");
        
        address seller = offer.seller;

        // Transfer ownership
        _punkIndexToAddress[punkIndex] = msg.sender;
        _balanceOf[seller]--;
        _balanceOf[msg.sender]++;
        emit Transfer(seller, msg.sender, 1);

        // Cancel the offer
        punkNoLongerForSale(punkIndex);

        // Reproduce the mainnet V1 sale-proceeds bug: in the original contract `offer` is a storage
        // pointer, and punkNoLongerForSale just overwrote `offer.seller` with msg.sender (the buyer),
        // so the BUYER is credited and PunkBought reports the buyer as both parties.
        pendingWithdrawals[msg.sender] += msg.value;

        emit PunkBought(punkIndex, msg.value, msg.sender, msg.sender);
    }

    /**
     * @notice Withdraw pending payments
     * @dev Like mainnet V1: no minimum-amount check, and `transfer` keeps the 2300 gas stipend.
     */
    function withdraw() external {
        uint256 amount = pendingWithdrawals[msg.sender];
        pendingWithdrawals[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }
}

