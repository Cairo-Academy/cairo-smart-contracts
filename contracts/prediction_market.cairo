use pragma_lib::types::{AggregationMode, DataType, PragmaPricesResponse};
use starknet::{ClassHash, ContractAddress};

#[derive(Drop, Serde, starknet::Store)]
//general market prediction
pub struct PredictionMarket {
    title: ByteArray,
    market_id: u256,
    description: ByteArray,
    choices: (Choice, Choice),
    category: felt252,
    image_url: ByteArray,
    is_resolved: bool,
    is_open: bool,
    end_time: u64,
    winning_choice: Option<Choice>,
    total_pool: u256,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct CryptoPrediction {
    title: ByteArray,
    market_id: u256,
    description: ByteArray,
    choices: (Choice, Choice),
    category: felt252,
    image_url: ByteArray,
    is_resolved: bool,
    is_open: bool,
    end_time: u64,
    winning_choice: Option<Choice>,
    total_pool: u256,
    comparison_type: u8, // 0 -> less than amount, 1 -> greater than amount
    asset_key: felt252,
    target_value: u128,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct SportsPrediction {
    title: ByteArray,
    market_id: u256,
    description: ByteArray,
    choices: (Choice, Choice),
    category: felt252,
    image_url: ByteArray,
    is_resolved: bool,
    is_open: bool,
    end_time: u64,
    winning_choice: Option<Choice>,
    total_pool: u256,
    event_id: u64, // API event ID for automatic resolution
    team_flag: bool,
}

#[derive(Copy, Serde, Drop, starknet::Store, PartialEq, Hash)]
pub struct Choice {
    label: felt252,
    staked_amount: u256,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct UserStake {
    amount: u256,
    claimed: bool,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct UserWager {
    choice: Choice,
    stake: UserStake,
}

#[starknet::interface]
pub trait IPredictionHub<TContractState> {
     // Creates a new general prediction market with binary (yes/no) choices
    fn create_prediction(
        ref self: TContractState,
        title: ByteArray,
        description: ByteArray,
        choices: (felt252, felt252),
        category: felt252,
        image_url: ByteArray,
        end_time: u64,
    );
    // Creates a cryptocurrency price prediction market (e.g., "Will BTC be above $X by date Y?")
    fn create_crypto_prediction(
        ref self: TContractState,
        title: ByteArray,
        description: ByteArray,
        choices: (felt252, felt252),
        category: felt252,
        image_url: ByteArray,
        end_time: u64,
        comparison_type: u8,
        asset_key: felt252,
        target_value: u128,
    );
    // Creates a sports event prediction market with team-based outcomes
    fn create_sports_prediction(
        ref self: TContractState,
        title: ByteArray,
        description: ByteArray,
        choices: (felt252, felt252),
        category: felt252,
        image_url: ByteArray,
        end_time: u64,
        event_id: u64,
        team_flag: bool,
    );
    // Returns the total number of prediction markets created
    fn get_prediction_count(self: @TContractState) -> u256;
    // Places a bet on a specific market and choice, returns transaction success status
    fn place_wager(
        ref self: TContractState, market_id: u256, choice_idx: u8, amount: u256, market_type: u8,
    ) -> bool;
    // Resolves a general prediction market by setting the winning option
    fn resolve_prediction(ref self: TContractState, market_id: u256, winning_choice: u8);
     // Manually resolves a crypto prediction market (override for the automatic resolution)
    fn resolve_crypto_prediction_manually(
        ref self: TContractState, market_id: u256, winning_choice: u8,
    );
    // Manually resolves a sports prediction market (override for the automatic resolution)
    fn resolve_sports_prediction_manually(
        ref self: TContractState, market_id: u256, winning_choice: u8,
    );
    // Allows a user to claim their winnings from a resolved prediction
    fn collect_winnings(ref self: TContractState, market_id: u256, market_type: u8, wager_idx: u8);
    // Retrieves a specific prediction market by ID
    fn get_prediction(self: @TContractState, market_id: u256) -> PredictionMarket;
     // Returns an array of all active general prediction markets
    fn get_all_predictions(self: @TContractState) -> Array<PredictionMarket>;
     // Retrieves a specific crypto prediction by ID
    fn get_crypto_prediction(self: @TContractState, market_id: u256) -> CryptoPrediction;
    // Returns an array of all active crypto prediction markets
    fn get_all_crypto_predictions(self: @TContractState) -> Array<CryptoPrediction>;
    // Retrieves a specific sports prediction by I
    fn get_sports_prediction(self: @TContractState, market_id: u256) -> SportsPrediction;
    // Returns an array of all active sports prediction markets
    fn get_all_sports_predictions(self: @TContractState) -> Array<SportsPrediction>;
      // Resolves a sports prediction automatically based on event outcome
    fn resolve_sports_prediction(ref self: TContractState, market_id: u256, winning_choice: u8);
    // Returns all general prediction markets a specific user has participated in
    fn get_user_predictions(
        self: @TContractState, user: ContractAddress,
    ) -> Array<PredictionMarket>;
     // Returns the contract admin address
    fn get_admin(self: @TContractState) -> ContractAddress;
    // Returns the address receiving platform fees
    fn get_fee_recipient(self: @TContractState) -> ContractAddress;
    // Sets a new fee recipient address
    fn set_fee_recipient(ref self: TContractState, recipient: ContractAddress);
    // Upgrades the contract implementation to a new class has
    fn update_contract(ref self: TContractState, new_class_hash: ClassHash);
     // Returns how many wagers a user has placed on a specific market
    fn get_wager_count_for_market(
        self: @TContractState, user: ContractAddress, market_id: u256, market_type: u8,
    ) -> u8;
    // Retrieves a specific wager made by a user
    fn get_choice_and_wager(
        self: @TContractState,
        user: ContractAddress,
        market_id: u256,
        market_type: u8,
        wager_idx: u8,
    ) -> UserWager;
     // Calculates total unclaimed winnings for a user across all markets
    fn get_user_claimable_amount(self: @TContractState, user: ContractAddress) -> u256;
    // Opens or closes a market for new wagers
    fn toggle_market_status(ref self: TContractState, market_id: u256, market_type: u8);
    // Automatically resolves a crypto prediction using oracle price data
    fn resolve_crypto_prediction(ref self: TContractState, market_id: u256);
    // Adds a new moderator who can create/resolve predictions
    fn add_moderator(ref self: TContractState, moderator: ContractAddress);
    // Administrative function to reset all prediction markets
    fn remove_all_predictions(ref self: TContractState);
    // Returns all crypto prediction markets a specific user has participated in
    fn get_user_crypto_predictions(
        self: @TContractState, user: ContractAddress,
    ) -> Array<CryptoPrediction>;
    // Returns all sports prediction markets a specific user has participated in
    fn get_user_sports_predictions(
        self: @TContractState, user: ContractAddress,
    ) -> Array<SportsPrediction>;
}

#[starknet::contract]
pub mod PredictionHub {
    use core::array::ArrayTrait;    
    use core::num::traits::zero::Zero;
    use core::option::OptionTrait;
    use core::starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use pragma_lib::abi::{IPragmaABIDispatcher, IPragmaABIDispatcherTrait};
    use pragma_lib::types::{AggregationMode, DataType, PragmaPricesResponse};
    use starknet::{
        ClassHash, ContractAddress, SyscallResultTrait, contract_address_const, get_block_timestamp,
        get_caller_address, get_contract_address,
    };
    use super::{Choice, CryptoPrediction, PredictionMarket, SportsPrediction, UserStake, UserWager};
    const ONE: u256 = 1_000_000_000_000_000_000;
    const MAX_ITERATIONS: u16 = 25;
    const PLATFORM_FEE: u256 = 2;
    

    #[storage]
    struct Storage {
        user_wager: Map<(ContractAddress, u256, u8, u8), UserWager>,  //stores all user wagers (bets) placed across all prediction markets
        wager_count: Map<(ContractAddress, u256, u8), u8>,
        predictions: Map<u256, PredictionMarket>,
        crypto_predictions: Map<u256, CryptoPrediction>,
        crypto_idx: u256,
        sports_predictions: Map<u256, SportsPrediction>,
        sports_idx: u256,
        idx: u256,
        admin: ContractAddress,
        fee_recipient: ContractAddress,
        moderators: Map<u128, ContractAddress>,
        moderator_count: u128,
        token_address: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PredictionCreated: PredictionCreated,
        CryptoPredictionCreated: CryptoPredictionCreated,
        WagerPlaced: WagerPlaced,
        SportsWagerPlaced: SportsWagerPlaced,
        CryptoWagerPlaced: CryptoWagerPlaced,
        PredictionResolved: PredictionResolved,
        SportsPredictionResolved: SportsPredictionResolved,
        CryptoPredictionResolved: CryptoPredictionResolved,
        PredictionToggled: PredictionToggled,
        WinningsCollected: WinningsCollected,
        SportsWinningsCollected: SportsWinningsCollected,
        CryptoWinningsCollected: CryptoWinningsCollected,
        ContractUpdated: ContractUpdated,
        SportsPredictionCreated: SportsPredictionCreated,
        SportsPredictionToggled: SportsPredictionToggled,
        CryptoPredictionToggled: CryptoPredictionToggled,
    }
    #[derive(Drop, PartialEq, starknet::Event)]
    pub struct ContractUpdated {
        pub class_hash: ClassHash,
    }
    #[derive(Drop, starknet::Event)]
    struct PredictionCreated {
        prediction: PredictionMarket,
    }

    #[derive(Drop, starknet::Event)]
    struct CryptoPredictionCreated {
        prediction: CryptoPrediction,
    }

    #[derive(Drop, starknet::Event)]
    struct SportsPredictionCreated {
        prediction: SportsPrediction,
    }

    #[derive(Drop, starknet::Event)]
    struct CryptoPredictionResolved {
        prediction: CryptoPrediction,
    }

    #[derive(Drop, starknet::Event)]
    struct SportsPredictionResolved {
        prediction: SportsPrediction,
    }

    #[derive(Drop, starknet::Event)]
    struct WagerPlaced {
        user: ContractAddress,
        prediction: PredictionMarket,
        choice: Choice,
        amount: u256,
    }
    #[derive(Drop, starknet::Event)]
    struct SportsWagerPlaced {
        user: ContractAddress,
        prediction: SportsPrediction,
        choice: Choice,
        amount: u256,
    }
    #[derive(Drop, starknet::Event)]
    struct CryptoWagerPlaced {
        user: ContractAddress,
        prediction: CryptoPrediction,
        choice: Choice,
        amount: u256,
    }
    #[derive(Drop, starknet::Event)]
    struct PredictionResolved {
        prediction: PredictionMarket,
    }

    #[derive(Drop, starknet::Event)]
    struct PredictionToggled {
        prediction: PredictionMarket,
    }
    #[derive(Drop, starknet::Event)]
    struct SportsPredictionToggled {
        prediction: SportsPrediction,
    }
    #[derive(Drop, starknet::Event)]
    struct CryptoPredictionToggled {
        prediction: CryptoPrediction,
    }
    #[derive(Drop, starknet::Event)]
    struct WinningsCollected {
        user: ContractAddress,
        prediction: PredictionMarket,
        choice: Choice,
        amount: u256,
    }
    #[derive(Drop, starknet::Event)]
    struct SportsWinningsCollected {
        user: ContractAddress,
        prediction: SportsPrediction,
        choice: Choice,
        amount: u256,
    }
    #[derive(Drop, starknet::Event)]
    struct CryptoWinningsCollected {
        user: ContractAddress,
        prediction: CryptoPrediction,
        choice: Choice,
        amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, admin: ContractAddress, token_address: ContractAddress,
    ) {
        self.admin.write(admin);
        self.token_address.write(token_address);
    }

    fn create_choice_pair(labels: (felt252, felt252)) -> (Choice, Choice) {
        let (label1, label2) = labels;
        let mut choice1 = Choice { label: label1, staked_amount: 0 };
        let mut choice2 = Choice { label: label2, staked_amount: 0 };

        let choices = (choice1, choice2);

        return choices;
    }

    #[abi(embed_v0)]
    impl PredictionHub of super::IPredictionHub<ContractState> {
        fn create_prediction(
            ref self: ContractState,
            title: ByteArray,
            description: ByteArray,
            choices: (felt252, felt252),
            category: felt252,
            image_url: ByteArray,
            end_time: u64,
        ) {
            let mut i = 1;
            loop {
                assert(i <= self.moderator_count.read(), 'Not a moderator.');
                if self.moderators.read(i) == get_caller_address() {
                    break;
                }
                i += 1;
            }
            let choices = create_choice_pair(choices);
            let prediction = PredictionMarket {
                title,
                description,
                choices,
                is_resolved: false,
                is_open: true,
                winning_choice: Option::None,
                total_pool: 0,
                category,
                image_url,
                end_time,
                market_id: self.idx.read() + 1,
            };
            self.idx.write(self.idx.read() + 1);
            self.predictions.write(self.idx.read(), prediction);
            let current_prediction = self.predictions.read(self.idx.read());
            self.emit(PredictionCreated { prediction: current_prediction });
        }
        fn create_crypto_prediction(
            ref self: ContractState,
            title: ByteArray,
            description: ByteArray,
            choices: (felt252, felt252),
            category: felt252,
            image_url: ByteArray,
            end_time: u64,
            comparison_type: u8,
            asset_key: felt252,
            target_value: u128,
        ) {
            let mut i = 1;
            loop {
                assert(i <= self.moderator_count.read(), 'Not a moderator.');
                if self.moderators.read(i) == get_caller_address() {
                    break;
                }
                i += 1;
            }
            let choices = create_choice_pair(choices);
            let crypto_prediction = CryptoPrediction {
                title,
                description,
                choices,
                is_resolved: false,
                is_open: true,
                winning_choice: Option::None,
                total_pool: 0,
                category,
                image_url,
                end_time,
                market_id: self.crypto_idx.read() + 1,
                comparison_type,
                asset_key,
                target_value,
            };
            self.crypto_idx.write(self.crypto_idx.read() + 1);
            self.crypto_predictions.write(self.crypto_idx.read(), crypto_prediction);
            let current_prediction = self.crypto_predictions.read(self.crypto_idx.read());
            self.emit(CryptoPredictionCreated { prediction: current_prediction });
        }


        fn get_prediction(self: @ContractState, market_id: u256) -> PredictionMarket {
            return self.predictions.read(market_id);
        }

        fn create_sports_prediction(
            ref self: ContractState,
            title: ByteArray,
            description: ByteArray,
            choices: (felt252, felt252),
            category: felt252,
            image_url: ByteArray,
            end_time: u64,
            event_id: u64,
            team_flag: bool,
        ) {
            let mut i = 1;
            loop {
                assert(i <= self.moderator_count.read(), 'Not a moderator.');
                if self.moderators.read(i) == get_caller_address() {
                    break;
                }
                i += 1;
            }
            let choices = create_choice_pair(choices);
            let sports_prediction = SportsPrediction {
                title,
                description,
                choices,
                is_resolved: false,
                is_open: true,
                winning_choice: Option::None,
                total_pool: 0,
                category,
                image_url,
                end_time,
                market_id: self.sports_idx.read() + 1,
                event_id,
                team_flag,
            };
            self.sports_idx.write(self.sports_idx.read() + 1);
            self.sports_predictions.write(self.sports_idx.read(), sports_prediction);
            let current_prediction = self.sports_predictions.read(self.sports_idx.read());
            self.emit(SportsPredictionCreated { prediction: current_prediction });
        }

        fn get_prediction_count(self: @ContractState) -> u256 {
            return self.idx.read();
        }

        fn resolve_sports_prediction(ref self: ContractState, market_id: u256, winning_choice: u8) {
            assert(get_caller_address() == self.admin.read(), 'Not admin');
            assert(market_id <= self.sports_idx.read(), 'Prediction does not exist');
            let mut sports_prediction = self.sports_predictions.read(market_id);
            assert(
                get_block_timestamp() > sports_prediction.end_time, 'Prediction has not expired.',
            );
            sports_prediction.is_resolved = true;
            sports_prediction.is_open = false;
            let (choice1, choice2) = sports_prediction.choices;
            if winning_choice == 0 {
                sports_prediction.winning_choice = Option::Some(choice1);
            } else {
                sports_prediction.winning_choice = Option::Some(choice2);
            }
            self.sports_predictions.write(market_id, sports_prediction);
            let current_prediction = self.sports_predictions.read(market_id);
            self.emit(SportsPredictionResolved { prediction: current_prediction });
        }

        fn get_crypto_prediction(self: @ContractState, market_id: u256) -> CryptoPrediction {
            return self.crypto_predictions.read(market_id);
        }

        fn get_all_crypto_predictions(self: @ContractState) -> Array<CryptoPrediction> {
            let mut predictions: Array<CryptoPrediction> = ArrayTrait::new();
            let mut i: u256 = 1;
            loop {
                if i > self.crypto_idx.read() {
                    break;
                }
                if self.crypto_predictions.read(i).is_open == true {
                    predictions.append(self.crypto_predictions.read(i));
                }
                i += 1;
            }
            predictions
        }

        fn get_sports_prediction(self: @ContractState, market_id: u256) -> SportsPrediction {
            return self.sports_predictions.read(market_id);
        }

        fn get_all_sports_predictions(self: @ContractState) -> Array<SportsPrediction> {
            let mut predictions: Array<SportsPrediction> = ArrayTrait::new();
            let mut i: u256 = 1;
            loop {
                if i > self.sports_idx.read() {
                    break;
                }
                if self.sports_predictions.read(i).is_open == true {
                    predictions.append(self.sports_predictions.read(i));
                }
                i += 1;
            }
            predictions
        }

        fn get_user_predictions(
            self: @ContractState, user: ContractAddress,
        ) -> Array<PredictionMarket> {
            let mut predictions: Array<PredictionMarket> = ArrayTrait::new();
            let mut i: u256 = 1;
            loop {
                if i > self.idx.read() {
                    break;
                }
                let total_wagers = self.wager_count.read((user, i, 2));
                if total_wagers > 0 {
                    predictions.append(self.predictions.read(i));
                }
                i += 1;
            }
            predictions
        }

        fn get_user_crypto_predictions(
            self: @ContractState, user: ContractAddress,
        ) -> Array<CryptoPrediction> {
            let mut predictions: Array<CryptoPrediction> = ArrayTrait::new();
            let mut i: u256 = 1;
            loop {
                if i > self.crypto_idx.read() {
                    break;
                }
                let total_wagers = self.wager_count.read((user, i, 1));
                if total_wagers > 0 {
                    predictions.append(self.crypto_predictions.read(i));
                }
                i += 1;
            }
            predictions
        }

        fn get_user_sports_predictions(
            self: @ContractState, user: ContractAddress,
        ) -> Array<SportsPrediction> {
            let mut predictions: Array<SportsPrediction> = ArrayTrait::new();
            let mut i: u256 = 1;
            loop {
                if i > self.sports_idx.read() {
                    break;
                }
                let total_wagers = self.wager_count.read((user, i, 0));
                if total_wagers > 0 {
                    predictions.append(self.sports_predictions.read(i));
                }
                i += 1;
            }
            predictions
        }

        fn get_wager_count_for_market(
            self: @ContractState, user: ContractAddress, market_id: u256, market_type: u8,
        ) -> u8 {
            return self.wager_count.read((user, market_id, market_type));
        }

        fn resolve_crypto_prediction(ref self: ContractState, market_id: u256) {
            assert(get_caller_address() == self.admin.read(), 'Not Admin');
            assert(market_id <= self.crypto_idx.read(), 'Prediction does not exist');
            let mut crypto_prediction = self.crypto_predictions.read(market_id);
            let price = get_asset_price_median(DataType::SpotEntry(crypto_prediction.asset_key));
            crypto_prediction.is_resolved = true;
            crypto_prediction.is_open = false;
            let (choice1, choice2) = crypto_prediction.choices;
            if crypto_prediction.comparison_type == 0 {
                if price < crypto_prediction.target_value {
                    crypto_prediction.winning_choice = Option::Some(choice1);
                } else {
                    crypto_prediction.winning_choice = Option::Some(choice2);
                }
            } else {
                if price > crypto_prediction.target_value {
                    crypto_prediction.winning_choice = Option::Some(choice1);
                } else {
                    crypto_prediction.winning_choice = Option::Some(choice2);
                }
            }
            self.crypto_predictions.write(market_id, crypto_prediction);
            let current_prediction = self.crypto_predictions.read(market_id);
            self.emit(CryptoPredictionResolved { prediction: current_prediction });
        }

        fn toggle_market_status(ref self: ContractState, market_id: u256, market_type: u8) {
            let mut i = 1;
            loop {
                assert(i <= self.moderator_count.read(), 'Not a moderator.');
                if self.moderators.read(i) == get_caller_address() {
                    break;
                }
                i += 1;
            }
            if market_type == 0 {
                let mut prediction = self.sports_predictions.read(market_id);
                prediction.is_open = !prediction.is_open;
                self.sports_predictions.write(market_id, prediction);
                let current_prediction = self.sports_predictions.read(market_id);
                self.emit(SportsPredictionToggled { prediction: current_prediction });
            } else if market_type == 1 {
                let mut prediction = self.crypto_predictions.read(market_id);
                prediction.is_open = !prediction.is_open;
                self.crypto_predictions.write(market_id, prediction);
                let current_prediction = self.crypto_predictions.read(market_id);
                self.emit(CryptoPredictionToggled { prediction: current_prediction });
            } else {
                let mut prediction = self.predictions.read(market_id);
                prediction.is_open = !prediction.is_open;
                self.predictions.write(market_id, prediction);
                let current_prediction = self.predictions.read(market_id);
                self.emit(PredictionToggled { prediction: current_prediction });
            }
        }

        fn get_choice_and_wager(
            self: @ContractState,
            user: ContractAddress,
            market_id: u256,
            market_type: u8,
            wager_idx: u8,
        ) -> UserWager {
            let user_wager = self.user_wager.read((user, market_id, market_type, wager_idx));
            return user_wager;
        }

        fn add_moderator(ref self: ContractState, moderator: ContractAddress) {
            assert(get_caller_address() == self.admin.read(), 'Only admin can add moderators.');
            self.moderator_count.write(self.moderator_count.read() + 1);
            self.moderators.write(self.moderator_count.read(), moderator);
        }

        fn get_user_claimable_amount(self: @ContractState, user: ContractAddress) -> u256 {
            let mut total: u256 = 0;
            let mut i: u256 = 1;
            loop {
                if i > self.idx.read() {
                    break;
                }
                let prediction = self.sports_predictions.read(i);
                if prediction.is_resolved == false {
                    i += 1;
                    continue;
                }
                let total_wagers = self.wager_count.read((user, i, 0));

                if total_wagers > 0 {
                    let mut wager_idx = 1;
                    loop {
                        if wager_idx > total_wagers {
                            break;
                        }
                        let user_wager = self.user_wager.read((user, i, 0, wager_idx));
                        if user_wager.choice == prediction.winning_choice.unwrap() {
                            if user_wager.stake.claimed == false {
                                total += user_wager.stake.amount
                                    * prediction.total_pool
                                    / user_wager.choice.staked_amount;
                            }
                        }
                        wager_idx += 1;
                    }
                }
                i += 1;
            }
            let mut i: u256 = 1;
            loop {
                if i > self.idx.read() {
                    break;
                }
                let prediction = self.crypto_predictions.read(i);
                if prediction.is_resolved == false {
                    i += 1;
                    continue;
                }
                let total_wagers = self.wager_count.read((user, i, 1));

                if total_wagers > 0 {
                    let mut wager_idx = 1;
                    loop {
                        if wager_idx > total_wagers {
                            break;
                        }
                        let user_wager = self.user_wager.read((user, i, 1, wager_idx));
                        if user_wager.choice == prediction.winning_choice.unwrap() {
                            if user_wager.stake.claimed == false {
                                total += user_wager.stake.amount
                                    * prediction.total_pool
                                    / user_wager.choice.staked_amount;
                            }
                        }
                        wager_idx += 1;
                    }
                }
                i += 1;
            }
            let mut i: u256 = 1;
            loop {
                if i > self.idx.read() {
                    break;
                }
                let prediction = self.predictions.read(i);
                if prediction.is_resolved == false {
                    i += 1;
                    continue;
                }
                let total_wagers = self.wager_count.read((user, i, 2));

                if total_wagers > 0 {
                    let mut wager_idx = 1;
                    loop {
                        if wager_idx > total_wagers {
                            break;
                        }
                        let user_wager = self.user_wager.read((user, i, 2, wager_idx));
                        if user_wager.choice == prediction.winning_choice.unwrap() {
                            if user_wager.stake.claimed == false {
                                total += user_wager.stake.amount
                                    * prediction.total_pool
                                    / user_wager.choice.staked_amount;
                            }
                        }
                        wager_idx += 1;
                    }
                }
                i += 1;
            }
            total
        }

        // creates a position in a market for a user
        fn place_wager(
            ref self: ContractState, market_id: u256, choice_idx: u8, amount: u256, market_type: u8,
        ) -> bool {
            let token_address = self.token_address.read();
            let dispatcher = IERC20Dispatcher { contract_address: token_address };
            match market_type {
                0 => { // Sports predictions
                    let mut prediction = self.sports_predictions.read(market_id);
                    assert(prediction.is_open, 'Prediction not open.');
                    assert(get_block_timestamp() < prediction.end_time, 'Prediction has expired.');
                    let (mut choice1, mut choice2) = prediction.choices;

                    let txn: bool = dispatcher
                        .transfer_from(get_caller_address(), get_contract_address(), amount);
                    dispatcher.transfer(self.fee_recipient.read(), amount * PLATFORM_FEE / 100);

                    let staked_amount = amount - amount * PLATFORM_FEE / 100;
                    let total_pool = prediction.total_pool + staked_amount;

                    if choice_idx == 0 {
                        choice1.staked_amount += staked_amount;
                    } else {
                        choice2.staked_amount += staked_amount;
                    }

                    prediction.choices = (choice1, choice2);
                    prediction.total_pool = total_pool;

                    self.sports_predictions.write(market_id, prediction);
                    self
                        .wager_count
                        .write(
                            (get_caller_address(), market_id, 0),
                            self.wager_count.read((get_caller_address(), market_id, 0)) + 1,
                        );
                    self
                        .user_wager
                        .write(
                            (
                                get_caller_address(),
                                market_id,
                                market_type,
                                self.wager_count.read((get_caller_address(), market_id, 0)),
                            ),
                            UserWager {
                                choice: if choice_idx == 0 {
                                    choice1
                                } else {
                                    choice2
                                },
                                stake: UserStake { amount: amount, claimed: false },
                            },
                        );
                    let new_prediction = self.sports_predictions.read(market_id);
                    self
                        .emit(
                            SportsWagerPlaced {
                                user: get_caller_address(),
                                prediction: new_prediction,
                                choice: if choice_idx == 0 {
                                    choice1
                                } else {
                                    choice2
                                },
                                amount: amount,
                            },
                        );
                    txn
                },
                1 => { // Crypto predictions
                    let mut prediction = self.crypto_predictions.read(market_id);
                    assert(prediction.is_open, 'Prediction is not open.');
                    assert(get_block_timestamp() < prediction.end_time, 'Prediction has expired.');
                    let (mut choice1, mut choice2) = prediction.choices;

                    let txn: bool = dispatcher
                        .transfer_from(get_caller_address(), get_contract_address(), amount);
                    dispatcher.transfer(self.fee_recipient.read(), amount * PLATFORM_FEE / 100);

                    let staked_amount = amount - amount * PLATFORM_FEE / 100;
                    let total_pool = prediction.total_pool + staked_amount;

                    if choice_idx == 0 {
                        choice1.staked_amount += staked_amount;
                    } else {
                        choice2.staked_amount += staked_amount;
                    }

                    prediction.choices = (choice1, choice2);
                    prediction.total_pool = total_pool;

                    self.crypto_predictions.write(market_id, prediction);
                    self
                        .wager_count
                        .write(
                            (get_caller_address(), market_id, 1),
                            self.wager_count.read((get_caller_address(), market_id, 1)) + 1,
                        );
                    self
                        .user_wager
                        .write(
                            (
                                get_caller_address(),
                                market_id,
                                market_type,
                                self.wager_count.read((get_caller_address(), market_id, 1)),
                            ),
                            UserWager {
                                choice: if choice_idx == 0 {
                                    choice1
                                } else {
                                    choice2
                                },
                                stake: UserStake { amount: amount, claimed: false },
                            },
                        );
                    let new_prediction = self.crypto_predictions.read(market_id);
                    self
                        .emit(
                            CryptoWagerPlaced {
                                user: get_caller_address(),
                                prediction: new_prediction,
                                choice: if choice_idx == 0 {
                                    choice1
                                } else {
                                    choice2
                                },
                                amount: amount,
                            },
                        );
                    txn
                },
                2 => { // General predictions
                    let mut prediction = self.predictions.read(market_id);
                    assert(prediction.is_open, 'Prediction is not open.');
                    assert(get_block_timestamp() < prediction.end_time, 'Prediction has expired.');
                    let (mut choice1, mut choice2) = prediction.choices;

                    let txn: bool = dispatcher
                        .transfer_from(get_caller_address(), get_contract_address(), amount);
                    dispatcher.transfer(self.fee_recipient.read(), amount * PLATFORM_FEE / 100);

                    let staked_amount = amount - amount * PLATFORM_FEE / 100;
                    let total_pool = prediction.total_pool + staked_amount;

                    if choice_idx == 0 {
                        choice1.staked_amount += staked_amount;
                    } else {
                        choice2.staked_amount += staked_amount;
                    }

                    prediction.choices = (choice1, choice2);
                    prediction.total_pool = total_pool;

                    self.predictions.write(market_id, prediction);
                    self
                        .wager_count
                        .write(
                            (get_caller_address(), market_id, 2),
                            self.wager_count.read((get_caller_address(), market_id, 2)) + 1,
                        );
                    self
                        .user_wager
                        .write(
                            (
                                get_caller_address(),
                                market_id,
                                market_type,
                                self.wager_count.read((get_caller_address(), market_id, 2)),
                            ),
                            UserWager {
                                choice: if choice_idx == 0 {
                                    choice1
                                } else {
                                    choice2
                                },
                                stake: UserStake { amount: amount, claimed: false },
                            },
                        );
                    let new_prediction = self.predictions.read(market_id);
                    self
                        .emit(
                            WagerPlaced {
                                user: get_caller_address(),
                                prediction: new_prediction,
                                choice: if choice_idx == 0 {
                                    choice1
                                } else {
                                    choice2
                                },
                                amount: amount,
                            },
                        );
                    txn
                },
                _ => panic!("Invalid prediction type"),
            }
        }


        fn resolve_prediction(ref self: ContractState, market_id: u256, winning_choice: u8) {
            let mut i = 1;
            loop {
                assert(i <= self.moderator_count.read(), 'Not a moderator.');
                if self.moderators.read(i) == get_caller_address() {
                    break;
                }
                i += 1;
            }
            assert(market_id <= self.idx.read(), 'Prediction does not exist');
            let mut prediction = self.predictions.read(market_id);
            prediction.is_resolved = true;
            prediction.is_open = false;
            let (choice1, choice2) = prediction.choices;
            if winning_choice == 0 {
                prediction.winning_choice = Option::Some(choice1);
            } else {
                prediction.winning_choice = Option::Some(choice2);
            }
            self.predictions.write(market_id, prediction);
            let current_prediction = self.predictions.read(market_id);
            self.emit(PredictionResolved { prediction: current_prediction });
        }

        fn resolve_crypto_prediction_manually(
            ref self: ContractState, market_id: u256, winning_choice: u8,
        ) {
            let mut i = 1;
            loop {
                assert(i <= self.moderator_count.read(), 'Not a moderator.');
                if self.moderators.read(i) == get_caller_address() {
                    break;
                }
                i += 1;
            }
            assert(market_id <= self.crypto_idx.read(), 'Prediction does not exist');
            let mut prediction = self.crypto_predictions.read(market_id);
            prediction.is_resolved = true;
            prediction.is_open = false;
            let (choice1, choice2) = prediction.choices;
            if winning_choice == 0 {
                prediction.winning_choice = Option::Some(choice1);
            } else {
                prediction.winning_choice = Option::Some(choice2);
            }
            self.crypto_predictions.write(market_id, prediction);
            let current_prediction = self.crypto_predictions.read(market_id);
            self.emit(CryptoPredictionResolved { prediction: current_prediction });
        }

        fn resolve_sports_prediction_manually(
            ref self: ContractState, market_id: u256, winning_choice: u8,
        ) {
            let mut i = 1;
            loop {
                assert(i <= self.moderator_count.read(), 'Not a moderator.');
                if self.moderators.read(i) == get_caller_address() {
                    break;
                }
                i += 1;
            }
            assert(market_id <= self.sports_idx.read(), 'Prediction does not exist');
            let mut prediction = self.sports_predictions.read(market_id);
            prediction.is_resolved = true;
            prediction.is_open = false;
            let (choice1, choice2) = prediction.choices;
            if winning_choice == 0 {
                prediction.winning_choice = Option::Some(choice1);
            } else {
                prediction.winning_choice = Option::Some(choice2);
            }
            self.sports_predictions.write(market_id, prediction);
            let current_prediction = self.sports_predictions.read(market_id);
            self.emit(SportsPredictionResolved { prediction: current_prediction });
        }

        fn collect_winnings(
            ref self: ContractState, market_id: u256, market_type: u8, wager_idx: u8,
        ) {
            if (market_type == 0) {
                assert(market_id <= self.sports_idx.read(), 'Prediction does not exist');
                let mut winnings = 0;
                let prediction = self.sports_predictions.read(market_id);
                assert(prediction.is_resolved, 'Prediction not resolved');
                let total_wagers = self
                    .wager_count
                    .read((get_caller_address(), market_id, market_type));
                assert(total_wagers > 0, 'no wagers in this prediction.');
                let user_wager: UserWager = self
                    .user_wager
                    .read((get_caller_address(), market_id, market_type, wager_idx));
                assert(!user_wager.stake.claimed, 'User has claimed winnings.');
                let winning_choice = prediction.winning_choice.unwrap();
                assert(user_wager.choice == winning_choice, 'User did not win!');
                winnings = user_wager.stake.amount
                    * prediction.total_pool
                    / user_wager.choice.staked_amount;
                let token_address = self.token_address.read();
                let dispatcher = IERC20Dispatcher { contract_address: token_address };
                dispatcher.transfer(get_caller_address(), winnings);
                self
                    .user_wager
                    .write(
                        (get_caller_address(), market_id, market_type, wager_idx),
                        UserWager {
                            choice: user_wager.choice,
                            stake: UserStake { amount: user_wager.stake.amount, claimed: true },
                        },
                    );
                self
                    .emit(
                        SportsWinningsCollected {
                            user: get_caller_address(),
                            prediction: prediction,
                            choice: user_wager.choice,
                            amount: winnings,
                        },
                    );
            } else if (market_type == 1) {
                assert(market_id <= self.crypto_idx.read(), 'Prediction does not exist');
                let prediction = self.crypto_predictions.read(market_id);
                assert(prediction.is_resolved, 'Prediction not resolved');
                let total_wagers = self
                    .wager_count
                    .read((get_caller_address(), market_id, market_type));
                assert(total_wagers > 0, 'no wagers in this prediction.');
                let user_wager: UserWager = self
                    .user_wager
                    .read((get_caller_address(), market_id, market_type, wager_idx));
                assert(user_wager.stake.claimed, 'User has claimed winnings.');
                let mut winnings = 0;
                let winning_choice = prediction.winning_choice.unwrap();
                assert(user_wager.choice == winning_choice, 'User did not win!');
                winnings = user_wager.stake.amount
                    * prediction.total_pool
                    / user_wager.choice.staked_amount;
                let token_address = self.token_address.read();
                let dispatcher = IERC20Dispatcher { contract_address: token_address };
                dispatcher.transfer(get_caller_address(), winnings);
                self
                    .user_wager
                    .write(
                        (get_caller_address(), market_id, market_type, wager_idx),
                        UserWager {
                            choice: user_wager.choice,
                            stake: UserStake { amount: user_wager.stake.amount, claimed: true },
                        },
                    );
                self
                    .emit(
                        CryptoWinningsCollected {
                            user: get_caller_address(),
                            prediction: prediction,
                            choice: user_wager.choice,
                            amount: winnings,
                        },
                    );
            } else {
                assert(market_id <= self.idx.read(), 'Prediction does not exist');
                let prediction = self.predictions.read(market_id);
                assert(prediction.is_resolved, 'Prediction not resolved');
                let total_wagers = self
                    .wager_count
                    .read((get_caller_address(), market_id, market_type));
                assert(total_wagers > 0, 'no wagers in this prediction.');
                let user_wager: UserWager = self
                    .user_wager
                    .read((get_caller_address(), market_id, market_type, wager_idx));
                assert(user_wager.stake.claimed, 'User has claimed winnings.');
                let mut winnings = 0;
                let winning_choice = prediction.winning_choice.unwrap();
                assert(user_wager.choice == winning_choice, 'User did not win!');
                winnings = user_wager.stake.amount
                    * prediction.total_pool
                    / user_wager.choice.staked_amount;
                let token_address = self.token_address.read();
                let dispatcher = IERC20Dispatcher { contract_address: token_address };
                dispatcher.transfer(get_caller_address(), winnings);
                self
                    .user_wager
                    .write(
                        (get_caller_address(), market_id, market_type, wager_idx),
                        UserWager {
                            choice: user_wager.choice,
                            stake: UserStake { amount: user_wager.stake.amount, claimed: true },
                        },
                    );
                self
                    .emit(
                        WinningsCollected {
                            user: get_caller_address(),
                            prediction: prediction,
                            choice: user_wager.choice,
                            amount: winnings,
                        },
                    );
            }
        }

        fn get_all_predictions(self: @ContractState) -> Array<PredictionMarket> {
            let mut predictions: Array<PredictionMarket> = ArrayTrait::new();
            let mut i: u256 = 1;
            loop {
                if i > self.idx.read() {
                    break;
                }
                if self.predictions.read(i).is_open == true {
                    predictions.append(self.predictions.read(i));
                }
                i += 1;
            }
            predictions
        }

        fn get_admin(self: @ContractState) -> ContractAddress {
            return self.admin.read();
        }

        fn get_fee_recipient(self: @ContractState) -> ContractAddress {
            assert(get_caller_address() == self.admin.read(), 'Only admin can read.');
            return self.fee_recipient.read();
        }

        fn set_fee_recipient(ref self: ContractState, recipient: ContractAddress) {
            assert(get_caller_address() == self.admin.read(), 'Only admin can set.');
            self.fee_recipient.write(recipient);
        }

        fn update_contract(ref self: ContractState, new_class_hash: ClassHash) {
            assert(get_caller_address() == self.admin.read(), 'Only admin can upgrade.');
            starknet::syscalls::replace_class_syscall(new_class_hash).unwrap_syscall();
            self.emit(ContractUpdated { class_hash: new_class_hash });
        }

        fn remove_all_predictions(ref self: ContractState) {
            assert(get_caller_address() == self.admin.read(), 'Not admin');
            self.idx.write(0);
            self.crypto_idx.write(0);
            self.sports_idx.write(0);
        }
    }

    fn get_asset_price_median(asset: DataType) -> u128 {
        let oracle_address: ContractAddress = contract_address_const::<
            0x2a85bd616f912537c50a49a4076db02c00b29b2cdc8a197ce92ed1837fa875b,
        >();
        let oracle_dispatcher = IPragmaABIDispatcher { contract_address: oracle_address };
        let output: PragmaPricesResponse = oracle_dispatcher
            .get_data(asset, AggregationMode::Median(()));
        return output.price;
    }
}

