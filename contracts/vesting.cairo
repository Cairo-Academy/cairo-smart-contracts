use core::array::Array;
use starknet::ContractAddress;

#[starknet::interface]
pub trait ITokenVesting<TContractState> {
    fn calculate_vested_amount(self: @TContractState, beneficiary: ContractAddress) -> u256;
    fn calculate_releasable_amount(self: @TContractState, beneficiary: ContractAddress) -> u256;
    fn get_beneficiary_count(self: @TContractState) -> u32;
    fn create_vesting_schedule(
        ref self: TContractState,
        beneficiary: ContractAddress,
        start: u64,
        cliff_duration: u64,
        total_duration: u64,
        amount: u256,
        revocable: bool,
    );
    fn release(ref self: TContractState, beneficiary: ContractAddress);
    fn release_my_tokens(ref self: TContractState);
    fn revoke(ref self: TContractState, beneficiary: ContractAddress);
    fn transfer_beneficiary(
        ref self: TContractState,
        previous_beneficiary: ContractAddress,
        new_beneficiary: ContractAddress,
    );
    fn get_beneficiaries(self: @TContractState) -> Array<ContractAddress>;
}

#[starknet::contract]
pub mod TokenVesting {
    use core::starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::{
        ContractAddress, contract_address_const, get_block_timestamp, get_caller_address,
        get_contract_address,
    };

