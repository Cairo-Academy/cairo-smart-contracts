use starknet::class_hash::ClassHash;
 
#[starknet::interface]
pub trait IUpgradeableContract<TContractState> {
    fn upgrade(ref self: TContractState, impl_hash: ClassHash);
    fn version(self: @TContractState) -> u8;
}
 
#[starknet::contract]
pub mod UpgradeableContract_V1 {
    use starknet::class_hash::ClassHash;
    use core::num::traits::Zero;
 
    #[storage]
    struct Storage {}
 
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Upgraded: Upgraded,
    }
 
    #[derive(Drop, starknet::Event)]
    struct Upgraded {
        implementation: ClassHash,
    }
 
    #[abi(embed_v0)]
    impl UpgradeableContract of super::IUpgradeableContract<ContractState> {
        fn upgrade(ref self: ContractState, impl_hash: ClassHash) {
            assert(impl_hash.is_non_zero(), 'Class hash cannot be zero');
            starknet::syscalls::replace_class_syscall(impl_hash).unwrap();
            self.emit(Event::Upgraded(Upgraded { implementation: impl_hash }))
        }
 
        fn version(self: @ContractState) -> u8 {
            1
        }
    }
}