#[cfg(test)]
mod tests {
    use core::traits::TryInto;
    use snforge_std::{declare, ContractClassTrait, start_prank, stop_prank};
    use contracts::erc20::{ITokenDispatcher, ITokenDispatcherTrait};
    use array::ArrayTrait;
    use starknet::{ContractAddress,get_caller_address};

    // #[test]
    fn setup() -> ContractAddress {
        // First declare and deploy a contract
        let contract = declare('BuyToken');
        // Initialize Constructor
        let mut deploy = ArrayTrait::new();
          let contract_address = contract.precalculate_address(@deploy);
        let owner: ContractAddress = 0x03.try_into().unwrap();
        start_prank(contract_address, owner);
        let deployed = contract.deploy(@deploy).unwrap();
        stop_prank(contract_address);
        deployed
    }

    #[test]
    fn test_name() {
        let contract_address = setup();
        // Create a Dispatcher object that will allow interacting with the deployed contract
        let dispatcher = ITokenDispatcher { contract_address };

        // Call a view function of the contract
        let name = dispatcher.get_name();
        assert(name == 'ERC20Token', 'Incorrect Name');
    }

    #[test]
    fn test_symbol() {
        let contract_address = setup();
        // Create a Dispatcher object that will allow interacting with the deployed contract
        let dispatcher = ITokenDispatcher { contract_address };

        // Call a view function of the contract
        let symbol = dispatcher.get_symbol();
        assert(symbol == 'ETK', 'Incorrect Symbol');
    }

    #[test]
    fn test_decimal() {
        let contract_address = setup();
        // Create a Dispatcher object that will allow interacting with the deployed contract
        let dispatcher = ITokenDispatcher { contract_address };

        // Call a view function of the contract
        let decimal = dispatcher.get_decimal();
        assert(decimal == 18, 'Incorrect Decimal');
    }

    #[test]
    fn test_owner() {
        let owner: ContractAddress = 0x03.try_into().unwrap();
        let contract_address = setup();
        // Create a Dispatcher object that will allow interacting with the deployed contract
        let dispatcher = ITokenDispatcher { contract_address };

        // Call a view function of the contract
        let get_owner = dispatcher.get_owner();
        assert(owner == get_owner, 'Incorrect Owner');
    }

     #[test]
    fn test_balance() {
        let contract_address = setup();
        // Create a Dispatcher object that will allow interacting with the deployed contract
        let dispatcher = ITokenDispatcher { contract_address };

        // Call a view function of the contract
        let user = get_caller_address();
        let balance = dispatcher.get_balance_of_user(user);
        assert(balance == 0, 'Incorrect Balance');
    }

     #[test]

    fn test_supply() {
        let contract_address = setup();
        // Create a Dispatcher object that will allow interacting with the deployed contract
        let dispatcher = ITokenDispatcher { contract_address };

        // Call a view function of the contract
        let supply = dispatcher.get_total_supply();
        assert(supply == 0, 'supply == 0');
    }

     #[test]
    fn test_mint() {
        let contract_address = setup();
        // Create a Dispatcher object that will allow interacting with the deployed contract
        let dispatcher = ITokenDispatcher { contract_address };

        // Call a view function of the contract
        let user: ContractAddress = 0x03.try_into().unwrap();
        start_prank(contract_address, user);
        let mint = dispatcher.mint(user);
        assert(dispatcher.get_balance_of_user(user) != 0, 'balance == 0');
        assert(dispatcher.get_balance_of_user(user) == 1000, 'incorrect balance');
        assert(dispatcher.get_total_supply() == dispatcher.get_balance_of_user(user), 'supply == 0');
        stop_prank(contract_address)
    }

