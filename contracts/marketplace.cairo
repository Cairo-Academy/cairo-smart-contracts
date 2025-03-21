use starknet::ContractAddress;

#[starknet::interface]
trait IMarketplace<TContractState> {
    // Creates new listing with nft ownership verification
    fn list_asset(
        ref self: TContractState,
        asset_contract: ContractAddress,
        token_id: u256,
        start_time: u256,
        duration: u256,
        quantity: u256,
        payment_token: ContractAddress,
        price_per_token: u256,
        asset_type: u256,
    );
    // Removes listing by replacing with empty listing
    fn remove_listing(ref self: TContractState, listing_id: u256);
    // Direct purchase at listed price
    fn purchase(
        ref self: TContractState,
        listing_id: u256,
        recipient: ContractAddress,
        quantity: u256,
        payment_token: ContractAddress,
        total_price: u256,
    );
    // Seller accepts a specific offer
    fn accept_bid(
        ref self: TContractState,
        listing_id: u256,
        bidder: ContractAddress,
        payment_token: ContractAddress,
        price_per_token: u256
    );
    // Places a bid/offer on an existing listing
    fn place_bid(
        ref self: TContractState,
        listing_id: u256,
        quantity: u256,
        payment_token: ContractAddress,
        price_per_token: u256,
        expiration: u256
    );
    // Modify existing listing parameters
    fn modify_listing(
        ref self: TContractState,
        listing_id: u256,
        quantity: u256,
        reserve_price: u256,
        buy_now_price: u256,
        payment_token: ContractAddress,
        start_time: u256,
        duration: u256,
    );
    // Returns total number of listings created
    fn get_listing_count(self: @TContractState) -> u256;
}

#[starknet::interface]
trait IERC20<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    );
}

#[starknet::interface]
trait IERC721<TContractState> {
    fn owner_of(self: @TContractState, token_id: u256) -> ContractAddress;
    fn get_approved(self: @TContractState, token_id: u256) -> ContractAddress;
    fn is_approved_for_all(
        self: @TContractState, owner: ContractAddress, operator: ContractAddress
    ) -> bool;
    fn transfer_from(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256
    );
}

#[starknet::interface]
trait IERC1155<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress, id: u256) -> u256;
    fn is_approved_for_all(
        self: @TContractState, account: ContractAddress, operator: ContractAddress
    ) -> bool;
    fn safe_transfer_from(
        ref self: TContractState,
        from: ContractAddress,
        to: ContractAddress,
        id: u256,
        amount: u256,
        data: Span<felt252>
    );
}

#[starknet::contract]
mod Marketplace {
   
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::get_block_timestamp;
    use starknet::contract_address_const;
    use starknet::syscalls::replace_class_syscall;
    use starknet::class_hash::ClassHash;
    use core::traits::Into;   
    use core::starknet::storage::{
        Map,StorageMapReadAccess, StorageMapWriteAccess, StoragePointerWriteAccess,
        StoragePointerReadAccess,
    };
    use core::num::traits::Zero;       
    use openzeppelin::token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
    use openzeppelin::token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    
    // Token type constants - used to differentiate between NFT standards
    const TYPE_ERC721: u256 = 0;
    const TYPE_ERC1155: u256 = 1;

    // Core storage - tracks marketplace state including listings and offers
    #[storage]
    struct Storage {
        admin: ContractAddress,
        listing_count: u256,
        listings: Map::<u256, Listing>,
        bids: Map::<(u256, ContractAddress), Bid>,
    }

