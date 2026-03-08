// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ============================================================
//  HarvestGreen Credit (HGC) — ERC-20 Token
//  HarvestMind Carbon Credit System
//  Deploy on: Polygon Amoy Testnet (demo) / Polygon Mainnet (prod)
// ============================================================

/**
 * @title HarvestGreen Credit Token (HGC)
 * @notice ERC-20 token representing verified food-rescue carbon credits.
 *         1 HGC = 1 tonne of CO₂ prevented by rescuing food from landfill.
 *
 * MINT LOGIC:
 *   - Supply starts at zero. No pre-minting.
 *   - Only the authorized minter (your backend/ImpactRegistry contract) can mint.
 *   - Minting happens automatically when NGO marks a rescue as "delivered".
 *
 * BURN LOGIC:
 *   - Any token holder can burn (retire) their credits.
 *   - Burning is permanent — prevents double-counting in ESG reports.
 *
 * SPLIT:
 *   - On every mint, 50% goes to the restaurant wallet, 50% to HarvestMind treasury.
 *   - This split is enforced in the mintForRescue() function.
 */
contract HGCToken {

    // ── Token metadata ──────────────────────────────────────
    string  public constant name     = "HarvestGreen Credit";
    string  public constant symbol   = "HGC";
    uint8   public constant decimals = 18;

    // ── State ────────────────────────────────────────────────
    uint256 public totalSupply;

    mapping(address => uint256)                     public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public owner;           // HarvestMind deployer wallet
    address public treasury;        // HarvestMind's 50% accumulation wallet
    address public authorizedMinter; // Your backend wallet or ImpactRegistry contract

    // ── Events ───────────────────────────────────────────────
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner_, address indexed spender, uint256 value);
    event Minted(address indexed restaurant, uint256 restaurantAmount, uint256 treasuryAmount, string rescueId);
    event Retired(address indexed by, uint256 amount, string reason);

    // ── Modifiers ────────────────────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "HGC: not owner");
        _;
    }

    modifier onlyMinter() {
        require(msg.sender == authorizedMinter || msg.sender == owner, "HGC: not authorized minter");
        _;
    }

    // ── Constructor ──────────────────────────────────────────
    /**
     * @param _treasury  Your HarvestMind treasury wallet address
     * @param _minter    Your backend hot-wallet address (or ImpactRegistry contract later)
     */
    constructor(address _treasury, address _minter) {
        require(_treasury != address(0), "HGC: zero treasury");
        require(_minter   != address(0), "HGC: zero minter");
        owner            = msg.sender;
        treasury         = _treasury;
        authorizedMinter = _minter;
    }

    // ── Core ERC-20 functions ────────────────────────────────

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "HGC: allowance exceeded");
        allowance[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    // ── HarvestMind-specific: Mint on rescue ─────────────────

    /**
     * @notice Called by backend when NGO marks rescue as "delivered".
     * @param restaurantWallet  The restaurant's custodial wallet address
     * @param kgRescued         Total kg of food rescued (in grams for precision, divide by 1000)
     * @param rescueId          Unique rescue ID from your Supabase database
     *
     * Formula:
     *   CO₂ prevented (kg) = kgRescued × 2.5
     *   HGC total = CO₂ prevented / 1000  (1 HGC = 1 tonne CO₂)
     *   Restaurant gets 50%, Treasury gets 50%
     *
     * Example: 40 kg rescued
     *   CO₂ = 40 × 2.5 = 100 kg = 0.1 tonne
     *   Total HGC = 0.1 HGC = 0.1 × 10^18 token units
     *   Restaurant: 0.05 HGC | Treasury: 0.05 HGC
     */
    function mintForRescue(
        address restaurantWallet,
        uint256 kgRescued,        // e.g. 40 (for 40 kg)
        string  calldata rescueId
    ) external onlyMinter returns (uint256 restaurantAmount, uint256 treasuryAmount) {

        require(restaurantWallet != address(0), "HGC: zero restaurant wallet");
        require(kgRescued > 0,                  "HGC: zero kg rescued");

        // 1 kg rescued = 2.5 kg CO₂ = 0.0025 tonne CO₂
        // Total HGC (in wei) = kgRescued * 2.5 / 1000 * 10^18
        // Simplified: kgRescued * 2500 * 10^12
        uint256 totalHGC = kgRescued * 2500 * (10 ** 12); // = kgRescued × 0.0025 HGC

        restaurantAmount = totalHGC / 2;         // 50%
        treasuryAmount   = totalHGC - restaurantAmount; // 50% (handles odd rounding)

        _mint(restaurantWallet, restaurantAmount);
        _mint(treasury,         treasuryAmount);

        emit Minted(restaurantWallet, restaurantAmount, treasuryAmount, rescueId);
    }

    // ── HarvestMind-specific: Retire (burn) for ESG ──────────

    /**
     * @notice Companies call this to permanently retire credits for ESG compliance.
     *         Burned tokens cannot be resold — prevents double-counting.
     * @param amount  Amount of HGC to retire (in token wei, 18 decimals)
     * @param reason  Description for audit trail, e.g. "TCS Q3 2025 ESG Report"
     */
    function retire(uint256 amount, string calldata reason) external {
        require(balanceOf[msg.sender] >= amount, "HGC: insufficient balance to retire");
        _burn(msg.sender, amount);
        emit Retired(msg.sender, amount, reason);
    }

    // ── Admin functions ──────────────────────────────────────

    function setAuthorizedMinter(address _minter) external onlyOwner {
        require(_minter != address(0), "HGC: zero address");
        authorizedMinter = _minter;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "HGC: zero address");
        treasury = _treasury;
    }

    // ── Internal helpers ─────────────────────────────────────

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0),                 "HGC: transfer to zero");
        require(balanceOf[from] >= amount,        "HGC: insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to]   += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply    += amount;
        balanceOf[to]  += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;
        totalSupply     -= amount;
        emit Transfer(from, address(0), amount);
    }
}