     #[test]
    fn test_transfer() {
        let contract_address = setup();
        // Create a Dispatcher object that will allow interacting with the deployed contract
        let dispatcher = ITokenDispatcher { contract_address };

        // Call a view function of the contract
        let user: ContractAddress = 0x03.try_into().unwrap();
        let receiver: ContractAddress = 0x01.try_into().unwrap();
        start_prank(contract_address, user);
        dispatcher.mint(user);
        assert(dispatcher.get_balance_of_user(user) != 0, 'balance is 0');
        assert(dispatcher.get_total_supply() == dispatcher.get_balance_of_user(user), 'supply == 0');
        let transfer = dispatcher.transfer(receiver, 1000);
        assert(dispatcher.get_balance_of_user(user) != 1000, 'balance is 1000');
        assert(dispatcher.get_balance_of_user(receiver) != 0, 'rec_balance == 0');
        stop_prank(contract_address)
    }

    #[test]
    fn test_approval() {
        let contract_address = setup();
        // Create a Dispatcher object that will allow interacting with the deployed contract
        let dispatcher = ITokenDispatcher { contract_address };

        // Call a view function of the contract
        let user: ContractAddress = 0x03.try_into().unwrap();
        let receiver: ContractAddress = 0x01.try_into().unwrap();
        start_prank(contract_address, user);
        dispatcher.approval(user, receiver, 1000);
        assert(dispatcher.allowance(user, receiver) != 0, 'allowance is 0');
        stop_prank(contract_address)
    }

    #[test]
    fn test_allowance() {
        let contract_address = setup();
        // Create a Dispatcher object that will allow interacting with the deployed contract
        let dispatcher = ITokenDispatcher { contract_address };

        // Call a view function of the contract
        let user: ContractAddress = 0x03.try_into().unwrap();
        let receiver: ContractAddress = 0x0.try_into().unwrap();
        start_prank(contract_address, user);
        dispatcher.allowance(user, receiver);
        assert(dispatcher.allowance(user, receiver) == 0, 'incorrect allowance');
        stop_prank(contract_address)
    }

    #[test]
    fn test_transfer_from() {
        let contract_address = setup();
        // Create a Dispatcher object that will allow interacting with the deployed contract
        let dispatcher = ITokenDispatcher { contract_address };

        // Call a view function of the contract
        let user: ContractAddress = 0x03.try_into().unwrap();
        let receiver: ContractAddress = 0x01.try_into().unwrap();
        start_prank(contract_address, user);
        dispatcher.mint(user);
        assert(dispatcher.get_balance_of_user(user) != 0, 'balance is 0');
        assert(dispatcher.get_total_supply() == dispatcher.get_balance_of_user(user), 'supply == 0');
        dispatcher.approval(user, contract_address, 100);
        assert(dispatcher.allowance(user, contract_address) != 0, 'allowance is 0');
        let transfer_from = dispatcher.transfer_from(user, receiver, 10);
        assert(dispatcher.get_balance_of_user(user) != 1000, 'balance is 1000');
        assert(dispatcher.get_balance_of_user(receiver) != 0, 'rec_balance == 0');
        stop_prank(contract_address)
    }

    #[test]
    fn test_withdraw_tokens() {
        let contract_address = setup();
        // Create a Dispatcher object that will allow interacting with the deployed contract
        let dispatcher = ITokenDispatcher { contract_address 
};

        // Call a view function of the contract
        let user: ContractAddress = 0x03.try_into().unwrap();
        start_prank(contract_address, user);
        dispatcher.mint(user);
        assert(dispatcher.get_balance_of_user(user) != 0, 'balance is 0');
        assert(dispatcher.get_total_supply() == dispatcher.get_balance_of_user(user), 'supply == 0');
        let transfer = dispatcher.transfer(contract_address, 100);
        let prev_bal = dispatcher.get_balance_of_user(user);
        assert(prev_bal != 1000, 'balance is 1000');
        assert(dispatcher.get_balance_of_user(contract_address) != 0, 'rec_balance == 0');
        dispatcher.withdrawTokens(contract_address, dispatcher.get_balance_of_user(contract_address));
        assert(prev_bal < dispatcher.get_balance_of_user(user), 'balance not added');
        assert(dispatcher.get_balance_of_user(contract_address) == 0, 'contract_balance == 0');
        stop_prank(contract_address)
    }
}