// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ============================================================
//  HGC Marketplace — Buy & Sell Carbon Credits
//  HarvestMind Carbon Credit System
//  Deploy on: Polygon Amoy Testnet (demo) / Polygon Mainnet (prod)
// ============================================================

/**
 * @title HGCMarketplace
 * @notice Peer-to-peer marketplace for HarvestGreen Credits (HGC).
 *         Sellers list HGC at a price in MATIC. Buyers purchase atomically.
 *         HarvestMind earns 2% fee on every trade (configurable).
 *         Floor price enforced — no listing below minimum.
 *
 * HOW A TRADE WORKS (atomic, no trust needed):
 *   1. Seller calls listCredits(amount, pricePerHGC)
 *      → HGC is locked in this contract (escrowed)
 *   2. Buyer calls buyCredits(listingId) with MATIC payment
 *      → Contract checks payment, deducts 2% fee
 *      → Transfers HGC to buyer wallet
 *      → Transfers MATIC (minus fee) to seller
 *      → Sends 2% fee to HarvestMind fee wallet
 *   3. Buyer can call retire(amount, reason) on the HGCToken
 *      for permanent ESG credit retirement
 */
interface IERC20 {
    function transferFrom(address from, address to,   uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount)                     external returns (bool);
    function balanceOf(address account)               external view   returns (uint256);
    function allowance(address owner, address spender) external view  returns (uint256);
}

