// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import { Base64 } from "@openzeppelin/contracts/utils/Base64.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
// solhint-disable-next-line max-line-length
import { ERC721EnumerableUpgradeable, ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import { IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
// solhint-disable-next-line max-line-length
import { AccessManagedUpgradeable } from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import { ILicenseToken } from "./interfaces/ILicenseToken.sol";
import { ILicenseRegistry } from "./interfaces/registries/ILicenseRegistry.sol";
import { ILicensingModule } from "./interfaces/modules/licensing/ILicensingModule.sol";
import { IDisputeModule } from "./interfaces/modules/dispute/IDisputeModule.sol";
import { Errors } from "./lib/Errors.sol";
import { ILicenseTemplate } from "./interfaces/modules/licensing/ILicenseTemplate.sol";

/// @title LicenseToken aka LNFT
contract LicenseToken is ILicenseToken, ERC721EnumerableUpgradeable, AccessManagedUpgradeable, UUPSUpgradeable {
    using Strings for *;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ILicenseRegistry public immutable LICENSE_REGISTRY;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ILicensingModule public immutable LICENSING_MODULE;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IDisputeModule public immutable DISPUTE_MODULE;

    /// @notice Max Royalty percentage is 100_000_000 means 100%.
    uint32 public constant MAX_COMMERCIAL_REVENUE_SHARE = 100_000_000;

    /// @notice Emitted for metadata updates, per EIP-4906
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    /// @dev Storage structure for the LicenseToken
    /// @custom:storage-location erc7201:story-protocol.LicenseToken
    struct LicenseTokenStorage {
        string imageUrl;
        uint256 totalMintedTokens;
        mapping(uint256 tokenId => LicenseTokenMetadata) licenseTokenMetadatas;
        mapping(address licensorIpId => uint256 totalMintedTokens) licensorIpTotalTokens;
    }

    // keccak256(abi.encode(uint256(keccak256("story-protocol.LicenseToken")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant LicenseTokenStorageLocation =
        0x62a0d75e37bea0c3e666dc72a74112fc6af15ce635719127e380d8ca1e555d00;

    modifier onlyLicensingModule() {
        if (msg.sender != address(LICENSING_MODULE)) {
            revert Errors.LicenseToken__CallerNotLicensingModule();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address licensingModule, address disputeModule, address licenseRegistry) {
        LICENSING_MODULE = ILicensingModule(licensingModule);
        DISPUTE_MODULE = IDisputeModule(disputeModule);
        LICENSE_REGISTRY = ILicenseRegistry(licenseRegistry);
        _disableInitializers();
    }

    /// @dev Initializes the LicenseToken contract
    function initialize(address accessManager, string memory imageUrl) public initializer {
        if (accessManager == address(0)) {
            revert Errors.LicenseToken__ZeroAccessManager();
        }
        __ERC721_init("Programmable IP License Token", "PILicenseToken");
        __AccessManaged_init(accessManager);
        __UUPSUpgradeable_init();
        _getLicenseTokenStorage().imageUrl = imageUrl;
    }

    /// @dev Sets the Licensing Image URL.
    /// @dev Enforced to be only callable by the protocol admin
    /// @param url The URL of the Licensing Image
    function setLicensingImageUrl(string calldata url) external restricted {
        LicenseTokenStorage storage $ = _getLicenseTokenStorage();
        $.imageUrl = url;
        emit BatchMetadataUpdate(1, $.totalMintedTokens);
    }

    /// @notice Mints a specified amount of License Tokens (LNFTs).
    /// @param licensorIpId The ID of the licensor IP for which the License Tokens are minted.
    /// @param licenseTemplate The address of the License Template.
    /// @param licenseTermsId The ID of the License Terms.
    /// @param amount The amount of License Tokens to mint.
    /// @param minter The address of the minter.
    /// @param receiver The address of the receiver of the minted License Tokens.
    /// @param maxRevenueShare The maximum revenue share percentage allowed for minting the License Tokens.
    /// @return startLicenseTokenId The start ID of the minted License Tokens.
    function mintLicenseTokens(
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        uint256 amount, // mint amount
        address minter,
        address receiver,
        uint32 maxRevenueShare
    ) external onlyLicensingModule returns (uint256 startLicenseTokenId) {
        LicenseTokenMetadata memory ltm = LicenseTokenMetadata({
            licensorIpId: licensorIpId,
            licenseTemplate: licenseTemplate,
            licenseTermsId: licenseTermsId,
            transferable: ILicenseTemplate(licenseTemplate).isLicenseTransferable(licenseTermsId),
            commercialRevShare: LICENSE_REGISTRY.getRoyaltyPercent(licensorIpId, licenseTemplate, licenseTermsId)
        });
        if (maxRevenueShare != 0 && ltm.commercialRevShare > maxRevenueShare) {
            revert Errors.LicenseToken__CommercialRevenueShareExceedMaxRevenueShare(
                ltm.commercialRevShare,
                maxRevenueShare,
                licensorIpId,
                licenseTemplate,
                licenseTermsId
            );
        }
        if (ltm.commercialRevShare > MAX_COMMERCIAL_REVENUE_SHARE) {
            revert Errors.LicenseToken__InvalidRoyaltyPercent(
                ltm.commercialRevShare,
                licensorIpId,
                licenseTemplate,
                licenseTermsId
            );
        }
        LicenseTokenStorage storage $ = _getLicenseTokenStorage();
        startLicenseTokenId = $.totalMintedTokens;
        $.totalMintedTokens += amount;

        $.licensorIpTotalTokens[licensorIpId] += amount;

        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = startLicenseTokenId + i;
            $.licenseTokenMetadatas[tokenId] = ltm;
            _safeMint(receiver, tokenId);
            emit LicenseTokenMinted(minter, receiver, tokenId);
        }
    }

    /// @notice Burns the License Tokens (LTs) for the given token IDs.
    /// @param holder The address of the holder of the License Tokens.
    /// @param tokenIds An array of IDs of the License Tokens to be burned.
    function burnLicenseTokens(address holder, uint256[] calldata tokenIds) external onlyLicensingModule {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _burn(tokenIds[i]);
        }
    }

    /// @notice Validates License Tokens for registering a derivative IP.
    /// @dev This function checks if the License Tokens are valid for the derivative IP registration process.
    /// The function will be called by LicensingModule when registering a derivative IP with license tokens.
    /// @param caller The address of the caller who register derivative with the given tokens.
    /// @param childIpId The ID of the derivative IP.
    /// @param tokenIds An array of IDs of the License Tokens to validate for the derivative
    /// IP to register as derivative of the licensor IPs which minted the license tokens.
    /// @return licenseTemplate The address of the License Template associated with the License Tokens.
    /// @return licensorIpIds An array of licensor IPs associated with each License Token.
    /// @return licenseTermsIds An array of License Terms associated with each validated License Token.
    /// @return commercialRevShares An array of commercial revenue share percentages associated with each License Token.
    function validateLicenseTokensForDerivative(
        address caller,
        address childIpId,
        uint256[] calldata tokenIds
    )
        external
        view
        returns (
            address licenseTemplate,
            address[] memory licensorIpIds,
            uint256[] memory licenseTermsIds,
            uint32[] memory commercialRevShares
        )
    {
        LicenseTokenStorage storage $ = _getLicenseTokenStorage();

        // If an IP has minted license tokens, has derivative IPs or is a derivative itself, it cannot link to parents
        // The check if an IP has derivatives or is a derivative itself is in license registry registerDerivativeIp()
        // The check if the child ip already minted license tokens is done in the line below
        if ($.licensorIpTotalTokens[childIpId] != 0) {
            revert Errors.LicenseToken__ChildIPAlreadyHasBeenMintedLicenseTokens(childIpId);
        }

        licenseTemplate = $.licenseTokenMetadatas[tokenIds[0]].licenseTemplate;
        licensorIpIds = new address[](tokenIds.length);
        licenseTermsIds = new uint256[](tokenIds.length);
        commercialRevShares = new uint32[](tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            LicenseTokenMetadata memory ltm = $.licenseTokenMetadatas[tokenIds[i]];
            address tokenOwner = ownerOf(tokenIds[i]);
            if (ownerOf(tokenIds[i]) != caller && tokenOwner != childIpId) {
                revert Errors.LicenseToken__CallerAndChildIPNotTokenOwner(tokenIds[i], caller, childIpId, tokenOwner);
            }
            if (licenseTemplate != ltm.licenseTemplate) {
                revert Errors.LicenseToken__AllLicenseTokensMustFromSameLicenseTemplate(
                    licenseTemplate,
                    ltm.licenseTemplate
                );
            }
            if (isLicenseTokenRevoked(tokenIds[i])) {
                revert Errors.LicenseToken__RevokedLicense(tokenIds[i]);
            }

            licensorIpIds[i] = ltm.licensorIpId;
            licenseTermsIds[i] = ltm.licenseTermsId;
            commercialRevShares[i] = ltm.commercialRevShare;
        }
    }

    /// @notice Returns the total number of minted License Tokens since beginning,
    /// the number won't decrease when license tokens are burned.
    /// @return The total number of minted License Tokens.
    function totalMintedTokens() external view returns (uint256) {
        return _getLicenseTokenStorage().totalMintedTokens;
    }

    /// @notice Returns the license data for the given license ID
    /// @param tokenId The ID of the license token
    function getLicenseTokenMetadata(uint256 tokenId) external view returns (LicenseTokenMetadata memory) {
        return _getLicenseTokenStorage().licenseTokenMetadatas[tokenId];
    }

    /// @notice Returns the ID of the IP asset that is the licensor of the given license ID
    /// @param tokenId The ID of the license token
    function getLicensorIpId(uint256 tokenId) external view returns (address) {
        return _getLicenseTokenStorage().licenseTokenMetadatas[tokenId].licensorIpId;
    }

    /// @notice Returns the ID of the license terms that are used for the given license ID
    /// @param tokenId The ID of the license token
    function getLicenseTermsId(uint256 tokenId) external view returns (uint256) {
        return _getLicenseTokenStorage().licenseTokenMetadatas[tokenId].licenseTermsId;
    }

    /// @notice Returns the address of the license template that is used for the given license ID
    /// @param tokenId The ID of the license token
    function getLicenseTemplate(uint256 tokenId) external view returns (address) {
        return _getLicenseTokenStorage().licenseTokenMetadatas[tokenId].licenseTemplate;
    }

    /// @notice Retrieves the total number of License Tokens minted for a given licensor IP.
    /// @param licensorIpId The ID of the licensor IP.
    /// @return The total number of License Tokens minted for the licensor IP.
    function getTotalTokensByLicensor(address licensorIpId) external view returns (uint256) {
        return _getLicenseTokenStorage().licensorIpTotalTokens[licensorIpId];
    }

    /// @notice Returns true if the license has been revoked (licensor IP tagged after a dispute in
    /// the dispute module). If the tag is removed, the license is not revoked anymore.
    /// @return isRevoked True if the license is revoked
    function isLicenseTokenRevoked(uint256 tokenId) public view returns (bool) {
        LicenseTokenStorage storage $ = _getLicenseTokenStorage();
        return DISPUTE_MODULE.isIpTagged($.licenseTokenMetadatas[tokenId].licensorIpId);
    }

    /// @notice ERC721 OpenSea metadata JSON representation of the LNFT parameters
    /// @dev Expect LicenseTemplate.toJson to return {'trait_type: 'value'},{'trait_type': 'value'},...,{...}
    /// (last attribute must not have a comma at the end)
    function tokenURI(
        uint256 id
    ) public view virtual override(ERC721Upgradeable, IERC721Metadata) returns (string memory) {
        _requireOwned(id);
        LicenseTokenStorage storage $ = _getLicenseTokenStorage();

        LicenseTokenMetadata memory ltm = $.licenseTokenMetadatas[id];
        string memory licensorIpIdHex = ltm.licensorIpId.toHexString();

        /* solhint-disable */
        // Follows the OpenSea standard for JSON metadata

        // base json, open the attributes array
        string memory json = string(
            abi.encodePacked(
                "{",
                '"name": "Story Protocol License #',
                id.toString(),
                '",',
                '"description": "License agreement stating the terms of a Story Protocol IPAsset",',
                '"external_url": "https://protocol.storyprotocol.xyz/ipa/',
                licensorIpIdHex,
                '",',
                '"image": "',
                $.imageUrl,
                '",',
                '"attributes": ['
            )
        );

        json = string(abi.encodePacked(json, ILicenseTemplate(ltm.licenseTemplate).toJson(ltm.licenseTermsId)));

        // append the common license attributes
        json = string(
            abi.encodePacked(
                json,
                '{"trait_type": "Licensor", "value": "',
                licensorIpIdHex,
                '"},',
                '{"trait_type": "License Template", "value": "',
                ltm.licenseTemplate.toHexString(),
                '"},',
                '{"trait_type": "License Terms ID", "value": "',
                ltm.licenseTermsId.toString(),
                '"},',
                '{"trait_type": "Transferable", "value": "',
                ltm.transferable ? "true" : "false",
                '"},',
                '{"trait_type": "Revoked", "value": "',
                isLicenseTokenRevoked(id) ? "true" : "false",
                '"}'
            )
        );

        // close the attributes array and the json metadata object
        json = string(abi.encodePacked(json, "]}"));

        /* solhint-enable */

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        LicenseTokenStorage storage $ = _getLicenseTokenStorage();
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            LicenseTokenMetadata memory ltm = $.licenseTokenMetadatas[tokenId];
            if (isLicenseTokenRevoked(tokenId)) {
                revert Errors.LicenseToken__RevokedLicense(tokenId);
            }
            if (!ltm.transferable) {
                // True if from == licensor
                if (from != ltm.licensorIpId) {
                    revert Errors.LicenseToken__NotTransferable();
                }
            }
        }
        return super._update(to, tokenId, auth);
    }

    /// @dev Returns the storage struct of LicenseToken.
    function _getLicenseTokenStorage() private pure returns (LicenseTokenStorage storage $) {
        assembly {
            $.slot := LicenseTokenStorageLocation
        }
    }

    /// @dev Hook to authorize the upgrade according to UUPSUpgradeable
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
