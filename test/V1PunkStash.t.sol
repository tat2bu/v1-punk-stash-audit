// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {V1PunkStash} from "src/V1PunkStash.sol";
import {V1PunkStashFactory} from "src/V1PunkStashFactory.sol";
import {IV1PunkStash} from "src/interfaces/IV1PunkStash.sol";
import {V1PunkBid, Order} from "src/helpers/V1PunkStruct.sol";
import {MockPunksV1} from "src/mocks/MockPunksV1.sol";
import {StashImplementationPlaceholderV1} from "src/mocks/StashImplementationPlaceholderV1.sol";
import {StashImplementationPlaceholderV2} from "src/mocks/StashImplementationPlaceholderV2.sol";
import {StashImplementationPlaceholderV3} from "src/mocks/StashImplementationPlaceholderV3.sol";
import {MockWPV1Minimal} from "./mocks/MockWPV1Minimal.sol";
import {MockWPV1Full} from "./mocks/MockWPV1Full.sol";
import {MockWETH9} from "./mocks/MockWETH9.sol";
import {MockWrappedPunksMarketplace} from "./mocks/MockWrappedPunksMarketplace.sol";

contract V1PunkStashTest is Test {
    V1PunkStashFactory public factory;
    V1PunkStash public implementation;

    address public constant WETH_PLACEHOLDER = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant WRAPPED_PUNKS_V1 = address(0xEe9528924Be9b46b85205caadC6851926F81bd95);
    address public constant PUNKS_V1_CONTRACT = address(0x0E12369b6b33411f3eC37D29C1Ba6d821262Fb5f);
    address public constant WRAPPED_MARKETPLACE = address(0x759c6C1923910930C18ef490B3c3DbeFf24003cE);

    address public owner = address(0x1111);
    address public user = address(0x2222);

    bytes32 private constant ORDER_TYPEHASH =
        keccak256("Order(uint16 numberOfUnits,uint80 pricePerUnit,address auction)");
    bytes32 private constant ERC721_BID_TYPEHASH = keccak256(
        "V1PunkBid(Order order,uint256 accountNonce,uint256 bidNonce,uint256 expiration,bytes32 root)Order(uint16 numberOfUnits,uint80 pricePerUnit,address auction)"
    );

    event PunkBought(uint256 indexed punkIndex, uint256 value, address indexed fromAddress, address indexed toAddress);

    struct UnwrappedScenario {
        address stashAddr;
        address stashOwnerAddr;
        address seller;
        uint256 tokenId;
        uint256 bidPrice;
        MockPunksV1 punks;
        V1PunkBid bid;
        bytes signature;
    }

    struct WrappedScenario {
        address stashAddr;
        address stashOwnerAddr;
        address seller;
        uint256 tokenId;
        uint256 bidPrice;
        MockWPV1Full wpv1;
        MockWrappedPunksMarketplace marketplace;
        V1PunkBid bid;
        bytes signature;
    }

    function setUp() public {
        factory = new V1PunkStashFactory(address(0));

        vm.startPrank(factory.owner());
        factory.addVersion(address(new StashImplementationPlaceholderV1()));
        factory.addVersion(address(new StashImplementationPlaceholderV2()));
        factory.addVersion(address(new StashImplementationPlaceholderV3()));

        implementation = new V1PunkStash(
            address(factory),
            WETH_PLACEHOLDER,
            WRAPPED_PUNKS_V1,
            PUNKS_V1_CONTRACT,
            WRAPPED_MARKETPLACE
        );

        factory.addVersion(address(implementation));
        vm.stopPrank();
    }

    // ===================== DEPLOY & VERSION TESTS =====================

    function test_DeployStash() public {
        address predictedAddress = factory.stashAddressFor(owner);

        address deployedAddress = factory.deployStash(owner);

        assertEq(deployedAddress, predictedAddress, "Deployed address should match predicted address");

        IV1PunkStash stash = IV1PunkStash(payable(deployedAddress));
        assertEq(stash.owner(), owner, "Stash owner should be set correctly");
        assertEq(stash.version(), 4, "Stash version should be 4");
    }

    function test_DeployStashTwiceReverts() public {
        factory.deployStash(owner);

        vm.expectRevert(V1PunkStashFactory.AlreadyDeployed.selector);
        factory.deployStash(owner);
    }

    function test_StashAddressFor() public view {
        address predictedAddress = factory.stashAddressFor(owner);

        address predictedAddress2 = factory.stashAddressFor(owner);
        assertEq(predictedAddress, predictedAddress2, "Predicted address should be deterministic");

        address predictedAddress3 = factory.stashAddressFor(user);
        assertNotEq(predictedAddress, predictedAddress3, "Different owners should have different addresses");
    }

    function test_OwnerHasDeployed() public {
        assertFalse(factory.ownerHasDeployed(owner), "Owner should not have deployed stash yet");

        factory.deployStash(owner);

        assertTrue(factory.ownerHasDeployed(owner), "Owner should have deployed stash");
    }

    function test_Version() public view {
        assertEq(implementation.version(), 4, "Implementation version should be 4");
    }

    // ===================== UNWRAPPED V1 TESTS (unchanged from v3) =====================

    /// @dev Unwrapped V1 path: the seller lists at the bid price directed to the stash, the stash buys at
    /// that price (so the native contract records the real amount), recovers the buyer-credited proceeds
    /// with withdraw(), pays the seller from its own balance and forwards native custody to its owner.
    function test_ProcessV1PunkBid_unwrapped_buys_at_bid_price_and_delivers_native() public {
        UnwrappedScenario memory s = _setupUnwrappedScenario();

        vm.prank(s.seller);
        s.punks.offerPunkForSaleToAddress(s.tokenId, s.bidPrice, s.stashAddr);

        uint256 sellerBalBefore = s.seller.balance;
        uint256 stashBalBefore = s.stashAddr.balance;

        // The native market must record the sale at the real bid price. Due to the V1 storage-aliasing
        // bug, PunkBought reports the buyer (the stash) as both parties.
        vm.expectEmit(true, true, true, true, address(s.punks));
        emit PunkBought(s.tokenId, s.bidPrice, s.stashAddr, s.stashAddr);

        vm.prank(s.seller);
        V1PunkStash(payable(s.stashAddr)).processV1PunkBid(s.bid, s.tokenId, s.signature, new bytes32[](0));

        assertEq(s.punks.punkIndexToAddress(s.tokenId), s.stashOwnerAddr, "native owner");
        assertEq(s.seller.balance, sellerBalBefore + s.bidPrice, "seller paid from stash");
        assertEq(s.stashAddr.balance, stashBalBefore - s.bidPrice, "stash spent exactly the bid price");
        assertEq(s.punks.pendingWithdrawals(s.stashAddr), 0, "no ETH left in native pendingWithdrawals");
        assertEq(address(s.punks).balance, 0, "no ETH stuck in native contract");
    }

    function test_ProcessV1PunkBid_unwrapped_reverts_when_listing_price_mismatch() public {
        UnwrappedScenario memory s = _setupUnwrappedScenario();

        // Listed below the bid price: the recorded amount would be wrong, must revert.
        vm.prank(s.seller);
        s.punks.offerPunkForSaleToAddress(s.tokenId, s.bidPrice - 1, s.stashAddr);

        vm.prank(s.seller);
        vm.expectRevert(V1PunkStash.InvalidBid.selector);
        V1PunkStash(payable(s.stashAddr)).processV1PunkBid(s.bid, s.tokenId, s.signature, new bytes32[](0));
    }

    function test_ProcessV1PunkBid_unwrapped_reverts_when_listing_at_zero() public {
        UnwrappedScenario memory s = _setupUnwrappedScenario();

        // Legacy v2 flow (list at 0) is no longer accepted.
        vm.prank(s.seller);
        s.punks.offerPunkForSaleToAddress(s.tokenId, 0, s.stashAddr);

        vm.prank(s.seller);
        vm.expectRevert(V1PunkStash.InvalidBid.selector);
        V1PunkStash(payable(s.stashAddr)).processV1PunkBid(s.bid, s.tokenId, s.signature, new bytes32[](0));
    }

    function test_ProcessV1PunkBid_unwrapped_reverts_when_listing_not_directed_to_stash() public {
        UnwrappedScenario memory s = _setupUnwrappedScenario();

        // Open listing: anybody could snipe it, must revert.
        vm.prank(s.seller);
        s.punks.offerPunkForSale(s.tokenId, s.bidPrice);

        vm.prank(s.seller);
        vm.expectRevert(V1PunkStash.InvalidBid.selector);
        V1PunkStash(payable(s.stashAddr)).processV1PunkBid(s.bid, s.tokenId, s.signature, new bytes32[](0));
    }

    function test_ProcessV1PunkBid_unwrapped_reverts_when_not_for_sale() public {
        UnwrappedScenario memory s = _setupUnwrappedScenario();

        vm.prank(s.seller);
        vm.expectRevert(V1PunkStash.InvalidBid.selector);
        V1PunkStash(payable(s.stashAddr)).processV1PunkBid(s.bid, s.tokenId, s.signature, new bytes32[](0));
    }

    // ===================== WRAPPED V1 TESTS (new in v4) =====================

    /// @dev Wrapped path: seller lists on Franck's marketplace at the bid price directed to the stash,
    /// the stash calls marketplace.buyPunk{value: bidPrice}, the marketplace pays the seller directly
    /// and transfers the WPV1 ERC721 to the stash. Stash then forwards the WPV1 to its owner (bidder).
    function test_ProcessV1PunkBid_wrapped_buys_via_marketplace_and_delivers_wpv1() public {
        WrappedScenario memory s = _setupWrappedScenario();

        // Seller lists on marketplace directed to stash at bid price
        vm.prank(s.seller);
        s.marketplace.offerPunkForSaleToAddress(s.tokenId, s.bidPrice, s.stashAddr);

        uint256 sellerBalBefore = s.seller.balance;
        uint256 stashBalBefore = s.stashAddr.balance;

        // Marketplace must emit PunkBought at the real price
        vm.expectEmit(true, true, true, true, address(s.marketplace));
        emit PunkBought(s.tokenId, s.bidPrice, s.seller, s.stashAddr);

        vm.prank(s.seller);
        V1PunkStash(payable(s.stashAddr)).processV1PunkBid(s.bid, s.tokenId, s.signature, new bytes32[](0));

        // Bidder (stash owner) received the WPV1 token
        assertEq(s.wpv1.ownerOf(s.tokenId), s.stashOwnerAddr, "WPV1 delivered to stash owner");
        // Seller was paid by the marketplace
        assertEq(s.seller.balance, sellerBalBefore + s.bidPrice, "seller paid by marketplace");
        // Stash spent exactly the bid price
        assertEq(s.stashAddr.balance, stashBalBefore - s.bidPrice, "stash spent exactly the bid price");
        // Marketplace recorded the volume
        assertEq(s.marketplace.totalVolume(), s.bidPrice, "marketplace volume updated");
    }

    function test_ProcessV1PunkBid_wrapped_reverts_when_listing_price_mismatch() public {
        WrappedScenario memory s = _setupWrappedScenario();

        // Listed below the bid price: the recorded amount would be wrong, must revert.
        vm.prank(s.seller);
        s.marketplace.offerPunkForSaleToAddress(s.tokenId, s.bidPrice - 1, s.stashAddr);

        vm.prank(s.seller);
        vm.expectRevert(V1PunkStash.InvalidBid.selector);
        V1PunkStash(payable(s.stashAddr)).processV1PunkBid(s.bid, s.tokenId, s.signature, new bytes32[](0));
    }

    function test_ProcessV1PunkBid_wrapped_reverts_when_listing_not_directed_to_stash() public {
        WrappedScenario memory s = _setupWrappedScenario();

        // Open listing: anybody could snipe it, must revert.
        vm.prank(s.seller);
        s.marketplace.offerPunkForSale(s.tokenId, s.bidPrice);

        vm.prank(s.seller);
        vm.expectRevert(V1PunkStash.InvalidBid.selector);
        V1PunkStash(payable(s.stashAddr)).processV1PunkBid(s.bid, s.tokenId, s.signature, new bytes32[](0));
    }

    function test_ProcessV1PunkBid_wrapped_reverts_when_not_for_sale() public {
        WrappedScenario memory s = _setupWrappedScenario();

        // Not listed at all
        vm.prank(s.seller);
        vm.expectRevert(V1PunkStash.InvalidBid.selector);
        V1PunkStash(payable(s.stashAddr)).processV1PunkBid(s.bid, s.tokenId, s.signature, new bytes32[](0));
    }

    function test_ProcessV1PunkBid_wrapped_reverts_when_caller_not_owner() public {
        WrappedScenario memory s = _setupWrappedScenario();

        vm.prank(s.seller);
        s.marketplace.offerPunkForSaleToAddress(s.tokenId, s.bidPrice, s.stashAddr);

        // Random address tries to call processV1PunkBid
        address impersonator = address(0xDEAD);
        vm.prank(impersonator);
        vm.expectRevert(V1PunkStash.Unauthorized.selector);
        V1PunkStash(payable(s.stashAddr)).processV1PunkBid(s.bid, s.tokenId, s.signature, new bytes32[](0));
    }

    // ===================== HELPERS =====================

    function _setupUnwrappedScenario() internal returns (UnwrappedScenario memory s) {
        address wpv1Addr = address(new MockWPV1Minimal());
        address punksAddr = address(new MockPunksV1());
        address wethAddr = address(new MockWETH9());
        // Marketplace not used for unwrapped path, deploy a dummy
        address marketplaceAddr = address(new MockWrappedPunksMarketplace(wpv1Addr));

        V1PunkStashFactory localFactory = new V1PunkStashFactory(address(0));
        vm.startPrank(localFactory.owner());
        localFactory.addVersion(address(new StashImplementationPlaceholderV1()));
        localFactory.addVersion(address(new StashImplementationPlaceholderV2()));
        localFactory.addVersion(address(new StashImplementationPlaceholderV3()));

        V1PunkStash impl = new V1PunkStash(address(localFactory), wethAddr, wpv1Addr, punksAddr, marketplaceAddr);
        localFactory.addVersion(address(impl));
        vm.stopPrank();

        uint256 stashOwnerPk = 0xA11CE;
        s.stashOwnerAddr = vm.addr(stashOwnerPk);
        s.stashAddr = localFactory.deployStash(s.stashOwnerAddr);

        s.seller = address(0xBEEF);
        s.tokenId = 7;
        s.bidPrice = 1 ether;
        s.punks = MockPunksV1(punksAddr);

        s.punks.mintPunk(s.seller, s.tokenId);
        vm.deal(s.stashAddr, s.bidPrice);

        s.bid = _makeBid(wpv1Addr, s.bidPrice);
        bytes32 digest = _eip712Digest(s.stashAddr, s.bid);
        (uint8 v, bytes32 r, bytes32 sig_s) = vm.sign(stashOwnerPk, digest);
        s.signature = abi.encodePacked(r, sig_s, v);
    }

    function _setupWrappedScenario() internal returns (WrappedScenario memory s) {
        MockWPV1Full wpv1 = new MockWPV1Full();
        MockWrappedPunksMarketplace marketplace = new MockWrappedPunksMarketplace(address(wpv1));
        address punksAddr = address(new MockPunksV1());
        address wethAddr = address(new MockWETH9());

        V1PunkStashFactory localFactory = new V1PunkStashFactory(address(0));
        vm.startPrank(localFactory.owner());
        localFactory.addVersion(address(new StashImplementationPlaceholderV1()));
        localFactory.addVersion(address(new StashImplementationPlaceholderV2()));
        localFactory.addVersion(address(new StashImplementationPlaceholderV3()));

        V1PunkStash impl = new V1PunkStash(
            address(localFactory), wethAddr, address(wpv1), punksAddr, address(marketplace)
        );
        localFactory.addVersion(address(impl));
        vm.stopPrank();

        uint256 stashOwnerPk = 0xA11CE;
        s.stashOwnerAddr = vm.addr(stashOwnerPk);
        s.stashAddr = localFactory.deployStash(s.stashOwnerAddr);

        s.seller = address(0xBEEF);
        vm.deal(s.seller, 0); // start with 0 to verify payment
        s.tokenId = 42;
        s.bidPrice = 2 ether;
        s.wpv1 = wpv1;
        s.marketplace = marketplace;

        // Mint a wrapped punk to the seller
        wpv1.mintWrapped(s.seller, s.tokenId);

        // Seller approves the marketplace to transfer the WPV1 token
        vm.prank(s.seller);
        wpv1.approve(address(marketplace), s.tokenId);

        // Fund the stash with enough ETH to pay the bid
        vm.deal(s.stashAddr, s.bidPrice);

        s.bid = _makeBid(address(wpv1), s.bidPrice);
        bytes32 digest = _eip712Digest(s.stashAddr, s.bid);
        (uint8 v, bytes32 r, bytes32 sig_s) = vm.sign(stashOwnerPk, digest);
        s.signature = abi.encodePacked(r, sig_s, v);
    }

    function _makeBid(address wpv1Addr, uint256 bidPrice) private pure returns (V1PunkBid memory bid) {
        bid = V1PunkBid({
            order: Order({numberOfUnits: 1, pricePerUnit: uint80(bidPrice), auction: wpv1Addr}),
            accountNonce: 0,
            bidNonce: 1,
            expiration: 0,
            root: bytes32(0)
        });
    }

    function _eip712Digest(address verifyingContract, V1PunkBid memory bid) internal view returns (bytes32) {
        bytes32 orderStructHash = keccak256(
            abi.encode(ORDER_TYPEHASH, bid.order.numberOfUnits, bid.order.pricePerUnit, bid.order.auction)
        );
        bytes32 hashStruct = keccak256(
            abi.encode(
                ERC721_BID_TYPEHASH,
                orderStructHash,
                bid.accountNonce,
                bid.bidNonce,
                bid.expiration,
                bid.root
            )
        );
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(uint256 chainId,address verifyingContract)"),
                block.chainid,
                verifyingContract
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, hashStruct));
    }
}
