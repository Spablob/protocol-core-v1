// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { IDisputeModule } from "../../../../interfaces/modules/dispute/IDisputeModule.sol";
import { IArbitrationPolicyUMA } from "../../../../interfaces/modules/dispute/policies/UMA/IArbitrationPolicyUMA.sol";
import { IOptimisticOracleV3 } from "../../../../interfaces/modules/dispute/policies/UMA/IOptimisticOracleV3.sol";
import { ProtocolPausableUpgradeable } from "../../../../pause/ProtocolPausableUpgradeable.sol";
import { Errors } from "../../../../lib/Errors.sol";

/// @title Arbitration Policy UMA
/// @notice The arbitration policy UMA acts as an enforcement layer for IP assets that allows raising and judging
/// disputes according to the UMA protocol rules.
contract ArbitrationPolicyUMA is
    IArbitrationPolicyUMA,
    ProtocolPausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    /// @notice Dispute module address
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable DISPUTE_MODULE;

    /// @notice UMA Optimistic oracle v3 address
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IOptimisticOracleV3 public immutable OPTIMISTIC_ORACLE_V3;

    /// @dev Storage structure for the ArbitrationPolicyUMA
    /// @param minLiveness The minimum liveness value
    /// @param maxLiveness The maximum liveness value
    /// @param maxBonds The maximum bond size for each token
    /// @param disputeIdToAssertionId The mapping of dispute id to assertion id
    /// @param assertionIdToDisputeId The mapping of assertion id to dispute id
    /// @param counterEvidenceHashes The mapping of assertion id to counter evidence hash
    /// @custom:storage-location erc7201:story-protocol.ArbitrationPolicyUMA
    struct ArbitrationPolicyUMAStorage {
        uint64 minLiveness;
        uint64 maxLiveness;
        mapping(address token => uint256 maxBondSize) maxBonds;
        mapping(uint256 disputeId => bytes32 assertionId) disputeIdToAssertionId;
        mapping(bytes32 assertionId => uint256 disputeId) assertionIdToDisputeId;
        mapping(bytes32 assertionId => bytes32 counterEvidenceHash) counterEvidenceHashes;
    }

    // keccak256(abi.encode(uint256(keccak256("story-protocol.ArbitrationPolicyUMA")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant ArbitrationPolicyUMAStorageLocation =
        0xbd39630b628d883a3167c4982acf741cbddb24bae6947600210f8eb1db515300;

    /// @dev Restricts the calls to the dispute module
    modifier onlyDisputeModule() {
        if (msg.sender != DISPUTE_MODULE) revert Errors.ArbitrationPolicyUMA__NotDisputeModule();
        _;
    }

    /// Constructor
    /// @param disputeModule The address of the dispute module
    /// @param optimisticOracleV3 The address of the optimistic oracle v3
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address disputeModule, address optimisticOracleV3) {
        if (disputeModule == address(0)) revert Errors.ArbitrationPolicyUMA__ZeroDisputeModule();
        if (optimisticOracleV3 == address(0)) revert Errors.ArbitrationPolicyUMA__ZeroOptimisticOracleV3();

        DISPUTE_MODULE = disputeModule;
        OPTIMISTIC_ORACLE_V3 = IOptimisticOracleV3(optimisticOracleV3);
        _disableInitializers();
    }

    /// @notice Initializer for this implementation contract
    /// @param accessManager The address of the protocol admin roles contract
    function initialize(address accessManager) external initializer {
        if (accessManager == address(0)) revert Errors.ArbitrationPolicyUMA__ZeroAccessManager();

        __ProtocolPausable_init(accessManager);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
    }

    /// @notice Sets the liveness for UMA disputes
    /// @param minLiveness The minimum liveness value
    /// @param maxLiveness The maximum liveness value
    function setLiveness(uint64 minLiveness, uint64 maxLiveness) external restricted {
        if (minLiveness == 0) revert Errors.ArbitrationPolicyUMA__ZeroMinLiveness();
        if (maxLiveness == 0) revert Errors.ArbitrationPolicyUMA__ZeroMaxLiveness();
        if (minLiveness > maxLiveness) revert Errors.ArbitrationPolicyUMA__MinLivenessAboveMax();

        ArbitrationPolicyUMAStorage storage $ = _getArbitrationPolicyUMAStorage();
        $.minLiveness = minLiveness;
        $.maxLiveness = maxLiveness;

        emit LivenessSet(minLiveness, maxLiveness);
    }

    /// @notice Sets the max bond for UMA disputes
    /// @param token The token address
    /// @param maxBond The maximum bond value
    function setMaxBond(address token, uint256 maxBond) external restricted {
        ArbitrationPolicyUMAStorage storage $ = _getArbitrationPolicyUMAStorage();
        $.maxBonds[token] = maxBond;

        emit MaxBondSet(token, maxBond);
    }

    /// @notice Executes custom logic on raising dispute
    /// @dev Enforced to be only callable by the DisputeModule
    /// @param caller Address of the caller
    /// @param data The arbitrary data used to raise the dispute
    function onRaiseDispute(address caller, bytes calldata data) external onlyDisputeModule nonReentrant {
        (bytes memory claim, uint64 liveness, address currency, uint256 bond, bytes32 identifier) = abi.decode(
            data,
            (bytes, uint64, address, uint256, bytes32)
        );

        ArbitrationPolicyUMAStorage storage $ = _getArbitrationPolicyUMAStorage();
        if (liveness < $.minLiveness) revert Errors.ArbitrationPolicyUMA__LivenessBelowMin();
        if (liveness > $.maxLiveness) revert Errors.ArbitrationPolicyUMA__LivenessAboveMax();
        if (bond > $.maxBonds[currency]) revert Errors.ArbitrationPolicyUMA__BondAboveMax();

        bytes32 assertionId = OPTIMISTIC_ORACLE_V3.assertTruth(
            claim,
            caller, // asserter
            address(this), // callbackRecipient
            address(0), // escalationManager
            liveness,
            IERC20(currency),
            bond,
            identifier,
            bytes32(0) // domainId
        );

        uint256 disputeId = IDisputeModule(DISPUTE_MODULE).disputeCounter();
        $.assertionIdToDisputeId[assertionId] = disputeId;
        $.disputeIdToAssertionId[disputeId] = assertionId;

        emit DisputeRaisedUMA(disputeId, caller, claim, liveness, currency, bond, identifier);
    }

    /// @notice Executes custom logic on disputing judgement
    /// @dev Enforced to be only callable by the DisputeModule
    /// @param disputeId The dispute id
    /// @param decision The decision of the dispute
    /// @param data The arbitrary data used to set the dispute judgement
    function onDisputeJudgement(uint256 disputeId, bool decision, bytes calldata data) external onlyDisputeModule {}

    /// @notice Executes custom logic on disputing cancel
    /// @dev Enforced to be only callable by the DisputeModule
    /// @param caller Address of the caller
    /// @param disputeId The dispute id
    /// @param data The arbitrary data used to cancel the dispute
    function onDisputeCancel(address caller, uint256 disputeId, bytes calldata data) external onlyDisputeModule {
        revert Errors.ArbitrationPolicyUMA__CannotCancel();
    }

    /// @notice Executes custom logic on resolving dispute
    /// @dev Enforced to be only callable by the DisputeModule
    /// @param caller Address of the caller
    /// @param disputeId The dispute id
    /// @param data The arbitrary data used to resolve the dispute
    function onResolveDispute(address caller, uint256 disputeId, bytes calldata data) external onlyDisputeModule {}

    /// @notice Allows the IP that was targeted to dispute the assertion while providing counter evidence
    /// @param assertionId The identifier of the assertion that was disputed
    /// @param counterEvidenceHash The hash of the counter evidence
    function disputeAssertion(bytes32 assertionId, bytes32 counterEvidenceHash) external nonReentrant {
        if (counterEvidenceHash == bytes32(0)) revert Errors.ArbitrationPolicyUMA__NoCounterEvidence();

        ArbitrationPolicyUMAStorage storage $ = _getArbitrationPolicyUMAStorage();
        uint256 disputeId = $.assertionIdToDisputeId[assertionId];
        if (disputeId == 0) revert Errors.ArbitrationPolicyUMA__DisputeNotFound();

        (address targetIpId, , address arbitrationPolicy, , , , uint256 parentDisputeId) = IDisputeModule(
            DISPUTE_MODULE
        ).disputes(disputeId);

        if (msg.sender != targetIpId) revert Errors.ArbitrationPolicyUMA__OnlyTargetIpIdCanDispute();
        if (arbitrationPolicy != address(this)) revert Errors.ArbitrationPolicyUMA__OnlyDisputePolicyUMA();
        if (parentDisputeId > 0) revert Errors.ArbitrationPolicyUMA__CannotDisputeAssertionIfTagIsInherited();

        $.counterEvidenceHashes[assertionId] = counterEvidenceHash;

        OPTIMISTIC_ORACLE_V3.disputeAssertion(assertionId, targetIpId);

        emit AssertionDisputed(assertionId, counterEvidenceHash);
    }

    /// @notice Callback function that is called by Optimistic Oracle V3 when an assertion is resolved
    /// @param assertionId The identifier of the assertion that was resolved
    /// @param assertedTruthfully Whether the assertion was resolved as truthful or not
    function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) external nonReentrant {
        if (msg.sender != address(OPTIMISTIC_ORACLE_V3)) revert Errors.ArbitrationPolicyUMA__NotOptimisticOracleV3();

        ArbitrationPolicyUMAStorage storage $ = _getArbitrationPolicyUMAStorage();
        uint256 disputeId = $.assertionIdToDisputeId[assertionId];

        IDisputeModule(DISPUTE_MODULE).setDisputeJudgement(disputeId, assertedTruthfully, "");
    }

    /// @notice Callback function that is called by Optimistic Oracle V3 when an assertion is disputed
    /// @param assertionId The identifier of the assertion that was disputed
    function assertionDisputedCallback(bytes32 assertionId) external {
        if (msg.sender != address(OPTIMISTIC_ORACLE_V3)) revert Errors.ArbitrationPolicyUMA__NotOptimisticOracleV3();

        ArbitrationPolicyUMAStorage storage $ = _getArbitrationPolicyUMAStorage();
        if ($.counterEvidenceHashes[assertionId] == bytes32(0)) revert Errors.ArbitrationPolicyUMA__NoCounterEvidence();
    }

    /// @notice Returns the minimum liveness for UMA disputes
    function minLiveness() external view returns (uint64) {
        return _getArbitrationPolicyUMAStorage().minLiveness;
    }

    /// @notice Returns the maximum liveness for UMA disputes
    function maxLiveness() external view returns (uint64) {
        return _getArbitrationPolicyUMAStorage().maxLiveness;
    }

    /// @notice Returns the maximum bond for a given token for UMA disputes
    /// @param token The token address
    function maxBonds(address token) external view returns (uint256) {
        return _getArbitrationPolicyUMAStorage().maxBonds[token];
    }

    /// @notice Returns the assertion id for a given dispute id
    /// @param disputeId The dispute id
    function disputeIdToAssertionId(uint256 disputeId) external view returns (bytes32) {
        return _getArbitrationPolicyUMAStorage().disputeIdToAssertionId[disputeId];
    }

    /// @notice Returns the dispute id for a given assertion id
    /// @param assertionId The assertion id
    function assertionIdToDisputeId(bytes32 assertionId) external view returns (uint256) {
        return _getArbitrationPolicyUMAStorage().assertionIdToDisputeId[assertionId];
    }

    /// @dev Hook to authorize the upgrade according to UUPSUpgradeable
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override restricted {}

    /// @dev Returns the storage struct of ArbitrationPolicyUMA
    function _getArbitrationPolicyUMAStorage() private pure returns (ArbitrationPolicyUMAStorage storage $) {
        assembly {
            $.slot := ArbitrationPolicyUMAStorageLocation
        }
    }
}