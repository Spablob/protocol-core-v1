// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRoyaltyModule } from "contracts/interfaces/modules/royalty/IRoyaltyModule.sol";
import { IIPAssetRegistry } from "contracts/interfaces/registries/IIPAssetRegistry.sol";
import { ILicensingModule } from "contracts/interfaces/modules/licensing/ILicensingModule.sol";
import { IPILicenseTemplate, PILTerms } from "contracts/interfaces/modules/licensing/IPILicenseTemplate.sol";

import { BaseTest } from "../../utils/BaseTest.t.sol";
import { ExternalRoyaltyPolicy } from "../../mocks/policy/ExternalRoyaltyPolicy.sol";
import { MockERC721 } from "../../mocks/token/MockERC721.sol";
import { MockIPGraph } from "../../mocks/MockIPGraph.sol";

contract ExternalRoyaltyPolicyTest is BaseTest {
    ExternalRoyaltyPolicy externalRoyaltyPolicy;
    address ROYALTY_MODULE = address(0xD2f60c40fEbccf6311f8B47c4f2Ec6b040400086);
    address WIP = address(0x1514000000000000000000000000000000000000);
    address IP_ASSET_REGISTRY = address(0x77319B4031e6eF1250907aa00018B8B1c67a244b);
    address PIL_TEMPLATE = address(0x2E896b0b2Fdb7457499B56AAaA4AE55BCB4Cd316);
    address LICENSE_MODULE = address(0x04fbd8a2e56dd85CFD5500A4A4DfA955B9f1dE6f);
    uint256 MAX_PERCENT = 100e6;

    uint256 commDerivTermsId;
    mapping(uint256 tokenId => address ipAccount) internal ipAcct;

    function setUp() public virtual override {
        // Fork the desired network where UMA contracts are deployed
        uint256 forkId = vm.createFork("https://aeneid.storyrpc.io/");
        vm.selectFork(forkId);

        vm.etch(address(0x0101), address(new MockIPGraph()).code);

        externalRoyaltyPolicy = new ExternalRoyaltyPolicy(ROYALTY_MODULE);
        vm.label(address(externalRoyaltyPolicy), "ExternalRoyaltyPolicy");
        IRoyaltyModule(ROYALTY_MODULE).registerExternalRoyaltyPolicy(address(externalRoyaltyPolicy));

        MockERC721 mockNft = new MockERC721("MockNft");
        mockNft.mintId(address(1), 1000);
        mockNft.mintId(address(2), 2000);

        ipAcct[1000] = IIPAssetRegistry(IP_ASSET_REGISTRY).register(block.chainid, address(mockNft), 1000);
        ipAcct[2000] = IIPAssetRegistry(IP_ASSET_REGISTRY).register(block.chainid, address(mockNft), 2000);

        commDerivTermsId = IPILicenseTemplate(PIL_TEMPLATE).registerLicenseTerms(
            PILTerms({
                transferable: true,
                royaltyPolicy: address(externalRoyaltyPolicy),
                defaultMintingFee: 0,
                expiration: 0,
                commercialUse: true,
                commercialAttribution: false,
                commercializerChecker: address(0),
                commercializerCheckerData: "",
                commercialRevShare: 10e6,
                commercialRevCeiling: 0,
                derivativesAllowed: true,
                derivativesAttribution: false,
                derivativesApproval: false,
                derivativesReciprocal: true,
                derivativeRevCeiling: 0,
                currency: WIP,
                uri: ""
            })
        );

        // attach terms to root
        vm.prank(ipAcct[1000]);
        ILicensingModule(LICENSE_MODULE).attachLicenseTerms(ipAcct[1000], address(PIL_TEMPLATE), commDerivTermsId);

        address[] memory parentIpIds = new address[](1);
        uint256[] memory licenseTermsIds = new uint256[](1);

        // register derivatives
        parentIpIds[0] = ipAcct[1000];
        licenseTermsIds[0] = commDerivTermsId;
        vm.prank(ipAcct[2000]);
        ILicensingModule(LICENSE_MODULE).registerDerivative(
            ipAcct[2000],
            parentIpIds,
            licenseTermsIds,
            address(PIL_TEMPLATE),
            "",
            0,
            100e6,
            100e6
        );
    }

    function test_claim_BelowThreshold() public {
        address ipRoyaltyVault = IRoyaltyModule(ROYALTY_MODULE).ipRoyaltyVaults(ipAcct[2000]);
        vm.label(ipRoyaltyVault, "ipRoyaltyVault");
        assertEq(IERC20(ipRoyaltyVault).balanceOf(address(externalRoyaltyPolicy)), 100e6);

        vm.prank(ipAcct[2000]);
        address scientist = address(1);
        address investor = address(2);
        uint32 thresholdPercent = 30e6;
        externalRoyaltyPolicy.assign(ipAcct[2000], scientist, investor, thresholdPercent, 1 ether);

        vm.startPrank(0xEA8a282cA8A010e42C13CF5E121DeeC97A021B88);
        vm.deal(0xEA8a282cA8A010e42C13CF5E121DeeC97A021B88, 2 ether);
        IWIP(WIP).deposit{ value: 2 ether }();
        IERC20(WIP).approve(address(ROYALTY_MODULE), 2 ether);
        IRoyaltyModule(ROYALTY_MODULE).payRoyaltyOnBehalf(
            ipAcct[2000],
            address(0xEA8a282cA8A010e42C13CF5E121DeeC97A021B88),
            WIP,
            0.9 ether
        );
        vm.stopPrank();

        externalRoyaltyPolicy.claim(ipAcct[2000]);

        assertEq(IERC20(WIP).balanceOf(address(externalRoyaltyPolicy)), 0);
        assertEq(IERC20(WIP).balanceOf(investor), 0.9 ether);
        assertEq(IERC20(WIP).balanceOf(scientist), 0);
    }

    function test_claim_AboveThreshold() public {
        address ipRoyaltyVault = IRoyaltyModule(ROYALTY_MODULE).ipRoyaltyVaults(ipAcct[2000]);
        vm.label(ipRoyaltyVault, "ipRoyaltyVault");
        assertEq(IERC20(ipRoyaltyVault).balanceOf(address(externalRoyaltyPolicy)), 100e6);

        vm.prank(ipAcct[2000]);
        address scientist = address(1);
        address investor = address(2);
        uint32 thresholdPercent = 30e6;
        externalRoyaltyPolicy.assign(ipAcct[2000], scientist, investor, thresholdPercent, 1 ether);

        vm.startPrank(0xEA8a282cA8A010e42C13CF5E121DeeC97A021B88);
        vm.deal(0xEA8a282cA8A010e42C13CF5E121DeeC97A021B88, 2 ether);
        IWIP(WIP).deposit{ value: 2 ether }();
        IERC20(WIP).approve(address(ROYALTY_MODULE), 2 ether);
        IRoyaltyModule(ROYALTY_MODULE).payRoyaltyOnBehalf(
            ipAcct[2000],
            address(0xEA8a282cA8A010e42C13CF5E121DeeC97A021B88),
            WIP,
            1.5 ether
        );
        vm.stopPrank();

        externalRoyaltyPolicy.claim(ipAcct[2000]);

        assertEq(IERC20(WIP).balanceOf(address(externalRoyaltyPolicy)), 0);
        assertEq(IERC20(WIP).balanceOf(investor), 1.15 ether);
        assertEq(IERC20(WIP).balanceOf(scientist), 0.35 ether);

        vm.startPrank(0xEA8a282cA8A010e42C13CF5E121DeeC97A021B88);
        IRoyaltyModule(ROYALTY_MODULE).payRoyaltyOnBehalf(
            ipAcct[2000],
            address(0xEA8a282cA8A010e42C13CF5E121DeeC97A021B88),
            WIP,
            0.5 ether
        );
        vm.stopPrank();

        externalRoyaltyPolicy.claim(ipAcct[2000]);

        assertEq(IERC20(WIP).balanceOf(address(externalRoyaltyPolicy)), 0);
        assertEq(IERC20(WIP).balanceOf(investor), 1.3 ether);
        assertEq(IERC20(WIP).balanceOf(scientist), 0.7 ether);
        assertEq(externalRoyaltyPolicy.totalClaimed(ipAcct[2000]), 2 ether);
    }

    function test_claim_AboveAndBelowThreshold() public {
        address ipRoyaltyVault = IRoyaltyModule(ROYALTY_MODULE).ipRoyaltyVaults(ipAcct[2000]);
        vm.label(ipRoyaltyVault, "ipRoyaltyVault");
        assertEq(IERC20(ipRoyaltyVault).balanceOf(address(externalRoyaltyPolicy)), 100e6);

        vm.prank(ipAcct[2000]);
        address scientist = address(1);
        address investor = address(2);
        uint32 thresholdPercent = 30e6;
        externalRoyaltyPolicy.assign(ipAcct[2000], scientist, investor, thresholdPercent, 1 ether);

        vm.startPrank(0xEA8a282cA8A010e42C13CF5E121DeeC97A021B88);
        vm.deal(0xEA8a282cA8A010e42C13CF5E121DeeC97A021B88, 2 ether);
        IWIP(WIP).deposit{ value: 2 ether }();
        IERC20(WIP).approve(address(ROYALTY_MODULE), 2 ether);
        IRoyaltyModule(ROYALTY_MODULE).payRoyaltyOnBehalf(
            ipAcct[2000],
            address(0xEA8a282cA8A010e42C13CF5E121DeeC97A021B88),
            WIP,
            2 ether
        );
        vm.stopPrank();

        externalRoyaltyPolicy.claim(ipAcct[2000]);

        assertEq(IERC20(WIP).balanceOf(address(externalRoyaltyPolicy)), 0);
        assertEq(IERC20(WIP).balanceOf(investor), 1.3 ether);
        assertEq(IERC20(WIP).balanceOf(scientist), 0.7 ether);
        assertEq(externalRoyaltyPolicy.totalClaimed(ipAcct[2000]), 2 ether);
    }
}

interface IWIP is IERC20 {
    function deposit() external payable;
}