    // Storage variables
    #[storage]
    struct Storage {
        token: ContractAddress,
        owner: ContractAddress,
        vesting_schedules: Map<ContractAddress, VestingSchedule>,
        beneficiaries_count: u32,
        beneficiaries_at_index: Map<u32, ContractAddress>,
        is_beneficiary: Map<ContractAddress, bool> // For quick lookups
    }
    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        VestingScheduleCreated: VestingScheduleCreated,
        TokensReleased: TokensReleased,
        VestingRevoked: VestingRevoked,
        BeneficiaryTransferred: BeneficiaryTransferred,
    }

    // Event emitted when a vesting schedule is created
    #[derive(Drop, starknet::Event)]
    pub struct VestingScheduleCreated {
        beneficiary: ContractAddress,
        amount: u256,
        start: u64,
        cliff: u64,
        duration: u64,
        revocable: bool,
    }

    // Event emitted when tokens are released
    #[derive(Drop, starknet::Event)]
    pub struct TokensReleased {
        #[key]
        beneficiary: ContractAddress,
        amount: u256,
    }

    // Event emitted when vesting is revoked
    #[derive(Drop, starknet::Event)]
    pub struct VestingRevoked {
        beneficiary: ContractAddress,
    }

    // Event emitted when beneficiary is transferred
    #[derive(Drop, starknet::Event)]
    pub struct BeneficiaryTransferred {
        previous_beneficiary: ContractAddress,
        new_beneficiary: ContractAddress,
    }

    // Struct to hold vesting schedule data
    #[derive(Copy, Drop, Serde, starknet::Store)]
    pub struct VestingSchedule {
        initialized: bool,
        beneficiary: ContractAddress,
        cliff: u64,
        start: u64,
        duration: u64,
        total_amount: u256,
        released_amount: u256,
        revocable: bool,
        revoked: bool,
    }

    // Constructor to initialize the contract
    #[constructor]
    fn constructor(ref self: ContractState, token_address: ContractAddress) {
        let caller = get_caller_address();
        self.owner.write(caller);
        self.token.write(token_address);
    }

    // External functions
    // Creates a vesting schedule for a beneficiary
    #[abi(embed_v0)]
    impl TokenVestingImpl of super::ITokenVesting<ContractState> {
        fn create_vesting_schedule(
            ref self: ContractState,
            beneficiary: ContractAddress,
            start: u64,
            cliff_duration: u64,
            total_duration: u64,
            amount: u256,
            revocable: bool,
        ) {
            let zero_addr: ContractAddress = contract_address_const::<0>();
            assert(beneficiary != zero_addr, 'Beneficiary cannot be 0');
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Caller is not the owner');

            assert(total_duration > 0, 'Duration must be > 0');
            assert(amount > 0, 'Amount must be > 0');

            let current_time = get_block_timestamp();
            let end_time = start + total_duration;
            assert(end_time > current_time, 'End time must be in future');

            let schedule = self.vesting_schedules.read(beneficiary);
            assert(!schedule.initialized, 'Schedule already exists');

            // Calculate cliff timestamp
            let cliff_timestamp = start + cliff_duration;

            // Create vesting schedule
            let new_schedule = VestingSchedule {
                initialized: true,
                beneficiary: beneficiary,
                cliff: cliff_timestamp,
                start: start,
                duration: total_duration,
                total_amount: amount,
                released_amount: (0),
                revocable: revocable,
                revoked: false,
            };

            self.vesting_schedules.write(beneficiary, new_schedule);

            // Add beneficiary to the mapping-based array
            self._add_beneficiary(beneficiary);

            // Emit event
            self
                .emit(
                    VestingScheduleCreated {
                        beneficiary,
                        amount,
                        start,
                        cliff: cliff_timestamp,
                        duration: total_duration,
                        revocable,
                    },
                );

            // Transfer tokens from caller to contract
            self._transferFrom(get_caller_address(), get_contract_address(), amount);
        }


        fn calculate_vested_amount(self: @ContractState, beneficiary: ContractAddress) -> u256 {
            let schedule = self.vesting_schedules.read(beneficiary);
            assert(schedule.initialized, 'No schedule for this address');

            let current_time = get_block_timestamp();

            if current_time < schedule.cliff {
                return (0);
            }

            if current_time >= schedule.start + schedule.duration || schedule.revoked {
                return schedule.total_amount;
            }

            // Calculate vested amount based on linear vesting
            let time_from_start = current_time - schedule.start;
            let vested_amount = schedule.total_amount
                * time_from_start.into()
                / schedule.duration.into();

            return vested_amount;
        }

        fn calculate_releasable_amount(self: @ContractState, beneficiary: ContractAddress) -> u256 {
            let schedule = self.vesting_schedules.read(beneficiary);
            assert(schedule.initialized, 'No schedule for this address');

            if schedule.revoked {
                return (0);
            }

            let vested_amount = self.calculate_vested_amount(beneficiary);
            return vested_amount - schedule.released_amount;
        }

        //can be used by admins to release tokens to users
        fn release(ref self: ContractState, beneficiary: ContractAddress) {
            let mut schedule = self.vesting_schedules.read(beneficiary);
            assert(schedule.initialized, 'No schedule for this address');
            assert(!schedule.revoked, 'Vesting has been revoked');

            let current_time = get_block_timestamp();
            assert(current_time >= schedule.cliff, 'Cliff period not passed');

            let releasable_amount = self.calculate_releasable_amount(beneficiary);
            assert(releasable_amount > 0, 'No tokens to release');

            // Update released amount
            schedule.released_amount = schedule.released_amount + releasable_amount;
            self.vesting_schedules.write(beneficiary, schedule);

            // Transfer tokens to beneficiary
            self._transfer(beneficiary, releasable_amount);
            self.emit(TokensReleased { beneficiary: beneficiary, amount: releasable_amount });
        }

        //lets users claim their tokens
        fn release_my_tokens(ref self: ContractState) {
            let caller = get_caller_address();
            let mut schedule = self.vesting_schedules.read(caller);
            assert(schedule.initialized, 'No schedule for caller');
            assert(!schedule.revoked, 'Vesting has been revoked');

            let current_time = get_block_timestamp();
            assert(current_time >= schedule.cliff, 'Cliff period not passed');

            let releasable_amount = self.calculate_releasable_amount(caller);
            assert(releasable_amount > 0, 'No tokens to release');

            // Update released amount
            schedule.released_amount = schedule.released_amount + releasable_amount;
            self.vesting_schedules.write(caller, schedule);

            // Transfer tokens to caller
            self._transfer(caller, releasable_amount);

            self.emit(TokensReleased { beneficiary: caller, amount: releasable_amount });
        }


        fn revoke(ref self: ContractState, beneficiary: ContractAddress) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Caller is not the owner');

            let mut schedule = self.vesting_schedules.read(beneficiary);
            assert(schedule.initialized, 'No schedule for this address');
            assert(schedule.revocable, 'Schedule is not revocable');
            assert(!schedule.revoked, 'Already revoked');

            let vested_amount = self.calculate_vested_amount(beneficiary);
            let refund_amount = schedule.total_amount - vested_amount;

            // Release any vested but unreleased tokens
            if vested_amount > schedule.released_amount {
                let releasable_amount = vested_amount - schedule.released_amount;
                schedule.released_amount = vested_amount;

                // Transfer vested tokens to beneficiary
                self._transfer(beneficiary, releasable_amount);

                self.emit(TokensReleased { beneficiary: beneficiary, amount: releasable_amount });
            }

            // Mark as revoked
            schedule.revoked = true;
            self.vesting_schedules.write(beneficiary, schedule);

            // Return unvested tokens to owner
            let _owner = self.owner.read();
            self._transfer(_owner, refund_amount);

            self.emit(VestingRevoked { beneficiary });
        }

        fn transfer_beneficiary(
            ref self: ContractState,
            previous_beneficiary: ContractAddress,
            new_beneficiary: ContractAddress,
        ) {
            let caller = get_caller_address();
            assert(caller == previous_beneficiary, 'Not authorized');
            let zero_addr: ContractAddress = contract_address_const::<0>();
            assert(new_beneficiary != zero_addr, 'Beneficiary cannot be 0');

            let new_schedule = self.vesting_schedules.read(new_beneficiary);
            assert(!new_schedule.initialized, 'New beneficiary has schedule');

            let mut old_schedule = self.vesting_schedules.read(previous_beneficiary);
            assert(old_schedule.initialized, 'No schedule for old address');
            assert(!old_schedule.revoked, 'Schedule has been revoked');

            // Create new schedule for new beneficiary
            let transfer_schedule = VestingSchedule {
                initialized: true,
                beneficiary: new_beneficiary,
                cliff: old_schedule.cliff,
                start: old_schedule.start,
                duration: old_schedule.duration,
                total_amount: old_schedule.total_amount,
                released_amount: old_schedule.released_amount,
                revocable: old_schedule.revocable,
                revoked: false,
            };

            self.vesting_schedules.write(new_beneficiary, transfer_schedule);

            // Add new beneficiary to list
            self._add_beneficiary(new_beneficiary);

            // Remove old schedule
            old_schedule.initialized = false;
            self.vesting_schedules.write(previous_beneficiary, old_schedule);

            // Remove old beneficiary from the list
            self._remove_beneficiary(previous_beneficiary);

            // Emit event
            self.emit(BeneficiaryTransferred { previous_beneficiary, new_beneficiary });
        }

        // Gets the number of beneficiaries
        fn get_beneficiary_count(self: @ContractState) -> u32 {
            self.beneficiaries_count.read()
        }

        // New function to get all beneficiaries
        fn get_beneficiaries(self: @ContractState) -> Array<ContractAddress> {
            let mut beneficiaries = ArrayTrait::new();
            let count = self.beneficiaries_count.read();

            let mut i: u32 = 0;
            loop {
                if i >= count {
                    break;
                }

                let beneficiary = self.beneficiaries_at_index.read(i);
                if self.is_beneficiary.read(beneficiary) {
                    beneficiaries.append(beneficiary);
                }

                i += 1;
            }

            beneficiaries
        }
    }

    #[generate_trait]
    impl BeneficiaryArrayImpl of BeneficiaryArrayTrait {
        // Add a beneficiary to the array
        fn _add_beneficiary(ref self: ContractState, beneficiary: ContractAddress) {
            // Only add if not already a beneficiary
            if !self.is_beneficiary.read(beneficiary) {
                let count = self.beneficiaries_count.read();
                self.beneficiaries_at_index.write(count, beneficiary);
                self.is_beneficiary.write(beneficiary, true);
                self.beneficiaries_count.write(count + 1);
            }
        }

        // Remove a beneficiary from the array
        fn _remove_beneficiary(ref self: ContractState, beneficiary: ContractAddress) {
            // Only proceed if it's a beneficiary
            if self.is_beneficiary.read(beneficiary) {
                // Mark as not a beneficiary anymore
                self.is_beneficiary.write(beneficiary, false);
                // Note: We're not actually removing the entry from the mapping or shifting elements
            // We just mark it as no longer active via the is_beneficiary mapping
            // The get_beneficiaries function will filter these out
            // This is more gas efficient than shifting elements
            }
        }
    }

    #[generate_trait]
    impl ERC20Impl of ERC20Trait {
        fn _transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let self_token = self.token.read();
            IERC20Dispatcher { contract_address: self_token }.transfer(recipient, amount)
        }

        fn _transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            let self_token = self.token.read();
            IERC20Dispatcher { contract_address: self_token }
                .transfer_from(sender, recipient, amount)
        }
    }
}

