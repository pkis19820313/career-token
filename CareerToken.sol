// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { Base64 } from "@openzeppelin/contracts/utils/Base64.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CareerToken is ERC20, ERC20Permit, Pausable, Ownable, ERC165, ReentrancyGuard {
    uint256 public constant MAX_SUPPLY = 5_000_000 * 10**18;
    uint256 public constant START_YEAR = 2025;
    uint256 public constant INITIAL_EMISSION = 100_000 * 10**18;
    uint256 public constant DECAY_RATE = 9850; // Representing 0.985 in basis points
    uint256 public constant DECAY_BASE = 10000;
    uint256 public constant START_TIMESTAMP = 1735689600;

    uint256 public lastMintReset;
    bool public mintingFinalized;

    mapping(address => uint8) public ranks;
    mapping(uint256 => uint256) public yearMinted;

    string private _tokenDescription;
    string private _imageURI;

    uint256 public lastMetadataUpdate;
    uint256 public constant METADATA_COOLDOWN = 1 days;
    uint8 public constant MAX_RANK = 10;

    bool public isRankPublic = true;

    event Minted(address indexed to, uint256 amount);
    event MintBatch(address[] recipients, uint256[] amounts);
    event YearLimitReached(uint256 year);
    event RankUpdated(address indexed user, uint8 rank);
    event MetadataUpdated(string newDescription, string newImageURI);
    event MintingFinalized();

    constructor(
        string memory name_,
        string memory symbol_,
        string memory description_,
        string memory imageURI_,
        address initialOwner
    ) ERC20(name_, symbol_) ERC20Permit(name_) Ownable(initialOwner) {
        lastMintReset = _currentYear();
        _tokenDescription = description_;
        _imageURI = imageURI_;
    }

    modifier whenNotFinalized() {
        require(!mintingFinalized, "Minting is finalized");
        _;
    }

    modifier metadataCooldown() {
        require(block.timestamp > lastMetadataUpdate + METADATA_COOLDOWN, "Cooldown active");
        _;
    }

    modifier onlyIfRankPublic() {
        require(isRankPublic, "Public access to ranks is disabled");
        _;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _currentYear() internal view returns (uint256) {
        if (block.timestamp < START_TIMESTAMP) return START_YEAR;
        return START_YEAR + (block.timestamp - START_TIMESTAMP) / 365 days;
    }

    function yearlyMintLimit(uint256 year) public pure returns (uint256) {
        require(year >= START_YEAR, "Invalid year");
        uint256 exponent = year - START_YEAR;
        uint256 rate = INITIAL_EMISSION;
        for (uint256 i = 0; i < exponent; i++) {
            rate = (rate * DECAY_RATE) / DECAY_BASE;
        }
        return rate;
    }

    function mint(address to, uint256 amount) public onlyOwner whenNotFinalized nonReentrant {
        require(to != address(0), "Cannot mint to zero address");
        uint256 year = _currentYear();
        require(year <= 2200, "Minting too far in the future");

        uint256 limit = yearlyMintLimit(year);
        require(yearMinted[year] + amount <= limit, "Yearly mint limit exceeded");

        yearMinted[year] += amount;
        _mint(to, amount);

        emit Minted(to, amount);
        if (yearMinted[year] == limit) {
            emit YearLimitReached(year);
        }
    }

    function mintBatch(address[] calldata recipients, uint256[] calldata amounts) public onlyOwner whenNotFinalized nonReentrant {
        require(recipients.length == amounts.length, "Mismatched inputs");
        require(recipients.length <= 100, "Too many recipients");

        uint256 year = _currentYear();
        require(year <= 2200, "Minting too far in the future");

        uint256 limit = yearlyMintLimit(year);
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        require(yearMinted[year] + totalAmount <= limit, "Yearly mint limit exceeded");

        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Cannot mint to zero address");
            _mint(recipients[i], amounts[i]);
        }

        yearMinted[year] += totalAmount;
        emit MintBatch(recipients, amounts);
        if (yearMinted[year] == limit) {
            emit YearLimitReached(year);
        }
    }

    function totalMinted() public view returns (uint256 total) {
        for (uint256 year = START_YEAR; year <= _currentYear(); year++) {
            total += yearMinted[year];
        }
    }

    function getYearlyStats(uint256 year) public view returns (uint256 minted, uint256 limit) {
        minted = yearMinted[year];
        limit = yearlyMintLimit(year);
    }

    function getAllMintedYears() public view returns (uint256[] memory, uint256[] memory) {
        uint256 current = _currentYear();
        uint256 count = 0;

        for (uint256 year = START_YEAR; year <= current; year++) {
            if (yearMinted[year] > 0) {
                count++;
            }
        }

        uint256[] memory resultYears = new uint256[](count);
        uint256[] memory resultAmounts = new uint256[](count);
        uint256 index = 0;

        for (uint256 year = START_YEAR; year <= current; year++) {
            if (yearMinted[year] > 0) {
                resultYears[index] = year;
                resultAmounts[index] = yearMinted[year];
                index++;
            }
        }

        return (resultYears, resultAmounts);
    }

    function setRank(address user, uint8 rank) public onlyOwner {
        require(rank <= MAX_RANK, "Invalid rank");
        ranks[user] = rank;
        emit RankUpdated(user, rank);
    }

    function setRankVisibility(bool _isPublic) external onlyOwner {
        isRankPublic = _isPublic;
    }

    function getRank(address user) public view onlyIfRankPublic returns (uint8) {
        return ranks[user];
    }

    function getMyRank() public view returns (uint8) {
        return ranks[msg.sender];
    }

    function updateMetadata(string memory newDescription, string memory newImageURI) public onlyOwner metadataCooldown {
        require(bytes(newDescription).length > 0, "Empty description");
        require(bytes(newImageURI).length > 0, "Empty image URI");
        _tokenDescription = newDescription;
        _imageURI = newImageURI;
        lastMetadataUpdate = block.timestamp;
        emit MetadataUpdated(newDescription, newImageURI);
    }

    function finalizeMinting() public onlyOwner {
        mintingFinalized = true;
        emit MintingFinalized();
    }

    function tokenURI() public view returns (string memory) {
        bytes memory data = abi.encodePacked(
            "{",
            "\"name\": \"", name(), "\",",
            "\"symbol\": \"", symbol(), "\",",
            "\"description\": \"", _tokenDescription, "\",",
            "\"image\": \"", _imageURI, "\"",
            "}"
        );
        string memory encoded = Base64.encode(data);
        return string(abi.encodePacked("data:application/json;base64,", encoded));
    }

    function version() public pure virtual returns (string memory) {
        return "1.0.0";
    }

    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        super._update(from, to, value);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}


