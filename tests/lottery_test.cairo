#[cfg(test)]
mod tests {
    use core::traits::TryInto;
    use core::array::ArrayTrait;
    use core::num::traits::Zero;
    use snforge_std::{declare, ContractClassTrait, start_prank, stop_prank, start_warp, stop_warp};
    use starknet::{ContractAddress, get_caller_address};
    use contracts::lottery::{
        ILotteryContractDispatcher, ILotteryContractDispatcherTrait, LotteryInfo, Winner
    };
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

    // Constants for testing
    const TICKET_PRICE: u256 = 100000000000000000; // 0.1 token
    const MAX_TICKETS: u32 = 100;
    const LOTTERY_DURATION: u64 = 86400; // 1 day
    const RANDOM_SEED: felt252 = 12345;

    // Setup function to deploy contracts and initialize test environment
    fn setup() -> (ContractAddress, ContractAddress) {
        // First deploy a mock ERC20 token for payments
        let token_contract = declare('BuyToken'); // Use existing ERC20 token contract
        let mut token_calldata = ArrayTrait::new();
        let token_address = token_contract.deploy(@token_calldata).unwrap();
        
        // Deploy the lottery contract
        let lottery_contract = declare('LotteryContract');
        let mut lottery_calldata = ArrayTrait::new();
        lottery_calldata.append(token_address.into());
        let lottery_address = lottery_contract.deploy(@lottery_calldata).unwrap();
        
        (token_address, lottery_address)
    }

    #[test]
    fn test_lottery_initialization() {
        let (token_address, lottery_address) = setup();
        let lottery_dispatcher = ILotteryContractDispatcher { contract_address: lottery_address };
        
        // Verify lottery is not active initially
        assert(!lottery_dispatcher.is_lottery_active(), 'Should not be active initially');
        
        // Get lottery info
        let info = lottery_dispatcher.get_lottery_info();
        assert(info.lottery_status == 0, 'Should be inactive');
    }

    #[test]
    fn test_start_lottery() {
        let (token_address, lottery_address) = setup();
        let lottery_dispatcher = ILotteryContractDispatcher { contract_address: lottery_address };
        
        // Set owner as caller
        let owner: ContractAddress = 0x03.try_into().unwrap();
        start_prank(lottery_address, owner);
        
        // Create prize distribution - 1 winner gets 100%
        let mut prize_distribution = ArrayTrait::new();
        prize_distribution.append(100);
        
        // Start lottery
        lottery_dispatcher.start_lottery(TICKET_PRICE, MAX_TICKETS, prize_distribution, LOTTERY_DURATION);
        
        // Check lottery is active
        assert(lottery_dispatcher.is_lottery_active(), 'Lottery should be active');
        
        // Check lottery info
        let info = lottery_dispatcher.get_lottery_info();
        assert(info.lottery_id == 1, 'Lottery ID should be 1');
        assert(info.ticket_price == TICKET_PRICE, 'Incorrect ticket price');
        assert(info.max_tickets == MAX_TICKETS, 'Incorrect max tickets');
        assert(info.tickets_sold == 0, 'Should have 0 tickets sold');
        assert(info.lottery_status == 1, 'Should be active');
        
        stop_prank(lottery_address);
    }

    #[test]
    fn test_buy_tickets() {
        let (token_address, lottery_address) = setup();
        let lottery_dispatcher = ILotteryContractDispatcher { contract_address: lottery_address };
        let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
        
        // Setup owner and player
        let owner: ContractAddress = 0x03.try_into().unwrap();
        let player: ContractAddress = 0x04.try_into().unwrap();
        
        // Start a lottery
        start_prank(lottery_address, owner);
        let mut prize_distribution = ArrayTrait::new();
        prize_distribution.append(100);
        lottery_dispatcher.start_lottery(TICKET_PRICE, MAX_TICKETS, prize_distribution, LOTTERY_DURATION);
        stop_prank(lottery_address);
        
        // Mint tokens to the player
        start_prank(token_address, owner);
        token_dispatcher.mint(player, TICKET_PRICE * 5);
        stop_prank(token_address);

        // Player approves lottery contract to spend tokens
        start_prank(token_address, player);
        token_dispatcher.approval(player, lottery_address, TICKET_PRICE * 5);
        stop_prank(token_address);
        
        // Player buys tickets
        start_prank(lottery_address, player);
        lottery_dispatcher.buy_tickets(3);
        stop_prank(lottery_address);
        
        // Check ticket purchase reflected in contract state
        assert(lottery_dispatcher.get_user_tickets(player) == 3, 'Player should have 3 tickets');
        
        let info = lottery_dispatcher.get_lottery_info();
        assert(info.tickets_sold == 3, 'Should have 3 tickets sold');
        assert(info.prize_pool == TICKET_PRICE * 3, 'Prize pool should match');
    }

