// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^1.0.0

#[starknet::contract]
mod VestingWallet {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::finance::vesting::VestingComponent;
    use starknet::ContractAddress;

    const START: u64 = 0;
    const DURATION: u64 = 0; // 0 day
    const CLIFF_DURATION: u64 = 0; // 0 day

    component!(path: VestingComponent, storage: vesting, event: VestingEvent);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    // External
    #[abi(embed_v0)]
    impl VestingImpl = VestingComponent::VestingImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;

    // Internal
    impl VestingInternalImpl = VestingComponent::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        vesting: VestingComponent::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        VestingEvent: VestingComponent::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.vesting.initializer(START, DURATION, CLIFF_DURATION);
        self.ownable.initializer(owner);
    }

    impl VestingSchedule of VestingComponent::VestingScheduleTrait<ContractState> {
        fn calculate_vested_amount(
            self: @VestingComponent::ComponentState<ContractState>,
            token: ContractAddress,
            total_allocation: u256,
            timestamp: u64,
            start: u64,
            duration: u64,
            cliff: u64,
        ) -> u256 {
            // TODO: Must be implemented according to the desired vesting schedule;
            0
        }
    }
}
