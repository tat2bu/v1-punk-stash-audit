// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import {IAuction} from './interfaces/IAuction.sol';
import {IWETH} from './interfaces/IWETH.sol';
import {OrderType} from './helpers/Enum.sol';
import {Order, V1PunkBid} from './helpers/V1PunkStruct.sol';
import {MerkleProofLib} from 'lib/solady/src/utils/MerkleProofLib.sol';
import {SignatureCheckerLib} from 'lib/solady/src/utils/SignatureCheckerLib.sol';
import {SafeTransferLib} from 'lib/solady/src/utils/SafeTransferLib.sol';
import {IERC721} from 'lib/forge-std/src/interfaces/IERC721.sol';
import {IERC1155} from 'lib/forge-std/src/interfaces/IERC1155.sol';
import {IERC20} from 'lib/forge-std/src/interfaces/IERC20.sol';
import {IWrappedPunksV1} from './interfaces/IWrappedPunksV1.sol';
import {IWrappedPunksMarketplace} from './interfaces/IWrappedPunksMarketplace.sol';
import {IV1PunkStashFactory} from './interfaces/IV1PunkStashFactory.sol';
import {PunksV1Contract} from './interfaces/PunksV1Contract.sol';

/**
 * @title V1PunkStash
 * @author Cryptopunks.eth.limo
 */
