// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^1.0.0

#[starknet::contract]
mod MyGovernor {
    use openzeppelin::governance::governor::{DefaultConfig, GovernorComponent};
    use openzeppelin::governance::governor::extensions::{
    	GovernorCountingSimpleComponent, GovernorSettingsComponent,
    	GovernorTimelockExecutionComponent, GovernorVotesQuorumFractionComponent
    };
    use openzeppelin::governance::governor::extensions::GovernorSettingsComponent::InternalTrait as GovernorSettingsInternalTrait;
    use openzeppelin::governance::governor::extensions::GovernorTimelockExecutionComponent::InternalTrait as GovernorTimelockExecutionInternalTrait;
    use openzeppelin::governance::governor::extensions::GovernorVotesQuorumFractionComponent::InternalTrait as GovernorVotesQuorumFractionInternalTrait;
    use openzeppelin::governance::governor::GovernorComponent::{
    	InternalExtendedImpl, InternalTrait as GovernorInternalTrait
    };
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::utils::cryptography::snip12::SNIP12Metadata;
    use starknet::{ClassHash, ContractAddress};

    const QUORUM_NUMERATOR: u256 = 40; // 4%
    const VOTING_DELAY: u64 = 86400; // 1 day
    const VOTING_PERIOD: u64 = 604800; // 1 week
    const PROPOSAL_THRESHOLD: u256 = 0;

    component!(path: GovernorComponent, storage: governor, event: GovernorEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: GovernorCountingSimpleComponent, storage: governor_counting, event: GovernorCountingSimpleEvent);
    component!(path: GovernorVotesQuorumFractionComponent, storage: governor_votes, event: GovernorVotesEvent);
    component!(path: GovernorSettingsComponent, storage: governor_settings, event: GovernorSettingsEvent);
    component!(path: GovernorTimelockExecutionComponent, storage: governor_timelock_execution, event: GovernorTimelockExecutionEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    // Extensions (external)
    #[abi(embed_v0)]
    impl QuorumFractionImpl = GovernorVotesQuorumFractionComponent::QuorumFractionImpl<ContractState>;
    #[abi(embed_v0)]
    impl GovernorSettingsAdminImpl = GovernorSettingsComponent::GovernorSettingsAdminImpl<ContractState>;
    #[abi(embed_v0)]
    impl TimelockedImpl = GovernorTimelockExecutionComponent::TimelockedImpl<ContractState>;

    // Extensions (internal)
    impl GovernorCountingSimpleImpl = GovernorCountingSimpleComponent::GovernorCounting<ContractState>;
    impl GovernorQuorumImpl = GovernorVotesQuorumFractionComponent::GovernorQuorum<ContractState>;
    impl GovernorVotesImpl = GovernorVotesQuorumFractionComponent::GovernorVotes<ContractState>;
    impl GovernorSettingsImpl = GovernorSettingsComponent::GovernorSettings<ContractState>;
    impl GovernorTimelockExecutionImpl = GovernorTimelockExecutionComponent::GovernorExecution<ContractState>;

    // Governor Core
    #[abi(embed_v0)]
    impl GovernorImpl = GovernorComponent::GovernorImpl<ContractState>;

    // Internal
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    // SRC5
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        governor: GovernorComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        governor_counting: GovernorCountingSimpleComponent::Storage,
        #[substorage(v0)]
        governor_votes: GovernorVotesQuorumFractionComponent::Storage,
        #[substorage(v0)]
        governor_settings: GovernorSettingsComponent::Storage,
        #[substorage(v0)]
        governor_timelock_execution: GovernorTimelockExecutionComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        GovernorEvent: GovernorComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        GovernorCountingSimpleEvent: GovernorCountingSimpleComponent::Event,
        #[flat]
        GovernorVotesEvent: GovernorVotesQuorumFractionComponent::Event,
        #[flat]
        GovernorSettingsEvent: GovernorSettingsComponent::Event,
        #[flat]
        GovernorTimelockExecutionEvent: GovernorTimelockExecutionComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        votes_token: ContractAddress,
        timelock_controller: ContractAddress,
    ) {
        self.governor.initializer();
        self.governor_votes.initializer(votes_token, QUORUM_NUMERATOR);
        self.governor_settings.initializer(VOTING_DELAY, VOTING_PERIOD, PROPOSAL_THRESHOLD);
        self.governor_timelock_execution.initializer(timelock_controller);
    }

    //
    // SNIP12 Metadata
    //
    
    impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            'OpenZeppelin Governor'
        }

        fn version() -> felt252 {
            'v1'
        }
    }

    //
    // Upgradeable
    //
    
    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.governor.assert_only_governance();
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}