    #[test]
    fn test_complete_lottery_lifecycle() {
        let (token_address, lottery_address) = setup();
        let lottery_dispatcher = ILotteryContractDispatcher { contract_address: lottery_address };
        let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
        
        // Setup owner and players
        let owner: ContractAddress = 0x03.try_into().unwrap();
        let player1: ContractAddress = 0x04.try_into().unwrap();
        let player2: ContractAddress = 0x05.try_into().unwrap();
        
        // Start a lottery
        start_prank(lottery_address, owner);
        let mut prize_distribution = ArrayTrait::new();
        prize_distribution.append(60); // 60% to winner 1
        prize_distribution.append(40); // 40% to winner 2
        lottery_dispatcher.start_lottery(TICKET_PRICE, MAX_TICKETS, prize_distribution, LOTTERY_DURATION);
        stop_prank(lottery_address);
        
        // Mint tokens to the players
        start_prank(token_address, owner);
        token_dispatcher.mint(player1, TICKET_PRICE * 10);
        token_dispatcher.mint(player2, TICKET_PRICE * 5);
        stop_prank(token_address);

        // Players approve lottery contract to spend tokens
        start_prank(token_address, player1);
        token_dispatcher.approval(player1, lottery_address, TICKET_PRICE * 10);
        stop_prank(token_address);
        
        start_prank(token_address, player2);
        token_dispatcher.approval(player2, lottery_address, TICKET_PRICE * 5);
        stop_prank(token_address);
        
        // Players buy tickets
        start_prank(lottery_address, player1);
        lottery_dispatcher.buy_tickets(10);
        stop_prank(lottery_address);
        
        start_prank(lottery_address, player2);
        lottery_dispatcher.buy_tickets(5);
        stop_prank(lottery_address);
        
        // Check ticket purchases reflected in contract state
        assert(lottery_dispatcher.get_user_tickets(player1) == 10, 'Player1 should have 10 tickets');
        assert(lottery_dispatcher.get_user_tickets(player2) == 5, 'Player2 should have 5 tickets');
        
        let info = lottery_dispatcher.get_lottery_info();
        assert(info.tickets_sold == 15, 'Should have 15 tickets sold');
        assert(info.prize_pool == TICKET_PRICE * 15, 'Prize pool should match');
        
        // Fast forward time to end of lottery
        start_warp(lottery_address, LOTTERY_DURATION + 1);
        
        // End the lottery
        start_prank(lottery_address, owner);
        lottery_dispatcher.end_lottery(RANDOM_SEED);
        stop_prank(lottery_address);
        
        // Check lottery ended
        let ended_info = lottery_dispatcher.get_lottery_info();
        assert(ended_info.lottery_status == 2, 'Lottery should be completed');
        
        // Get winners
        let winners = lottery_dispatcher.get_winners();
        assert(winners.len() > 0, 'Should have winners');
        
        // Note: Due to random selection of winners, we can't assert specific winners
        // But we can check that prizes are assigned correctly
        // The rest of the test would involve winners claiming prizes
        
        stop_warp(lottery_address);
    }

