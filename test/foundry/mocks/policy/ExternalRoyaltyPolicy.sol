// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC165, ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IIpRoyaltyVault } from "../../../../contracts/interfaces/modules/royalty/policies/IIpRoyaltyVault.sol";
import { IRoyaltyModule } from "../../../../contracts/interfaces/modules/royalty/IRoyaltyModule.sol";

// solhint-disable-next-line max-line-length
import { IExternalRoyaltyPolicy } from "../../../../contracts/interfaces/modules/royalty/policies/IExternalRoyaltyPolicy.sol";

contract ExternalRoyaltyPolicy is ERC165, IExternalRoyaltyPolicy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Returns the percentage scale - represents 100%
    uint32 public constant MAX_PERCENT = 100_000_000;

    /// @notice The address of the IP asset
    address public constant WIP = 0x1514000000000000000000000000000000000000;

    /// @notice The address of the royalty module
    address public immutable ROYALTY_MODULE;

    struct Product {
        address scientist;
        address investor;
        uint32 thresholdPercent;
        uint256 thresholdValue;
    }

    mapping(address ipId => Product) public products;
    mapping(address ipId => uint256) public totalClaimed;

    error NotAuthorized();
    error ProductAlreadyAssigned();
    error ProductNotAssigned();
    error InvalidScientist();
    error InvalidInvestor();
    error InvalidThresholdPercent();
    error InvalidThresholdValue();
    error InsufficientBalanceToAssign();
    error InvalidRoyaltyModule();
    error InsufficientBalanceToClaim();

    /// @notice Constructor
    /// @param royaltyModule The address of the royalty module
    constructor(address royaltyModule) {
        if (royaltyModule == address(0)) revert InvalidRoyaltyModule();
        ROYALTY_MODULE = royaltyModule;
    }

    /// @notice Assigns a product to an IP asset
    /// @param ipId The address of the IP asset
    /// @param scientist The address of the scientist
    /// @param investor The address of the investor
    /// @param thresholdPercent The threshold percentage
    /// @param thresholdValue The threshold value
    function assign(
        address ipId,
        address scientist,
        address investor,
        uint32 thresholdPercent,
        uint256 thresholdValue
    ) external {
        // solhint-disable-next-line max-line-length
        if (msg.sender != ipId) revert NotAuthorized(); // It is assumed for this example contract that the IP owner is trusted by all parties for the setup
        if (products[ipId].scientist != address(0)) revert ProductAlreadyAssigned();
        address royaltyToken = IRoyaltyModule(ROYALTY_MODULE).ipRoyaltyVaults(ipId);
        if (IERC20(royaltyToken).balanceOf(address(this)) == 0) revert InsufficientBalanceToAssign();

        if (scientist == address(0)) revert InvalidScientist();
        if (investor == address(0)) revert InvalidInvestor();
        if (thresholdPercent > MAX_PERCENT) revert InvalidThresholdPercent();
        if (thresholdValue == 0) revert InvalidThresholdValue();

        products[ipId] = Product(scientist, investor, thresholdPercent, thresholdValue);
    }

    /// @notice Claims revenue for an IP asset
    /// @param ipId The address of the IP asset
    function claim(address ipId) external nonReentrant {
        Product memory product = products[ipId];
        if (product.scientist == address(0)) revert ProductNotAssigned();

        address royaltyToken = IRoyaltyModule(ROYALTY_MODULE).ipRoyaltyVaults(ipId);
        uint256 amountClaimed = IIpRoyaltyVault(royaltyToken).claimRevenueOnBehalf(address(this), WIP);
        if (amountClaimed == 0) revert InsufficientBalanceToClaim();

        uint256 amountToInvestor;
        uint256 amountToScientist;
        uint256 totalClaimedAmount = totalClaimed[ipId];
        if (totalClaimedAmount > product.thresholdValue) {
            amountToInvestor = (amountClaimed * product.thresholdPercent) / MAX_PERCENT;
            amountToScientist = amountClaimed - amountToInvestor;
        } else {
            if (totalClaimedAmount + amountClaimed > product.thresholdValue) {
                uint256 amountAboveThreshold = totalClaimedAmount + amountClaimed - product.thresholdValue;
                uint256 amountAboveThresholdForInvestor = (amountAboveThreshold * product.thresholdPercent) /
                    MAX_PERCENT;
                amountToInvestor = product.thresholdValue - totalClaimedAmount + amountAboveThresholdForInvestor;
                amountToScientist = amountAboveThreshold - amountAboveThresholdForInvestor;
            } else {
                amountToInvestor = amountClaimed;
                amountToScientist = 0;
            }
        }

        totalClaimed[ipId] += amountClaimed;

        IERC20(WIP).safeTransfer(product.scientist, amountToScientist);
        IERC20(WIP).safeTransfer(product.investor, amountToInvestor);
    }

    /// @notice Returns the amount of royalty tokens required to link a child to a given IP asset
    /// @param ipId The ipId of the IP asset
    /// @param licensePercent The percentage of the license
    /// @return The amount of royalty tokens required to link a child to a given IP asset
    function getPolicyRtsRequiredToLink(address ipId, uint32 licensePercent) external view returns (uint32) {
        return MAX_PERCENT;
    }

    /// @notice IERC165 interface support.
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == this.getPolicyRtsRequiredToLink.selector || super.supportsInterface(interfaceId);
    }
}