contract HGCMarketplace {

    // ── Structs ──────────────────────────────────────────────

    struct Listing {
        uint256 id;
        address seller;
        uint256 hgcAmount;      // Amount of HGC listed (in wei, 18 decimals)
        uint256 pricePerHGC;    // Price in MATIC wei per 1 full HGC (1e18)
        bool    active;
        uint256 createdAt;
    }

    // ── State ────────────────────────────────────────────────

    IERC20  public hgcToken;         // HGCToken contract
    address public owner;
    address public feeWallet;        // HarvestMind's revenue wallet

    uint256 public floorPriceWei;    // Minimum price per HGC in MATIC wei
                                     // Default: ~₹800 worth of MATIC
    uint256 public feePercent;       // 2 = 2% fee (out of 100)

    uint256 public listingCount;
    mapping(uint256 => Listing) public listings;

    // seller address => list of their listing IDs
    mapping(address => uint256[]) public listingsBySeller;

    // ── Events ───────────────────────────────────────────────

    event Listed(uint256 indexed listingId, address indexed seller, uint256 hgcAmount, uint256 pricePerHGC);
    event Sold(uint256 indexed listingId, address indexed buyer, address indexed seller, uint256 hgcAmount, uint256 maticPaid);
    event ListingCancelled(uint256 indexed listingId);
    event FloorPriceUpdated(uint256 newFloorPrice);
    event FeeUpdated(uint256 newFeePercent);

    // ── Modifiers ────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "Market: not owner");
        _;
    }

    // ── Constructor ──────────────────────────────────────────

    /**
     * @param _hgcToken       Address of deployed HGCToken contract
     * @param _feeWallet      HarvestMind wallet that receives 2% fees
     * @param _floorPriceWei  Minimum listing price in MATIC wei
     *                        Example: 400000000000000000 = 0.4 MATIC ≈ ₹800
     */
    constructor(address _hgcToken, address _feeWallet, uint256 _floorPriceWei) {
        require(_hgcToken   != address(0), "Market: zero token");
        require(_feeWallet  != address(0), "Market: zero fee wallet");
        hgcToken       = IERC20(_hgcToken);
        feeWallet      = _feeWallet;
        owner          = msg.sender;
        floorPriceWei  = _floorPriceWei;
        feePercent     = 2; // 2% default
    }

    // ── Seller: List HGC for sale ─────────────────────────────

    /**
     * @notice Seller lists their HGC. Tokens are escrowed in this contract.
     * @param hgcAmount    Amount of HGC to sell (in wei). E.g. 0.1 HGC = 1e17
     * @param pricePerHGC  Price in MATIC wei for 1 full HGC (1e18).
     *                     E.g. 400000000000000000 = 0.4 MATIC per HGC
     *
     * IMPORTANT: Seller must first call hgcToken.approve(marketplaceAddress, hgcAmount)
     */
    function listCredits(uint256 hgcAmount, uint256 pricePerHGC) external returns (uint256 listingId) {
        require(hgcAmount > 0,                   "Market: zero amount");
        require(pricePerHGC >= floorPriceWei,    "Market: below floor price");
        require(
            hgcToken.allowance(msg.sender, address(this)) >= hgcAmount,
            "Market: approve HGC first"
        );

        // Pull tokens into escrow
        bool ok = hgcToken.transferFrom(msg.sender, address(this), hgcAmount);
        require(ok, "Market: HGC transfer failed");

        listingCount++;
        listingId = listingCount;

        listings[listingId] = Listing({
            id:           listingId,
            seller:       msg.sender,
            hgcAmount:    hgcAmount,
            pricePerHGC:  pricePerHGC,
            active:       true,
            createdAt:    block.timestamp
        });

        listingsBySeller[msg.sender].push(listingId);

        emit Listed(listingId, msg.sender, hgcAmount, pricePerHGC);
    }

    // ── Buyer: Purchase HGC ──────────────────────────────────

    /**
     * @notice Buyer purchases HGC from a listing by sending MATIC.
     * @param listingId   ID of the listing to purchase
     *
     * Buyer must send exactly: listing.hgcAmount × listing.pricePerHGC / 1e18 MATIC
     *
     * Example:
     *   Listing: 0.1 HGC at 0.4 MATIC per HGC
     *   Total MATIC = 0.1 × 0.4 = 0.04 MATIC
     *   msg.value must be 40000000000000000 wei
     */
    function buyCredits(uint256 listingId) external payable {
        Listing storage l = listings[listingId];
        require(l.active,                          "Market: listing not active");
        require(msg.sender != l.seller,            "Market: cannot buy your own listing");

        // Calculate total cost
        uint256 totalCost = (l.hgcAmount * l.pricePerHGC) / 1e18;
        require(msg.value >= totalCost,            "Market: insufficient MATIC sent");

        // Mark as sold before transfers (re-entrancy protection)
        l.active = false;

        // Calculate 2% fee
        uint256 fee           = (totalCost * feePercent) / 100;
        uint256 sellerPayout  = totalCost - fee;

        // Transfer HGC to buyer
        bool ok = hgcToken.transfer(msg.sender, l.hgcAmount);
        require(ok, "Market: HGC transfer to buyer failed");

        // Pay seller (minus fee)
        (bool sentSeller, ) = payable(l.seller).call{value: sellerPayout}("");
        require(sentSeller, "Market: MATIC to seller failed");

        // Send fee to HarvestMind
        (bool sentFee, ) = payable(feeWallet).call{value: fee}("");
        require(sentFee, "Market: fee transfer failed");

        // Refund overpayment if any
        if (msg.value > totalCost) {
            (bool refund, ) = payable(msg.sender).call{value: msg.value - totalCost}("");
            require(refund, "Market: refund failed");
        }

        emit Sold(listingId, msg.sender, l.seller, l.hgcAmount, totalCost);
    }

    // ── Seller: Cancel listing ────────────────────────────────

    /**
     * @notice Seller cancels their listing and gets HGC back.
     */
    function cancelListing(uint256 listingId) external {
        Listing storage l = listings[listingId];
        require(l.active,                          "Market: listing not active");
        require(msg.sender == l.seller,            "Market: not your listing");

        l.active = false;

        bool ok = hgcToken.transfer(l.seller, l.hgcAmount);
        require(ok, "Market: HGC refund failed");

        emit ListingCancelled(listingId);
    }

    // ── Read functions ────────────────────────────────────────

    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }

    function getListingsBySeller(address seller) external view returns (uint256[] memory) {
        return listingsBySeller[seller];
    }

    /**
     * @notice Helper to calculate exact MATIC required for a purchase
     */
    function getRequiredMatic(uint256 listingId) external view returns (uint256 totalCost, uint256 fee) {
        Listing storage l = listings[listingId];
        require(l.active, "Market: listing not active");
        totalCost = (l.hgcAmount * l.pricePerHGC) / 1e18;
        fee       = (totalCost * feePercent) / 100;
    }

    // ── Admin ─────────────────────────────────────────────────

    /**
     * @notice Update the floor price (only HarvestMind admin)
     * @param newFloorWei  New floor in MATIC wei
     */
    function setFloorPrice(uint256 newFloorWei) external onlyOwner {
        floorPriceWei = newFloorWei;
        emit FloorPriceUpdated(newFloorWei);
    }

    function setFeePercent(uint256 _fee) external onlyOwner {
        require(_fee <= 10, "Market: fee too high"); // Max 10%
        feePercent = _fee;
        emit FeeUpdated(_fee);
    }

    function setFeeWallet(address _feeWallet) external onlyOwner {
        require(_feeWallet != address(0), "Market: zero address");
        feeWallet = _feeWallet;
    }
}