    // Events emitted for indexing and tracking marketplace activity
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ListingCreated: ListingCreated,
        ListingModified: ListingModified,
        ListingCancelled: ListingCancelled,
        BidPlaced: BidPlaced,
        AssetSold: AssetSold,
    }

    #[derive(Drop, starknet::Event)]
    struct AssetSold {
        #[key]
        listing_id: u256,
        #[key]
        asset_contract: ContractAddress,
        #[key]
        seller: ContractAddress,
        buyer: ContractAddress,
        quantity: u256,
        price_paid: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ListingCreated {
        #[key]
        listing_id: u256,
        #[key]
        asset_contract: ContractAddress,
        #[key]
        seller: ContractAddress,
        listing: Listing,
    }
    
    #[derive(Drop, starknet::Event)]
    struct ListingModified {
        #[key]
        listing_id: u256,
        #[key]
        seller: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct ListingCancelled {
        #[key]
        listing_id: u256,
        #[key]
        seller: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct BidPlaced {
        #[key]
        listing_id: u256,
        #[key]
        bidder: ContractAddress,
        quantity: u256,
        total_bid_amount: u256,
        payment_token: ContractAddress,
    }

    // Structure for bids made on listings
    #[derive(Copy, Drop, Serde, starknet::Store)]
    struct Bid {
        listing_id: u256,
        bidder: ContractAddress,
        quantity: u256,
        payment_token: ContractAddress,
        price_per_token: u256,
        expiration: u256,
    }

    // Structure for active marketplace listings
    #[derive(Copy, Drop, Serde, starknet::Store)]
    struct Listing {
        listing_id: u256,
        seller: ContractAddress,
        asset_contract: ContractAddress,
        token_id: u256,
        start_time: u256,
        end_time: u256,
        quantity: u256,
        payment_token: ContractAddress,
        price_per_token: u256,
        asset_type: u256,
    }

    // Sets initial contract operator (admin)
    #[constructor]
    fn constructor(ref self: ContractState,) {
        self.admin.write(get_caller_address());
    }

    // Allows contract upgrade while preserving storage state
    #[external(v0)]
    fn upgrade(self: @ContractState, new_class_hash: ClassHash) {
        assert(!new_class_hash.is_zero(), 'Class hash cannot be zero');
        assert(get_caller_address() == self.admin.read(), 'Admin access required');
        replace_class_syscall(new_class_hash);
    }

    #[abi(embed_v0)]
    impl IMarketplaceImpl of super::IMarketplace<ContractState> {
        // Creates new listing with ownership verification
        fn list_asset(
            ref self: ContractState,
            asset_contract: ContractAddress,
            token_id: u256,
            start_time: u256,
            duration: u256,
            quantity: u256,
            payment_token: ContractAddress,
            price_per_token: u256,
            asset_type: u256,
        ) {
            let listing_id = self.listing_count.read();
            self.listing_count.write(listing_id + 1);

            let seller = get_caller_address();
            let adjusted_quantity = self.normalize_quantity(asset_type, quantity);
            assert(adjusted_quantity > 0, 'Invalid quantity');
            
            // Auto-adjust start_time if in the past (within 1 hour)
            let mut adjusted_start_time = start_time;
            let current_time = get_block_timestamp().into();
            if (adjusted_start_time < current_time) {
                assert(current_time - adjusted_start_time < 3600, 'Start time too old');
                adjusted_start_time = current_time;
            }

            self
                .verify_ownership_and_approval(
                    seller, asset_contract, token_id, adjusted_quantity, asset_type
                );

            let new_listing = Listing {
                listing_id: listing_id,
                seller: seller,
                asset_contract: asset_contract,
                token_id: token_id,
                start_time: adjusted_start_time,
                end_time: adjusted_start_time + duration,
                quantity: adjusted_quantity,
                payment_token: payment_token,
                price_per_token: price_per_token,
                asset_type: asset_type,
            };

            self.listings.write(listing_id, new_listing);
            self
                .emit(
                    Event::ListingCreated(
                        ListingCreated {
                            listing_id, asset_contract, seller, listing: new_listing,
                        }
                    )
                );
        }

        // Removes listing by replacing with empty listing
        fn remove_listing(ref self: ContractState, listing_id: u256) {
            self.require_seller(listing_id);
            let target_listing = self.listings.read(listing_id);
            let empty_listing = Listing {
                listing_id: 0,
                seller: contract_address_const::<0>(),
                asset_contract: contract_address_const::<0>(),
                token_id: 0,
                start_time: 0,
                end_time: 0,
                quantity: 0,
                payment_token: contract_address_const::<0>(),
                price_per_token: 0,
                asset_type: 0,
            };
            self.listings.write(listing_id, empty_listing);
            self
                .emit(
                    Event::ListingCancelled(
                        ListingCancelled {
                            listing_id, seller: target_listing.seller
                        }
                    )
                );
        }

        // Places a bid/offer on an existing listing
        fn place_bid(
            ref self: ContractState,
            listing_id: u256,
            quantity: u256,
            payment_token: ContractAddress,
            price_per_token: u256,
            expiration: u256
        ) {
            self.require_listing_exists(listing_id);
            let target_listing = self.listings.read(listing_id);
            
            // Check listing is active (within time window)
            assert(
                target_listing.end_time > get_block_timestamp().into()
                    && target_listing.start_time < get_block_timestamp().into(),
                'Listing not active'
            );
            
            let mut new_bid = Bid {
                listing_id: listing_id,
                bidder: get_caller_address(),
                quantity: quantity,
                payment_token: payment_token,
                price_per_token: price_per_token,
                expiration: expiration
            };

            // Normalize quantity for token type
            new_bid
                .quantity = self
                .normalize_quantity(target_listing.asset_type, quantity);
            self.process_bid(target_listing, new_bid);
        }

        // Seller accepts a specific offer
        fn accept_bid(
            ref self: ContractState,
            listing_id: u256,
            bidder: ContractAddress,
            payment_token: ContractAddress,
            price_per_token: u256
        ) {
            self.require_seller(listing_id);
            self.require_listing_exists(listing_id);
            let bid = self.bids.read((listing_id, bidder));
            let listing = self.listings.read(listing_id);

            // Validate offer details match
            assert(
                payment_token == bid.payment_token && price_per_token == bid.price_per_token,
                'Bid details mismatch'
            );
            // Check offer hasn't expired
            assert(bid.expiration > get_block_timestamp().into(), 'Bid expired');
            
            // Clear offer after acceptance
            let empty_bid = Bid {
                listing_id: 0,
                bidder: contract_address_const::<0>(),
                quantity: 0,
                payment_token: contract_address_const::<0>(),
                price_per_token: 0,
                expiration: 0,
            };

            self.bids.write((listing_id, bidder), empty_bid);

            // Execute the sale based on accepted offer
            self
                .complete_sale(
                    listing,
                    bidder,
                    bidder,
                    bid.payment_token,
                    bid.price_per_token * bid.quantity,
                    bid.quantity
                );
        }

        // Direct purchase at listed price
        fn purchase(
            ref self: ContractState,
            listing_id: u256,
            recipient: ContractAddress,
            quantity: u256,
            payment_token: ContractAddress,
            total_price: u256,
        ) {
            self.require_listing_exists(listing_id);
            let listing = self.listings.read(listing_id);
            let buyer = get_caller_address();

            // Validate price and currency match
            assert(
                payment_token == listing.payment_token
                    && total_price == (listing.price_per_token * quantity),
                'Price mismatch'
            );

            // Execute the direct sale
            self
                .complete_sale(
                    listing,
                    buyer,
                    recipient,
                    listing.payment_token,
                    listing.price_per_token * quantity,
                    quantity
                );
        }

        // Modify existing listing parameters
        fn modify_listing(
            ref self: ContractState,
            listing_id: u256,
            quantity: u256,
            reserve_price: u256,
            buy_now_price: u256,
            payment_token: ContractAddress,
            mut start_time: u256,
            duration: u256,
        ) {
            self.require_seller(listing_id);
            let listing = self.listings.read(listing_id);
            let safe_quantity = self.normalize_quantity(listing.asset_type, quantity);
            assert(safe_quantity != 0, 'Invalid quantity');

            // Auto-adjust start_time if in the past
            let timestamp: u256 = get_block_timestamp().into();
            if (start_time < timestamp) {
                assert(timestamp - start_time < 3600, 'Start time too old');
                start_time = timestamp;
            }
            
            // Retain original values if updates are zero/empty
            let new_start_time = if start_time == 0 {
                listing.start_time
            } else {
                start_time
            };
            
            self
                .listings
                .write(
                    listing_id,
                    Listing {
                        listing_id: listing_id,
                        seller: get_caller_address(),
                        asset_contract: listing.asset_contract,
                        token_id: listing.token_id,
                        start_time: new_start_time,
                        end_time: if duration == 0 {
                            listing.end_time
                        } else {
                            new_start_time + duration
                        },
                        quantity: safe_quantity,
                        payment_token: payment_token,
                        price_per_token: buy_now_price,
                        asset_type: listing.asset_type,
                    }
                );
                
            // Re-validate ownership if quantity changed
            if (listing.quantity != safe_quantity) {
                self
                    .verify_ownership_and_approval(
                        listing.seller,
                        listing.asset_contract,
                        listing.token_id,
                        safe_quantity,
                        listing.asset_type
                    );
            }

            self
                .emit(
                    Event::ListingModified(
                        ListingModified {
                            listing_id: listing_id, seller: listing.seller,
                        }
                    )
                );
        }

        // Returns total number of listings created
        fn get_listing_count(self: @ContractState) -> u256 {
            self.listing_count.read()
        }
    }

    #[generate_trait]
    impl StorageImpl of StorageTrait {
        // Handles quantity normalization (ERC721=1, ERC1155=variable)
        fn normalize_quantity(
            self: @ContractState, asset_type: u256, raw_quantity: u256
        ) -> u256 {
            if raw_quantity == 0 {
                0
            } else {
                if asset_type == TYPE_ERC721 {
                    1
                } else {
                    raw_quantity
                }
            }
        }

        // Verifies token ownership and marketplace approval
        fn verify_ownership_and_approval(
            self: @ContractState,
            owner: ContractAddress,
            asset_contract: ContractAddress,
            token_id: u256,
            quantity: u256,
            asset_type: u256
        ) {
            let marketplace = get_contract_address();
            let mut is_valid: bool = false;
            if (asset_type == TYPE_ERC1155) {
                let token = IERC1155Dispatcher { contract_address: asset_contract };
                is_valid = token.balance_of(owner, token_id) >= quantity
                    && token.is_approved_for_all(owner, marketplace);
            } else if (asset_type == TYPE_ERC721) {
                let token = IERC721Dispatcher { contract_address: asset_contract };
                is_valid = token.owner_of(token_id) == owner
                    && token.get_approved(token_id) == marketplace
                        || token.is_approved_for_all(owner, marketplace);
            }

            assert(is_valid, 'Not owned or approved');
        }

        // Processes and stores new bids
        fn process_bid(ref self: ContractState, listing: Listing, bid: Bid) {
            assert(
                bid.quantity <= listing.quantity && listing.quantity > 0,
                'Insufficient available quantity'
            );
            
            // Verify bidder has sufficient funds and approval
            self
                .check_token_balance_and_allowance(
                    bid.bidder,
                    bid.payment_token,
                    bid.price_per_token * bid.quantity
                );

            // Store bid and emit event
            self.bids.write((listing.listing_id, bid.bidder), bid);
            self
                .emit(
                    Event::BidPlaced(
                        BidPlaced {
                            listing_id: listing.listing_id,
                            bidder: bid.bidder,
                            quantity: bid.quantity,
                            total_bid_amount: bid.price_per_token * bid.quantity,
                            payment_token: bid.payment_token
                        }
                    )
                );
        }

        // Ensures sufficient balance and approval for payments
        fn check_token_balance_and_allowance(
            ref self: ContractState,
            account: ContractAddress,
            token: ContractAddress,
            amount: u256
        ) {
            let erc20 = IERC20Dispatcher { contract_address: token };
            assert(
                erc20.balance_of(account) >= amount
                    && erc20
                        .allowance(
                            account, get_contract_address()
                        ) >= amount,
                'Insufficient funds'
            );
        }

        // Orchestrates the exchange of tokens and payment
        fn complete_sale(
            ref self: ContractState,
            mut listing: Listing,
            payer: ContractAddress,
            recipient: ContractAddress,
            payment_token: ContractAddress,
            total_amount: u256,
            quantity: u256,
        ) {
            // Validate all sale conditions
            self
                .validate_sale(
                    listing,
                    payer,
                    quantity,
                    payment_token,
                    total_amount
                );

            // Update listing quantity or remove if sold out
            listing.quantity -= quantity;
            self.listings.write(listing.listing_id, listing);
            
            // Transfer payment to seller
            self
                .process_payment(
                    payer,
                    listing.seller,
                    payment_token,
                    total_amount,
                    listing
                );
                
            // Transfer tokens to buyer
            self
                .transfer_asset(
                    listing.seller,
                    recipient,
                    quantity,
                    listing
                );
                
            // Emit sale event
            self
                .emit(
                    Event::AssetSold(
                        AssetSold {
                            listing_id: listing.listing_id,
                            asset_contract: listing.asset_contract,
                            seller: listing.seller,
                            buyer: recipient,
                            quantity: quantity,
                            price_paid: total_amount,
                        }
                    )
                );
        }

        // Checks all requirements for a successful sale
        fn validate_sale(
            ref self: ContractState,
            listing: Listing,
            payer: ContractAddress,
            quantity: u256,
            payment_token: ContractAddress,
            total_price: u256,
        ) {
            // Verify token quantity is valid
            assert(
                listing.quantity > 0 && quantity > 0 && quantity <= listing.quantity,
                'Invalid quantity'
            );
            
            // Verify listing is active (within time window)
            assert(
                get_block_timestamp().into() < listing.end_time
                    && get_block_timestamp().into() > listing.start_time,
                'Listing not active'
            );
            
            // Verify buyer has sufficient funds and approval
            self.check_token_balance_and_allowance(payer, payment_token, total_price);
            
            // Verify seller still owns and has approved tokens
            self
                .verify_ownership_and_approval(
                    listing.seller,
                    listing.asset_contract,
                    listing.token_id,
                    quantity,
                    listing.asset_type
                );
        }

        // Handles payment transfer to seller
        fn process_payment(
            ref self: ContractState,
            payer: ContractAddress,
            payee: ContractAddress,
            payment_token: ContractAddress,
            amount: u256,
            listing: Listing,
        ) {
            self.transfer_erc20(payment_token, payer, payee, amount);
        }

        // Handles token transfer to buyer based on token type
        fn transfer_asset(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            quantity: u256,
            listing: Listing,
        ) {
            if listing.asset_type == TYPE_ERC1155 {
                let token = IERC1155Dispatcher { contract_address: listing.asset_contract };
                token
                    .safe_transfer_from(
                        from, to, listing.token_id, quantity, ArrayTrait::<felt252>::new().span()
                    );
            } else if listing.asset_type == TYPE_ERC721 {
                let token = IERC721Dispatcher { contract_address: listing.asset_contract };
                token.transfer_from(from, to, listing.token_id);
            }
        }

        // Safely transfers ERC20 tokens with validation
        fn transfer_erc20(
            ref self: ContractState,
            token: ContractAddress,
            from: ContractAddress,
            to: ContractAddress,
            amount: u256,
        ) {
            // Skip if amount is zero or sender equals recipient
            if (amount == 0) || (from == to) {
                return;
            }

            let erc20 = IERC20Dispatcher { contract_address: token };
            if from == get_contract_address() {
                erc20.transfer(to, amount);
            } else {
                erc20.transfer_from(from, to, amount);
            }
        }

        // Access control for listing owner operations
        fn require_seller(self: @ContractState, listing_id: u256) {
            assert(self.listings.read(listing_id).seller == get_caller_address(), 'Not the seller');
        }

        // Ensures listing exists before operations
        fn require_listing_exists(self: @ContractState, listing_id: u256) {
            assert(
                self.listings.read(listing_id).asset_contract != contract_address_const::<0>(), 'Listing does not exist'
            );
        }
    }
}