contract V1PunkStash {
  // --------------------- STASH EVENTS ---------------------

  /// @dev Emitted when an order is placed.
  event OrderPlaced(Order order);

  /// @dev Emitted when an order is updated.
  event OrderUpdated(Order originalOrder, Order updatedOrder);

  /// @dev Emitted when an order is removed, either because it was filled or the auction was finalized.
  event OrderRemoved(Order order);

  /// @dev Emitted when an ERC721 bid is canceled.
  event V1PunkBidCanceled(uint256 indexed bidNonce);

  /// @dev Emitted when the Stash's global nonce is incremented, canceling all ERC721 bids.
  event AllV1PunkBidsCanceled();

  /// @dev Emitted when an ERC721 bid is accepted.
  event V1PunkBidAccepted(uint256 indexed price, uint256 indexed tokenId);

  // --------------------- CUSTOM ERRORS ---------------------

  /// @dev The ERC721 bid has expired.
  error BidExpired();

  /// @dev The bid either has zero units or does not include the ERC721 token address.
  error InvalidBid();

  /// @dev The bid has been used or canceled.
  error BidCanceled();

  /// @dev The caller is not authorized to perform this action.
  error Unauthorized();

  /// @dev The order does not exist. It may have been filled, canceled, or never existed.
  error OrderNotFound();

  /// @dev The merkle proof provided does not match the ERC721 Bid.
  error InvalidProof();

  /// @dev The vault already has 10 orders for the given payment token.
  error TooManyOrders();

  /// @dev The order type is not supported by the Stash.
  error UnknownOrderType();

  /// @dev The ERC721 token could not be purchased or transferred.
  error FailedToBuyToken();

  /// @dev This Stash does not have an active bid on the auction that is attempting to process the order.
  error NoBidForAuction();

  /// @dev The provided signature does not match the provided ERC721 bid.
  error InvalidSignature();

  /// @dev The caller is not a valid auction contract, as determined by the StashFactory.
  error CallerNotAuction();

  /// @dev Payment to the Stash owner failed.
  error FailedToWithdraw();

  /// @dev The Stash has already been initialized.
  error AlreadyInitialized();

  /// @dev The order is being altered in a way that is not allowed by the order type.
  error InvalidOrderAlteration();

  /// @dev An order or withdrawal is being requested for an amount that exceeds the available balance.
  error RequestExceedsAvailableBalance();

  /// @dev An auction is attempting to pull more funds than the Stash owner has approved from the Stash.
  error CannotTransferMoreThanBidAmount();

  // --------------------- MODIFIERS ---------------------

  modifier onlyOwner() {
    if (msg.sender != owner) revert Unauthorized();
    _;
  }

  // ----------------- CONSTANTS & IMMUTABLES -----------------

  uint256 private constant _VERSION = 4;
  bytes32 private constant _COLLECTION_BID_ROOT = bytes32(0);
  bytes32 private constant _ORDER_TYPEHASH =
    keccak256('Order(uint16 numberOfUnits,uint80 pricePerUnit,address auction)');
  bytes32 private constant _ERC721_BID_TYPEHASH =
    keccak256(
      'V1PunkBid(Order order,uint256 accountNonce,uint256 bidNonce,uint256 expiration,bytes32 root)Order(uint16 numberOfUnits,uint80 pricePerUnit,address auction)'
    );

  IERC721 private immutable _ERC721_TOKEN;
  IWrappedPunksV1 private immutable _WRAPPED_PUNKS_V1;
  IWrappedPunksMarketplace private immutable _WRAPPED_PUNKS_MARKETPLACE;
  IWETH private immutable _WETH;
  IV1PunkStashFactory private immutable _STASH_FACTORY;
  PunksV1Contract private immutable _PUNKS_V1_CONTRACT;

  // -------------------- CONSTRUCTOR --------------------

  constructor(
    address stashFactory,
    address weth,
    address wrappedPunksV1,
    address punksV1Contract,
    address wrappedPunksMarketplace
  ) {
    _STASH_FACTORY = IV1PunkStashFactory(stashFactory);
    _WETH = IWETH(weth);
    // WPV1 is both the ERC721 token and the wrapper
    _WRAPPED_PUNKS_V1 = IWrappedPunksV1(wrappedPunksV1);
    _ERC721_TOKEN = IERC721(wrappedPunksV1);
    _PUNKS_V1_CONTRACT = PunksV1Contract(punksV1Contract);
    _WRAPPED_PUNKS_MARKETPLACE = IWrappedPunksMarketplace(wrappedPunksMarketplace);
    _initialized = true;
  }

  // --------------------- STORAGE ---------------------

  /// @dev Whether or not the contract has been initialized.
  bool private _initialized;

  /// @notice The permanent and immutable owner of the stash. Set once at initialization.
  address public owner;

  /// @notice The current nonce of the stash owner's account. Used for ERC721 bidding, can be incremented to cancel all open bids.
  uint56 public erc721AccountNonce;

  /// @notice A mapping of ERC721 bid nonces to the number of times they can be used.
  mapping(uint256 v1PunkBidNonce => uint256 usesRemaining) public v1PunkBidNonceUsesRemaining;

  /// @notice A mapping of ERC721 bid nonces to whether or not they have been used.
  mapping(uint256 v1PunkBidNonce => bool isUsed) public usedV1PunkBidNonces;

  /// @notice Returns an array of all current orders for a given payment token.
  mapping(address paymentToken => Order[] orders) public paymentTokenToOrders;

  // --------------------- EXTERNAL ---------------------

  // allow receiving ETH.
  receive() external payable {}

  /**
   * @notice Initializes the contract. This is called only once upon deployment by the StashFactory.
   * @param _owner The permanent and immutable owner of the stash.
   */
  function initialize(address _owner) external {
    if (_initialized) revert AlreadyInitialized();

    owner = _owner;
    _initialized = true;
  }

  /**
   * @notice Places an order for an auction. If one exists, it will be replaced or incremented depending on the order type.
   * @param pricePerUnit The price per unit of the order.
   * @param numberOfUnits The number of units included in the order.
   * @dev The stash owner must initiate this transaction by calling the corresponding bid function on a valid auction contract.
   */
  function placeOrder(uint80 pricePerUnit, uint16 numberOfUnits) external payable {
    // Prevent unwanted bids by enforcing that the user initiated the transaction and that the caller is a registered auction.
    if (tx.origin != owner) revert Unauthorized();
    if (!_STASH_FACTORY.isAuction(msg.sender)) revert CallerNotAuction();

    (address paymentToken, OrderType orderType) = IAuction(msg.sender).bidConfig();

    uint256 paymentTokenBalance = _balanceOfToken(paymentToken);
    (uint256 lockedAmount, uint256 finalizedIndexes) = _totalLockedAndStaleBids(paymentToken);

    uint256 _availableLiquidity;
    unchecked {
      // Locked amount cannot exceed paymentTokenBalance.
      _availableLiquidity = paymentTokenBalance - lockedAmount;
    }

    _cleanStaleBids(paymentToken, finalizedIndexes);

    Order memory newOrder = Order(numberOfUnits, pricePerUnit, msg.sender);

    Order[] storage _orders = paymentTokenToOrders[paymentToken];

    for (uint256 i = 0; i < _orders.length; ++i) {
      Order storage _order = _orders[i];
      if (_order.auction == msg.sender) {
        // cache the existing order to emit an event later.
        Order memory existingOrder = _order;

        // This will check that the stash has funds to cover the order, and modify the existing order in place.
        _replaceOrIncrementExistingOrders(_order, numberOfUnits, pricePerUnit, _availableLiquidity, orderType);

        emit OrderUpdated(existingOrder, _order);

        return;
      }
    }

    if (_bidDeltaExceedsLiquidity(0, uint256(numberOfUnits) * pricePerUnit, _availableLiquidity)) {
      revert RequestExceedsAvailableBalance();
    }

    _orders.push(newOrder);

    /**
     * Limit the number of orders to 10 to prevent gas issues. Realistically, there will only ever be one order
     * per payment token at a time. This is just a safety measure.
     */
    if (_orders.length > 10) revert TooManyOrders();

    emit OrderPlaced(newOrder);
  }

  /**
   * @notice Processes an order for a given auction, transferring payment to the auction contract.
   * @param costPerUnit The cost per unit of the order.
   * @param numberOfUnits The number of units to process.
   * @dev This function is called by the auction contract, which should handle minting corresponding units
   * as part of the transaction. The order's numberOfUnits will be lowered by numberOfUnits, and the order will be
   * removed if numberOfUnits is equal to the order's numberOfUnits.
   */
  function processOrder(uint80 costPerUnit, uint16 numberOfUnits) external {
    if (!_STASH_FACTORY.isAuction(msg.sender)) revert CallerNotAuction();
    (address paymentToken, ) = IAuction(msg.sender).bidConfig();

    Order[] storage _orders = paymentTokenToOrders[paymentToken];
    for (uint256 i = 0; i < _orders.length; ) {
      Order storage _order = _orders[i];
      if (_order.auction == msg.sender) {
        if (costPerUnit > _order.pricePerUnit || numberOfUnits > _order.numberOfUnits) {
          revert CannotTransferMoreThanBidAmount();
        }

        if (numberOfUnits == _order.numberOfUnits) {
          _removeBid(paymentToken, i);
        } else {
          // cache the existing order to emit an event later.
          Order memory _originalOrder = _order;

          unchecked {
            _order.numberOfUnits -= numberOfUnits;
          }

          emit OrderUpdated(_originalOrder, _order);
        }

        _transferTokens(paymentToken, uint256(numberOfUnits) * costPerUnit);
        return;
      } else {
        unchecked {
          ++i;
        }
      }
    }

    revert NoBidForAuction();
  }

  /**
   * @notice Allows selling an ERC721 token to the stash. A valid signature from the stash owner is required for successful execution.
   * @param bid The bid that was signed off-chain.
   * @param tokenId The id of the token to sell. Must be included in the bid's merkle tree.
   * @param signature The signed bid.
   * @param proof The merkle proof for the tokenId.
   * @dev This function will revert if the bid is invalid, expired, or canceled. It will also revert if the bid
   * does not contain the tokenId in its merkle tree. If the bid is valid, the token will be transferred to the stash
   * owner and the bid's numberOfUnits will be decremented. If numberOfUnits is 1, the bid will be marked as used.
   *
   * **Wrapped WPV1 path (v4):** The seller must list the wrapped punk on FrankPoncelet's WPV1 marketplace
   * (`_WRAPPED_PUNKS_MARKETPLACE`) at `minValue == bidPrice`, directed exclusively to this stash. The stash then
   * calls `marketplace.buyPunk{value: bidPrice}`, which pays the seller directly, transfers the WPV1 ERC721 token
   * to the stash via `safeTransferFrom`, and emits a `PunkBought` event at the real sale price. The stash then
   * forwards the WPV1 token to `owner`.
   *
   * **Unwrapped V1 path:** The seller must list at `minValue == bidPrice`, directed to this stash, on the native
   * V1 contract. The stash calls `buyPunk{value: bidPrice}` so the native contract records a PunkBought event at
   * the real sale price. The V1 sale-proceeds bug (`punkNoLongerForSale` overwrites the offer's seller before it
   * is credited) credits `pendingWithdrawals` to the buyer — this stash — so the stash immediately recovers the
   * ETH with `withdraw()` and pays the seller directly. Native custody is forwarded to `owner` with `transferPunk`.
   */
  function processV1PunkBid(
    V1PunkBid calldata bid,
    uint256 tokenId,
    bytes memory signature,
    bytes32[] calldata proof
  ) external {
    uint256 availableETH = availableLiquidity(address(0));

    Order calldata order = bid.order;
    uint256 bidPrice = order.pricePerUnit;

    if (order.numberOfUnits == 0) revert InvalidBid();
    if (order.auction != address(_WRAPPED_PUNKS_V1)) revert InvalidBid();
    if (erc721AccountNonce != bid.accountNonce) revert BidCanceled();
    if (usedV1PunkBidNonces[bid.bidNonce]) revert BidCanceled();
    if (bid.expiration > 0 && block.timestamp > bid.expiration) revert BidExpired();
    if (!_isValidSignature(bid, signature)) revert InvalidSignature();

    if (bid.root != _COLLECTION_BID_ROOT) {
      if (!MerkleProofLib.verifyCalldata(proof, bid.root, keccak256(abi.encode(tokenId)))) {
        revert InvalidProof();
      }
    }

    // if balance is too low, we try to use owner's approved weth to supplement.
    if (bidPrice > availableETH) {
      _swapWETH(bidPrice - availableETH);
    }

    uint256 remainingUnits = v1PunkBidNonceUsesRemaining[bid.bidNonce];

    // we have already checked if the nonce is marked as used, so if remainingUnits is 0, this is the first use.
    if (remainingUnits == 0) {
      if (order.numberOfUnits == 1) {
        usedV1PunkBidNonces[bid.bidNonce] = true;
      } else {
        unchecked {
          v1PunkBidNonceUsesRemaining[bid.bidNonce] = order.numberOfUnits - 1;
        }
      }
      // If remainingUnits is greater than 1, decrement it.
    } else if (remainingUnits > 1) {
      unchecked {
        --v1PunkBidNonceUsesRemaining[bid.bidNonce];
      }
      // remainingUnits is 1 - this is the last use, so mark the nonce as used.
    } else {
      delete v1PunkBidNonceUsesRemaining[bid.bidNonce];
      usedV1PunkBidNonces[bid.bidNonce] = true;
    }

    // Check if the punk is wrapped or not
    if (_isPunkWrapped(tokenId)) {
      // Wrapped punk: buy through FrankPoncelet's WPV1 marketplace so the marketplace records
      // a PunkBought event at the real sale price and pays the seller directly.

      // Verify that msg.sender owns the wrapped token
      address tokenOwner = _ERC721_TOKEN.ownerOf(tokenId);
      if (tokenOwner != msg.sender) {
        revert Unauthorized();
      }

      // Verify the listing on the wrapped marketplace
      IWrappedPunksMarketplace.Offer memory offer = _WRAPPED_PUNKS_MARKETPLACE.getOffer(tokenId);
      if (!offer.isForSale || offer.seller != msg.sender) {
        revert InvalidBid();
      }
      // The listing must be directed to this stash only, so nobody else can buy it while it is live
      if (offer.onlySellTo != address(this)) {
        revert InvalidBid();
      }
      // The listing price must equal the bid price, so the recorded PunkBought amount is the real one
      if (offer.minValue != bidPrice) {
        revert InvalidBid();
      }

      // Buy through the marketplace: this pays the seller directly via _withdraw(seller, msg.value),
      // transfers the WPV1 ERC721 to this stash via safeTransferFrom, and emits PunkBought at the real price.
      _WRAPPED_PUNKS_MARKETPLACE.buyPunk{value: bidPrice}(tokenId);

      // Forward the WPV1 token to the stash owner (bidder)
      _WRAPPED_PUNKS_V1.transferFrom(address(this), owner, tokenId);
    } else {
      // Unwrapped punk: buy at the real bid price on the V1 market so the native contract records the
      // true sale amount, then deliver native custody to the stash owner (no WPV1 wrap).
      // Verify that msg.sender is the owner
      if (_PUNKS_V1_CONTRACT.punkIndexToAddress(tokenId) != msg.sender) {
        revert Unauthorized();
      }

      (bool isForSale, , address listingSeller, uint minValue, address onlySellTo) = _PUNKS_V1_CONTRACT
        .punksOfferedForSale(tokenId);
      if (!isForSale || listingSeller != msg.sender) {
        revert InvalidBid();
      }
      // The listing must be directed to this stash only, so nobody else can buy it while it is live
      if (onlySellTo != address(this)) {
        revert InvalidBid();
      }
      // The listing price must equal the bid price, so the recorded PunkBought amount is the real one
      if (minValue != bidPrice) {
        revert InvalidBid();
      }

      // Buy the punk at the bid price - this transfers it from the seller to this stash
      _PUNKS_V1_CONTRACT.buyPunk{value: bidPrice}(tokenId);

      // The V1 bug credits msg.value to the buyer (this stash) instead of the seller: recover it,
      // the seller is paid directly below.
      _PUNKS_V1_CONTRACT.withdraw();

      // Forward native V1 ownership to the stash owner (bidder)
      _PUNKS_V1_CONTRACT.transferPunk(owner, tokenId);

      // Pay the caller (seller) the bid price.
      // For the wrapped path the marketplace already paid the seller during buyPunk(), so no payment here.
      if (bidPrice > 0) {
        (bool callerPaid, ) = payable(msg.sender).call{value: bidPrice}('');
        if (!callerPaid) revert FailedToBuyToken();
      }
    }

    emit V1PunkBidAccepted(bidPrice, tokenId);
  }

  /**
   * @notice Cancels a bid.
   * @param bidNonce The nonce of the bid to cancel.
   */
  function cancelV1PunkBid(uint256 bidNonce) external onlyOwner {
    usedV1PunkBidNonces[bidNonce] = true;

    emit V1PunkBidCanceled(bidNonce);
  }

  /**
   * @notice increments the global account nonce, canceling all existing offchain bids.
   * @dev a very motivated stash owner could overflow their nonce, but there would be no benefit to doing so.
   */
  function cancelAllV1PunkBids() external onlyOwner {
    unchecked {
      ++erc721AccountNonce;
    }

    emit AllV1PunkBidsCanceled();
  }

  // --------------------- WITHDRAWALS ---------------------

  /**
   * @notice Used by the WPV1 contract to wrap tokens. Tokens must be deposited to the Stash for wrapping.
   * @dev For WPV1, wrapping requires the original punk to be transferred to the WPV1 contract first
   * This function is called by WPV1 after receiving the punk
   */
  function wrapToken(uint256) external view {
    if (msg.sender != address(_WRAPPED_PUNKS_V1)) revert Unauthorized();

    // For WPV1, wrapping is done by the WPV1 contract itself
    // The punk must already be transferred to the WPV1 contract
    // This function is just a callback to confirm the stash received the wrapped token
  }

  /**
   * @notice withdraws funds from the stash.
   * @param tokenAddress The address of the token to withdraw. Zero address for ETH.
   * @param amount The amount to withdraw in wei.
   * @dev This function allows withdrawal of funds that are not committed to an active bid. It will also
   * clean up any stale bids that have been finalized or expired.
   */
  function withdraw(address tokenAddress, uint256 amount) external onlyOwner {
    (uint256 _lockedAmount, uint256 finalizedIndexes) = _totalLockedAndStaleBids(tokenAddress);

    uint256 tokenBalance = _balanceOfToken(tokenAddress);

    uint256 availableToWithdraw = tokenBalance - _lockedAmount;
    if (amount > availableToWithdraw) revert RequestExceedsAvailableBalance();

    _cleanStaleBids(tokenAddress, finalizedIndexes);

    _transferTokens(tokenAddress, amount);
  }

  /**
   * @notice Convenience function to withdraw ERC721 tokens from the stash.
   * @param tokenAddress The address of the token to withdraw.
   * @param tokenIds An array of token IDs to withdraw.
   */
  function withdrawERC721(address tokenAddress, uint256[] calldata tokenIds) external onlyOwner {
    IERC721 tokenContract = IERC721(tokenAddress);

    for (uint256 i = 0; i < tokenIds.length; ++i) {
      tokenContract.transferFrom(address(this), owner, tokenIds[i]);
    }
  }

  /**
   * @notice Convenience function to withdraw ERC1155 tokens from the stash.
   * @param tokenAddress The address of the token to withdraw.
   * @param tokenIds An array of token IDs to withdraw.
   * @param amounts An array of amounts to withdraw.
   */
  function withdrawERC1155(
    address tokenAddress,
    uint256[] calldata tokenIds,
    uint256[] calldata amounts
  ) external onlyOwner {
    IERC1155 tokenContract = IERC1155(tokenAddress);

    for (uint256 i = 0; i < tokenIds.length; ++i) {
      tokenContract.safeTransferFrom(address(this), owner, tokenIds[i], amounts[i], '');
    }
  }

  // --------------------- VIEW ---------------------

  /**
   * @notice Fetches a bid corresponding to an auction.
   * @param auction The address of the auction to fetch a bid for.
   * @return bid The bid corresponding to the auction.
   */
  function getOrder(address auction) external view returns (Order memory) {
    (address paymentToken, ) = IAuction(auction).bidConfig();
    Order[] storage _orders = paymentTokenToOrders[paymentToken];

    for (uint256 i = 0; i < _orders.length; ++i) {
      Order storage bid = _orders[i];
      if (bid.auction == auction) {
        if (!IAuction(bid.auction).finalized()) {
          return bid;
        } else {
          // If the auction is finalized, the bid is invalid.
          revert OrderNotFound();
        }
      }
    }

    revert OrderNotFound();
  }

  /**
   * @notice Fetches the total amount of locked funds for a given token.
   * @param tokenAddress The address of the token to fetch the locked amount for. Zero address for ETH.
   */
  function totalLocked(address tokenAddress) external view returns (uint256 lockedAmount) {
    (lockedAmount, ) = _totalLockedAndStaleBids(tokenAddress);
  }

  /**
   * @notice Fetches the total amount of available funds for a given token.
   * @param tokenAddress The address of the token to fetch the available amount for. Zero address for ETH.
   */
  function availableLiquidity(address tokenAddress) public view returns (uint256 availableAmount) {
    uint256 tokenBalance = _balanceOfToken(tokenAddress);
    (uint256 lockedAmount, ) = _totalLockedAndStaleBids(tokenAddress);
    availableAmount = tokenBalance - lockedAmount;
  }

  /**
   * @notice convenience function that returns the total amount of useable ETH and WETH.
   * @return availableAmount The total amount of useable ETH and WETH.
   */
  function availableLiquidityWETHAndETH() public view returns (uint256 availableAmount) {
    uint256 wethHeldByOwner = _WETH.balanceOf(owner);
    uint256 wethApprovedByOwner = _WETH.allowance(owner, address(this));
    uint256 availableWETH = wethHeldByOwner > wethApprovedByOwner ? wethApprovedByOwner : wethHeldByOwner;

    availableAmount = availableWETH + availableLiquidity(address(_WETH)) + availableLiquidity(address(0));
  }

  /**
   * @notice Returns the current version of this particular Stash.
   * @return _VERSION The current version of this Stash.
   */
  function version() external pure returns (uint256) {
    return _VERSION;
  }

  // --------------------- ERC165 ---------------------

  function onERC1155Received(address, address, uint256, uint256, bytes memory) public virtual returns (bytes4) {
    return this.onERC1155Received.selector;
  }

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] memory,
    uint256[] memory,
    bytes memory
  ) public virtual returns (bytes4) {
    return this.onERC1155BatchReceived.selector;
  }

  function onERC721Received(address, address, uint256, bytes memory) public virtual returns (bytes4) {
    return this.onERC721Received.selector;
  }

  // --------------------- INTERNAL ---------------------

  function _transferTokens(address tokenAddress, uint256 amount) internal {
    if (tokenAddress == address(0)) {
      (bool success, ) = payable(msg.sender).call{value: amount}('');
      if (!success) revert FailedToWithdraw();
    } else {
      SafeTransferLib.safeTransfer(tokenAddress, msg.sender, amount);
    }
  }

  function _replaceOrIncrementExistingOrders(
    Order storage existingOrder,
    uint16 updatedNumberOfUnits,
    uint80 updatedPricePerUnit,
    uint256 _availableLiquidity,
    OrderType _type
  ) internal {
    if (_type == OrderType.UNREPLACEABLE) revert InvalidOrderAlteration();

    uint16 newTotalNumberOfUnits;

    if (_type == OrderType.SUBSEQUENT_BIDS_REPLACE_EXISTING_PRICE_INCREASE_REQUIRED) {
      if (existingOrder.pricePerUnit >= updatedPricePerUnit) {
        revert InvalidOrderAlteration();
      } else {
        // `numberOfUnits` is allowed to decrease as long as `pricePerUnit` increases.
        newTotalNumberOfUnits = updatedNumberOfUnits;
      }
    } else if (_type == OrderType.SUBSEQUENT_BIDS_OVERWRITE_PRICE_AND_ADD_UNITS) {
      newTotalNumberOfUnits = existingOrder.numberOfUnits + updatedNumberOfUnits;
    } else {
      revert UnknownOrderType();
    }

    if (
      _bidDeltaExceedsLiquidity(
        uint256(existingOrder.numberOfUnits) * existingOrder.pricePerUnit,
        uint256(newTotalNumberOfUnits) * updatedPricePerUnit,
        _availableLiquidity
      )
    ) revert RequestExceedsAvailableBalance();

    existingOrder.numberOfUnits = newTotalNumberOfUnits;
    existingOrder.pricePerUnit = updatedPricePerUnit;
  }

  // internal helpers
  function _swapWETH(uint256 wethAmount) internal {
    uint256 availableBalance = availableLiquidity(address(_WETH));

    // if existing balance is high enough just withdraw it and return early.
    if (availableBalance >= wethAmount) {
      _WETH.withdraw(wethAmount);
      return;
    }

    uint256 amountToTransfer = wethAmount;
    // if existing balance is not high enough but greater than 0, decrement the amount needed by the existing balance.
    if (availableBalance > 0 && availableBalance < wethAmount) {
      unchecked {
        amountToTransfer -= availableBalance;
      }
    }
    // Canonical WETH9 reverts on failure, but use SafeTransferLib so the transfer
    // result is explicitly checked (and to support any ERC20-compliant WETH deployment).
    SafeTransferLib.safeTransferFrom(address(_WETH), owner, address(this), amountToTransfer);
    _WETH.withdraw(wethAmount);
  }

  // --------------------- INTERNAL VIEW ---------------------

  /**
   * @notice Check if a punk is wrapped
   * @param tokenId The token ID to check
   * @return True if the punk is wrapped, false otherwise
   */
  function _isPunkWrapped(uint256 tokenId) internal view returns (bool) {
    return _WRAPPED_PUNKS_V1.exists(tokenId);
  }

  function _isValidSignature(V1PunkBid calldata bid, bytes memory signature) internal view returns (bool) {
    Order calldata order = bid.order;

    bytes32 hashStruct = keccak256(
      abi.encode(
        _ERC721_BID_TYPEHASH,
        keccak256(abi.encode(_ORDER_TYPEHASH, order.numberOfUnits, order.pricePerUnit, order.auction)),
        bid.accountNonce,
        bid.bidNonce,
        bid.expiration,
        bid.root
      )
    );

    bytes32 _domainHash = keccak256(
      abi.encode(keccak256('EIP712Domain(uint256 chainId,address verifyingContract)'), block.chainid, address(this))
    );
    bytes32 hash = keccak256(abi.encodePacked('\x19\x01', _domainHash, hashStruct));

    // This lib does not include a malleability check, however, the bidNonce will prevent signature reuse.
    return SignatureCheckerLib.isValidSignatureNow(owner, hash, signature);
  }

  function _totalAmountBid(Order storage _order) internal view returns (uint256) {
    return uint256(_order.numberOfUnits) * _order.pricePerUnit;
  }

  function _balanceOfToken(address tokenAddress) internal view returns (uint256) {
    if (tokenAddress == address(0)) {
      return address(this).balance;
    } else {
      return IERC20(tokenAddress).balanceOf(address(this));
    }
  }

  function _totalLockedAndStaleBids(
    address tokenAddress
  ) internal view returns (uint256 _lockedAmount, uint256 finalizedIndexes) {
    Order[] storage _orders = paymentTokenToOrders[tokenAddress];

    for (uint256 i = 0; i < _orders.length; ++i) {
      Order storage order = _orders[i];
      IAuction auction = IAuction(order.auction);

      if (auction.finalized()) {
        finalizedIndexes = finalizedIndexes | (1 << i);
      } else {
        (address paymentToken, ) = auction.bidConfig();
        if (tokenAddress == paymentToken) {
          unchecked {
            _lockedAmount += _totalAmountBid(order);
          }
        }
      }
    }
  }

  function _cleanStaleBids(address tokenAddress, uint256 finalizedIndexes) internal {
    Order[] storage _orders = paymentTokenToOrders[tokenAddress];

    // If there are no bids to process, exit early.
    if (_orders.length == 0) return;

    // Otherwise, use a while loop to iterate and clean up stale bids.
    uint256 i = _orders.length;

    while (i > 0) {
      unchecked {
        --i;
      }
      if ((finalizedIndexes & (1 << i)) != 0) {
        _removeBid(tokenAddress, i);
        // If the last bid is removed, break out of the loop.
        if (_orders.length == 0) break;
      }
    }
  }

  function _removeBid(address _key, uint256 _bidIndex) internal {
    Order[] storage _orders = paymentTokenToOrders[_key];
    Order memory orderToRemove = _orders[_bidIndex];

    if (_bidIndex != _orders.length - 1) {
      _orders[_bidIndex] = _orders[_orders.length - 1];
    }
    _orders.pop();

    emit OrderRemoved(orderToRemove);
  }

  function _bidDeltaExceedsLiquidity(
    uint256 existingTotal,
    uint256 newTotal,
    uint256 _availableLiquidity
  ) internal pure returns (bool) {
    if (newTotal > existingTotal && newTotal - existingTotal > _availableLiquidity) {
      return true;
    }

    return false;
  }
}