    #[test]
    fn test_prize_claiming() {
        let (token_address, lottery_address) = setup();
        let lottery_dispatcher = ILotteryContractDispatcher { contract_address: lottery_address };
        let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
        
        // Setup owner and player
        let owner: ContractAddress = 0x03.try_into().unwrap();
        let player: ContractAddress = 0x04.try_into().unwrap();
        
        // Start a lottery with only one player to ensure they win
        start_prank(lottery_address, owner);
        let mut prize_distribution = ArrayTrait::new();
        prize_distribution.append(100); // 100% to winner
        lottery_dispatcher.start_lottery(TICKET_PRICE, MAX_TICKETS, prize_distribution, LOTTERY_DURATION);
        stop_prank(lottery_address);
        
        // Mint tokens to the player
        start_prank(token_address, owner);
        token_dispatcher.mint(player, TICKET_PRICE * 10);
        stop_prank(token_address);

        // Player approves lottery contract to spend tokens
        start_prank(token_address, player);
        token_dispatcher.approval(player, lottery_address, TICKET_PRICE * 10);
        stop_prank(token_address);
        
        // Player buys tickets (only participant)
        start_prank(lottery_address, player);
        lottery_dispatcher.buy_tickets(1);
        stop_prank(lottery_address);
        
        // Record player's balance before claiming prize
        let initial_balance = token_dispatcher.balance_of(player);
        
        // Fast forward time to end of lottery
        start_warp(lottery_address, LOTTERY_DURATION + 1);
        
        // End the lottery
        start_prank(lottery_address, owner);
        lottery_dispatcher.end_lottery(RANDOM_SEED);
        stop_prank(lottery_address);
        
        // Player claims prize (as only participant, should get 100%)
        start_prank(lottery_address, player);
        lottery_dispatcher.claim_prize();
        stop_prank(lottery_address);
        
        // Check player's balance increased by prize amount
        let final_balance = token_dispatcher.balance_of(player);
        assert(final_balance > initial_balance, 'Balance should increase');
        // Prize should be equal to ticket price (minus any fees if applicable)
        assert(final_balance >= initial_balance + TICKET_PRICE, 'Should receive prize');
        
        stop_warp(lottery_address);
    }

    #[test]
    #[should_panic(expected: 'Not the contract owner')]
    fn test_only_owner_can_start_lottery() {
        let (token_address, lottery_address) = setup();
        let lottery_dispatcher = ILotteryContractDispatcher { contract_address: lottery_address };
        
        // Try to start lottery as non-owner
        let non_owner: ContractAddress = 0x04.try_into().unwrap();
        start_prank(lottery_address, non_owner);
        
        let mut prize_distribution = ArrayTrait::new();
        prize_distribution.append(100);
        
        // This should fail with "Not the contract owner" error
        lottery_dispatcher.start_lottery(TICKET_PRICE, MAX_TICKETS, prize_distribution, LOTTERY_DURATION);
        
        stop_prank(lottery_address);
    }

    #[test]
    #[should_panic(expected: 'Invalid prize distribution')]
    fn test_invalid_prize_distribution() {
        let (token_address, lottery_address) = setup();
        let lottery_dispatcher = ILotteryContractDispatcher { contract_address: lottery_address };
        
        // Start lottery as owner but with invalid prize distribution (not 100%)
        let owner: ContractAddress = 0x03.try_into().unwrap();
        start_prank(lottery_address, owner);
        
        let mut prize_distribution = ArrayTrait::new();
        prize_distribution.append(90); // Only 90% distribution
        
        // This should fail with "Invalid prize distribution" error
        lottery_dispatcher.start_lottery(TICKET_PRICE, MAX_TICKETS, prize_distribution, LOTTERY_DURATION);
        
        stop_prank(lottery_address);
    }

    #[test]
    #[should_panic(expected: 'Lottery not active')]
    fn test_buy_tickets_when_not_active() {
        let (token_address, lottery_address) = setup();
        let lottery_dispatcher = ILotteryContractDispatcher { contract_address: lottery_address };
        let player: ContractAddress = 0x04.try_into().unwrap();
        
        // Try to buy tickets when no lottery is active
        start_prank(lottery_address, player);
        lottery_dispatcher.buy_tickets(1);
        stop_prank(lottery_address);
    }
}
