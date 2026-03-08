// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ============================================================
//  Impact Registry — Immutable Audit Trail
//  HarvestMind Carbon Credit System
//  Deploy on: Polygon Amoy Testnet (demo) / Polygon Mainnet (prod)
// ============================================================

/**
 * @title ImpactRegistry
 * @notice Every rescue is permanently recorded here the moment NGO marks "delivered".
 *         This is the proof layer — companies and auditors verify credits here.
 *         Records are IMMUTABLE. Once written, they cannot be changed or deleted.
 *
 * HOW IT CONNECTS:
 *   1. NGO taps "I've Delivered It" in the dispatch app
 *   2. Your backend calls ImpactRegistry.recordRescue(...)
 *   3. ImpactRegistry records everything on-chain
 *   4. ImpactRegistry then calls HGCToken.mintForRescue(...)
 *   5. HGC is minted to restaurant and treasury wallets
 *   6. Frontend reads the RescueRecorded event to show the Impact Certificate
 */
interface IHGCToken {
    function mintForRescue(
        address restaurantWallet,
        uint256 kgRescued,
        string  calldata rescueId
    ) external returns (uint256, uint256);
}

contract ImpactRegistry {

    // ── Structs ──────────────────────────────────────────────

    struct RescueRecord {
        string  rescueId;           // Matches your Supabase rescue ID
        string  donorName;          // Restaurant name
        address donorWallet;        // Restaurant wallet (gets HGC)
        string  ngoName;            // NGO that collected
        uint256 kgRescued;          // Food rescued in kg
        uint256 co2PreventedGrams;  // = kgRescued × 2500 (in grams for precision)
        uint256 hgcMintedWei;       // Total HGC minted (restaurant + treasury)
        uint256 mealsServed;        // Approximate meals (kgRescued × 2.5 meals/kg)
        uint256 timestamp;          // Block timestamp
        bool    retired;            // True if company retired this rescue's credits
        string  retirementReason;   // e.g. "TCS Q3 2025 ESG Report"
    }

    // ── State ────────────────────────────────────────────────

    address public owner;
    address public authorizedRecorder; // Your backend wallet
    IHGCToken public hgcToken;         // Reference to HGCToken contract

    uint256 public totalRescues;
    uint256 public totalKgRescued;
    uint256 public totalMealsServed;
    uint256 public totalCO2PreventedKg; // Running total in kg

    // rescueId (string) => RescueRecord
    mapping(string => RescueRecord) public rescues;

    // Store all rescue IDs in order for enumeration
    string[] public allRescueIds;

    // donor wallet => list of their rescue IDs
    mapping(address => string[]) public rescuesByDonor;

    // ── Events ───────────────────────────────────────────────

    event RescueRecorded(
        string  indexed rescueId,
        string  donorName,
        address indexed donorWallet,
        string  ngoName,
        uint256 kgRescued,
        uint256 co2PreventedGrams,
        uint256 hgcMintedWei,
        uint256 mealsServed,
        uint256 timestamp
    );

    event CreditsRetired(
        string  indexed rescueId,
        string  retirementReason,
        uint256 timestamp
    );

    // ── Modifiers ────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "Registry: not owner");
        _;
    }

    modifier onlyRecorder() {
        require(
            msg.sender == authorizedRecorder || msg.sender == owner,
            "Registry: not authorized recorder"
        );
        _;
    }

    // ── Constructor ──────────────────────────────────────────

    /**
     * @param _hgcToken         Address of deployed HGCToken contract
     * @param _recorder         Your backend hot-wallet address
     */
    constructor(address _hgcToken, address _recorder) {
        require(_hgcToken  != address(0), "Registry: zero hgc token");
        require(_recorder  != address(0), "Registry: zero recorder");
        owner              = msg.sender;
        hgcToken           = IHGCToken(_hgcToken);
        authorizedRecorder = _recorder;
    }

    // ── Core: Record a rescue and mint HGC ───────────────────

    /**
     * @notice Records the rescue permanently and triggers HGC minting.
     *         Called by your backend when NGO confirms delivery.
     *
     * @param rescueId       Unique ID from your Supabase DB (e.g. "rescue_0042")
     * @param donorName      Restaurant name (e.g. "Hotel Pearl Palace")
     * @param donorWallet    Restaurant's custodial wallet
     * @param ngoName        NGO name (e.g. "Akshaya Patra")
     * @param kgRescued      Food rescued in kg (e.g. 40)
     */
    function recordRescue(
        string  calldata rescueId,
        string  calldata donorName,
        address          donorWallet,
        string  calldata ngoName,
        uint256          kgRescued
    ) external onlyRecorder {

        // Prevent duplicate recording of same rescue
        require(bytes(rescues[rescueId].rescueId).length == 0, "Registry: rescue already recorded");
        require(donorWallet != address(0),  "Registry: zero donor wallet");
        require(kgRescued > 0,             "Registry: zero kg");

        // Calculate impact
        uint256 co2Grams  = kgRescued * 2500;      // 1 kg food = 2.5 kg CO₂ = 2500g
        uint256 meals     = kgRescued * 25 / 10;   // ~2.5 meals per kg rescued

        // Mint HGC via token contract — get back how much was minted
        (uint256 restaurantHGC, uint256 treasuryHGC) = hgcToken.mintForRescue(
            donorWallet,
            kgRescued,
            rescueId
        );
        uint256 totalMinted = restaurantHGC + treasuryHGC;

        // Write immutable record
        RescueRecord storage r = rescues[rescueId];
        r.rescueId          = rescueId;
        r.donorName         = donorName;
        r.donorWallet       = donorWallet;
        r.ngoName           = ngoName;
        r.kgRescued         = kgRescued;
        r.co2PreventedGrams = co2Grams;
        r.hgcMintedWei      = totalMinted;
        r.mealsServed       = meals;
        r.timestamp         = block.timestamp;
        r.retired           = false;

        // Index
        allRescueIds.push(rescueId);
        rescuesByDonor[donorWallet].push(rescueId);

        // Update global counters
        totalRescues         += 1;
        totalKgRescued       += kgRescued;
        totalMealsServed     += meals;
        totalCO2PreventedKg  += kgRescued * 25 / 10; // in tenths of kg, div by 10 for kg

        emit RescueRecorded(
            rescueId,
            donorName,
            donorWallet,
            ngoName,
            kgRescued,
            co2Grams,
            totalMinted,
            meals,
            block.timestamp
        );
    }

    // ── Mark credits as retired (after ESG use) ──────────────

    /**
     * @notice Called by backend when a company retires credits tied to this rescue.
     *         Marks the rescue as used — companies can prove on-chain their offset is real.
     */
    function markRetired(string calldata rescueId, string calldata reason) external onlyRecorder {
        require(bytes(rescues[rescueId].rescueId).length > 0, "Registry: rescue not found");
        require(!rescues[rescueId].retired, "Registry: already retired");

        rescues[rescueId].retired           = true;
        rescues[rescueId].retirementReason  = reason;

        emit CreditsRetired(rescueId, reason, block.timestamp);
    }

    // ── Read functions (for frontend + certificates) ─────────

    function getRescue(string calldata rescueId) external view returns (RescueRecord memory) {
        return rescues[rescueId];
    }

    function getRescuesByDonor(address donor) external view returns (string[] memory) {
        return rescuesByDonor[donor];
    }

    function getTotalRescues() external view returns (uint256) {
        return totalRescues;
    }

    function getGlobalImpact() external view returns (
        uint256 rescues_,
        uint256 kgRescued_,
        uint256 meals_,
        uint256 co2Kg_
    ) {
        return (totalRescues, totalKgRescued, totalMealsServed, totalCO2PreventedKg);
    }

    // ── Admin ────────────────────────────────────────────────

    function setAuthorizedRecorder(address _recorder) external onlyOwner {
        authorizedRecorder = _recorder;
    }
}
