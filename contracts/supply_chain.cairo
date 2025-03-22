use core::array::Array;
use core::num::traits::Zero;
use core::traits::Into;
use starknet::class_hash::ClassHash;
use starknet::syscalls::replace_class_syscall;
use starknet::{
    ContractAddress
};


#[starknet::interface]
trait ISupplyChain<TContractState> {
    // User registration functions
    fn register_seller(ref self: TContractState, name: felt252, location: felt252);
    fn register_buyer(ref self: TContractState, name: felt252, location: felt252);
    fn register_delivery(ref self: TContractState, name: felt252, service_area: felt252);

    // Order management functions
    fn create_order(
        ref self: TContractState,
        seller_id: u64,
        description: felt252,
        quantity: u64,
        price_per_unit: u256,
        payment_token: ContractAddress,
    );
    fn accept_order(ref self: TContractState, order_id: u64, estimated_delivery_time: u64);
    fn reject_order(ref self: TContractState, order_id: u64, reason: felt252);    
    fn deposit_escrow(ref self: TContractState, order_id: u64);
    fn release_payment(ref self: TContractState, order_id: u64);   
    fn assign_delivery(ref self: TContractState, order_id: u64, delivery_id: u64);
    fn update_delivery_status(ref self: TContractState, order_id: u64, status: u8, notes: felt252);
    fn confirm_delivery(ref self: TContractState, order_id: u64);  
    fn request_refund(ref self: TContractState, order_id: u64, reason: felt252);
    fn process_refund(ref self: TContractState, order_id: u64, approved: bool);    
    fn get_order_details(self: @TContractState, order_id: u64) -> SupplyChain::Order;
    fn get_user_details(self: @TContractState, user_id: u64, user_type: u8) -> SupplyChain::User;
    fn get_user_orders(self: @TContractState, user_id: u64, user_type: u8) -> Array<u64>;
    fn get_delivery_details(self: @TContractState, order_id: u64) -> SupplyChain::DeliveryDetails;
    fn attach_certificate(
        ref self: TContractState,
        order_id: u64,
        certificate_type: felt252,
        certificate_hash: felt252,
    );
    //for high regulatory products like phamaceuticals
    fn get_order_certificates(
        self: @TContractState, order_id: u64,
    ) -> Array<SupplyChain::Certificate>;
    fn get_certificate_count(self: @TContractState, order_id: u64) -> u64;

    //checkpoints
    fn record_checkpoint(
        ref self: TContractState, 
        order_id: u64, 
        location: felt252,
        notes: felt252
    );
    fn get_order_checkpoints(self: @TContractState, order_id: u64) -> Array<SupplyChain::SupplyChainCheckpoint>;
    fn get_checkpoint_count(self: @TContractState, order_id: u64) -> u64;

    fn deactivate_my_account(ref self: TContractState);

}

// Interface for ERC20 tokens used for payments
#[starknet::interface]
trait IERC20<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256,
    );
}

#[starknet::contract]
mod SupplyChain {
    use core::array::ArrayTrait;
    use core::num::traits::Zero;
    use core::option::OptionTrait;
    use core::starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use core::traits::Into;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::class_hash::ClassHash;
    use starknet::syscalls::replace_class_syscall;
    use starknet::{
        ContractAddress, contract_address_const, get_block_timestamp, get_caller_address,
        get_contract_address,
    };

    // Constants for user types
    const USER_TYPE_SELLER: u8 = 1;
    const USER_TYPE_BUYER: u8 = 2;
    const USER_TYPE_DELIVERY: u8 = 3;

    // Constants for order status
    const ORDER_STATUS_CREATED: u8 = 1;
    const ORDER_STATUS_ACCEPTED: u8 = 2;
    const ORDER_STATUS_REJECTED: u8 = 3;
    const ORDER_STATUS_PAID: u8 = 4;
    const ORDER_STATUS_PROCESSING: u8 = 5;
    const ORDER_STATUS_SHIPPED: u8 = 6;
    const ORDER_STATUS_DELIVERED: u8 = 7;
    const ORDER_STATUS_COMPLETED: u8 = 8;
    const ORDER_STATUS_REFUND_REQUESTED: u8 = 9;
    const ORDER_STATUS_REFUNDED: u8 = 10;
    const ORDER_STATUS_CANCELLED: u8 = 11;

    // Constants for delivery status
    const DELIVERY_STATUS_ASSIGNED: u8 = 1;
    const DELIVERY_STATUS_PICKED_UP: u8 = 2;
    const DELIVERY_STATUS_IN_TRANSIT: u8 = 3;
    const DELIVERY_STATUS_DELIVERED: u8 = 4;

    // Main storage for the contract
    #[storage]
    struct Storage {
        admin: ContractAddress,
        // Counters for IDs
        seller_count: u64,
        buyer_count: u64,
        delivery_count: u64,
        order_count: u64,
        // User mappings
        sellers: Map<u64, User>,
        buyers: Map<u64, User>,
        delivery_agents: Map<u64, User>,
        // Reverse lookup: address to user ID
        address_to_seller: Map<ContractAddress, u64>,
        address_to_buyer: Map<ContractAddress, u64>,
        address_to_delivery: Map<ContractAddress, u64>,
        // Order tracking
        orders: Map<u64, Order>,
        order_delivery_details: Map<u64, DeliveryDetails>,
        // User order history
        buyer_order_count: Map<u64, u64>,
        buyer_order_mapping: Map<(u64, u64), u64>, // (buyer_id, index) -> order_id
        seller_order_count: Map<u64, u64>,
        seller_order_mapping: Map<(u64, u64), u64>, // (seller_id, index) -> order_id
        delivery_order_count: Map<u64, u64>,
        delivery_order_mapping: Map<(u64, u64), u64>, // (delivery_id, index) -> order_id
        // Platform fee percentage (basis points: 100 = 1%)
        platform_fee_bps: u16,
        // Certificate tracking
        certificate_count: Map<u64, u64>, // order_id -> count of certificates
        order_certificates: Map<(u64, u64), Certificate>, // (order_id, index) -> certificate
        checkpoint_count: Map<u64, u64>, // order_id -> count of checkpoints
        order_checkpoints: Map<(u64, u64), SupplyChainCheckpoint>, // (order_id, index) -> checkpoint
    }

    // User structure for sellers, buyers, and delivery agents
    #[derive(Copy, Drop, Serde, starknet::Store)]
    pub struct User {
        id: u64,
        user_type: u8,
        address: ContractAddress,
        name: felt252,
        location_or_area: felt252,
        registration_time: u64,
        active: bool,
        rating: u8 // Rating out of 100
    }

    // Order structure to track all order details
    #[derive(Copy, Drop, Serde, starknet::Store)]
    pub struct Order {
        order_id: u64,
        buyer_id: u64,
        seller_id: u64,
        description: felt252,
        quantity: u64,
        price_per_unit: u256,
        total_price: u256,
        payment_token: ContractAddress,
        creation_time: u64,
        status: u8,
        delivery_assigned: bool,
        estimated_delivery_time: u64,
        actual_delivery_time: u64,
        refund_reason: felt252,
    }

    // Structure for tracking delivery details
    #[derive(Copy, Drop, Serde, starknet::Store)]
    pub struct DeliveryDetails {
        order_id: u64,
        delivery_id: u64,
        status: u8,
        pickup_time: u64,
        latest_update_time: u64,
        delivery_notes: felt252,
        tracking_info: felt252,
    }

    #[derive(Copy, Drop, Serde, starknet::Store)]
    pub struct Certificate {
        order_id: u64,
        certificate_id: u64,
        certificate_type: felt252, // Could be "organic", "quality", "origin", "customs", etc.
        certificate_hash: felt252, // IPFS hash or similar content identifier
        issuer: ContractAddress, // Who issued this certificate
        issuer_type: u8, // USER_TYPE constant
        timestamp: u64,
    }
    #[derive(Copy, Drop, Serde, starknet::Store)]
pub struct SupplyChainCheckpoint {
    order_id: u64,
    checkpoint_id: u64,
    location: felt252,
    timestamp: u64,
    handler: ContractAddress,
    handler_type: u8, // USER_TYPE_SELLER, USER_TYPE_DELIVERY, etc.
    notes: felt252,
}

    // Events for important contract actions
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        UserRegistered: UserRegistered,
        OrderCreated: OrderCreated,
        OrderStatusChanged: OrderStatusChanged,
        DeliveryAssigned: DeliveryAssigned,
        DeliveryStatusUpdated: DeliveryStatusUpdated,
        EscrowDeposited: EscrowDeposited,
        PaymentReleased: PaymentReleased,
        RefundRequested: RefundRequested,
        RefundProcessed: RefundProcessed,
        CertificateAttached: CertificateAttached,
        CheckpointRecorded: CheckpointRecorded,
        UserDeactivated: UserDeactivated,
    }

    #[derive(Drop, starknet::Event)]
    struct UserRegistered {
        #[key]
        user_id: u64,
        #[key]
        user_type: u8,
        #[key]
        user_address: ContractAddress,
        name: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct OrderCreated {
        #[key]
        order_id: u64,
        #[key]
        buyer_id: u64,
        #[key]
        seller_id: u64,
        description: felt252,
        quantity: u64,
        total_price: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct OrderStatusChanged {
        #[key]
        order_id: u64,
        #[key]
        previous_status: u8,
        #[key]
        new_status: u8,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct DeliveryAssigned {
        #[key]
        order_id: u64,
        #[key]
        delivery_id: u64,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct DeliveryStatusUpdated {
        #[key]
        order_id: u64,
        #[key]
        delivery_id: u64,
        #[key]
        status: u8,
        notes: felt252,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct EscrowDeposited {
        #[key]
        order_id: u64,
        #[key]
        buyer_id: u64,
        amount: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct PaymentReleased {
        #[key]
        order_id: u64,
        #[key]
        seller_id: u64,
        amount: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct RefundRequested {
        #[key]
        order_id: u64,
        #[key]
        buyer_id: u64,
        reason: felt252,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct RefundProcessed {
        #[key]
        order_id: u64,
        #[key]
        buyer_id: u64,
        #[key]
        approved: bool,
        amount: u256,
        timestamp: u64,
    }
    #[derive(Drop, starknet::Event)]
    struct CertificateAttached {
        #[key]
        order_id: u64,
        #[key]
        certificate_id: u64,
        certificate_type: felt252,
        certificate_hash: felt252,
        issuer: ContractAddress,
        timestamp: u64,
    }
    #[derive(Drop, starknet::Event)]
    struct CheckpointRecorded {
        #[key]
        order_id: u64,
        #[key]
        checkpoint_id: u64,
        location: felt252,
        timestamp: u64,
        handler: ContractAddress,
        handler_type: u8,
    }

    #[derive(Drop, starknet::Event)]
    struct UserDeactivated {
        #[key]
        user_id: u64,
        #[key]
        user_type: u8,
        #[key]
        user_address: ContractAddress,
        timestamp: u64,
    }


    // Constructor to initialize the contract
    #[constructor]
    fn constructor(ref self: ContractState, admin_address: ContractAddress, platform_fee_bps: u16) {
        // Set admin and initial platform fee
        self.admin.write(admin_address);
        self.platform_fee_bps.write(platform_fee_bps);

        // Initialize counters
        self.seller_count.write(0);
        self.buyer_count.write(0);
        self.delivery_count.write(0);
        self.order_count.write(0);
    }

    // Function to allow contract upgrades
    #[external(v0)]
    fn upgrade(self: @ContractState, new_class_hash: ClassHash) {
        assert(!new_class_hash.is_zero(), 'Class hash cannot be zero');
        assert(get_caller_address() == self.admin.read(), 'Admin access required');
        replace_class_syscall(new_class_hash);
    }

    // Function to update platform fee
    #[external(v0)]
    fn update_platform_fee(ref self: ContractState, new_fee_bps: u16) {
        assert(get_caller_address() == self.admin.read(), 'Admin access required');
        assert(new_fee_bps <= 1000, 'Fee too high'); // Max 10%
        self.platform_fee_bps.write(new_fee_bps);
    }

    #[abi(embed_v0)]
    impl SupplyChainImpl of super::ISupplyChain<ContractState> {
        // User registration functions
        fn register_seller(ref self: ContractState, name: felt252, location: felt252) {
            assert(name != 0, 'Name cannot be empty');
            let caller = get_caller_address();

            // Check if user is already registered as a seller
            assert(self.address_to_seller.read(caller) == 0, 'Already registered');

            // Increment seller count and create new seller
            let seller_id = self.seller_count.read() + 1;
            self.seller_count.write(seller_id);

            let new_seller = User {
                id: seller_id,
                user_type: USER_TYPE_SELLER,
                address: caller,
                name: name,
                location_or_area: location,
                registration_time: get_block_timestamp().into(),
                active: true,
                rating: 70 // Default rating of 70%
            };

            // Store seller and address mapping
            self.sellers.write(seller_id, new_seller);
            self.address_to_seller.write(caller, seller_id);

            // Initialize seller order count to 0
            self.seller_order_count.write(seller_id, 0);

            // Emit event
            self
                .emit(
                    Event::UserRegistered(
                        UserRegistered {
                            user_id: seller_id,
                            user_type: USER_TYPE_SELLER,
                            user_address: caller,
                            name: name,
                        },
                    ),
                );
        }
        fn register_buyer(ref self: ContractState, name: felt252, location: felt252) {
            assert(name != 0, 'Name cannot be empty');
            let caller = get_caller_address();

            // Check if user is already registered as a buyer
            assert(self.address_to_buyer.read(caller) == 0, 'Already registered');

            // Increment buyer count and create new buyer
            let buyer_id = self.buyer_count.read() + 1;
            self.buyer_count.write(buyer_id);

            let new_buyer = User {
                id: buyer_id,
                user_type: USER_TYPE_BUYER,
                address: caller,
                name: name,
                location_or_area: location,
                registration_time: get_block_timestamp().into(),
                active: true,
                rating: 70 // Default rating of 70%
            };

            // Store buyer and address mapping
            self.buyers.write(buyer_id, new_buyer);
            self.address_to_buyer.write(caller, buyer_id);

            // Initialize buyer order count to 0
            self.buyer_order_count.write(buyer_id, 0);

            // Emit event
            self
                .emit(
                    Event::UserRegistered(
                        UserRegistered {
                            user_id: buyer_id,
                            user_type: USER_TYPE_BUYER,
                            user_address: caller,
                            name: name,
                        },
                    ),
                );
        }
        fn register_delivery(ref self: ContractState, name: felt252, service_area: felt252) {
            assert(name != 0, 'Name cannot be empty');
            let caller = get_caller_address();

            // Check if user is already registered as a delivery agent
            assert(self.address_to_delivery.read(caller) == 0, 'Already registered');

            // Increment delivery count and create new delivery agent
            let delivery_id = self.delivery_count.read() + 1;
            self.delivery_count.write(delivery_id);

            let new_delivery = User {
                id: delivery_id,
                user_type: USER_TYPE_DELIVERY,
                address: caller,
                name: name,
                location_or_area: service_area,
                registration_time: get_block_timestamp().into(),
                active: true,
                rating: 70 // Default rating of 70%
            };

            // Store delivery agent and address mapping
            self.delivery_agents.write(delivery_id, new_delivery);
            self.address_to_delivery.write(caller, delivery_id);

            // Initialize delivery order count to 0
            self.delivery_order_count.write(delivery_id, 0);

            // Emit event
            self
                .emit(
                    Event::UserRegistered(
                        UserRegistered {
                            user_id: delivery_id,
                            user_type: USER_TYPE_DELIVERY,
                            user_address: caller,
                            name: name,
                        },
                    ),
                );
        }
        // Order management functions
        fn create_order(
            ref self: ContractState,
            seller_id: u64,
            description: felt252,
            quantity: u64,
            price_per_unit: u256,
            payment_token: ContractAddress,
        ) {
            assert(description != 0, 'Description cannot be empty');
            assert(quantity > 0, 'Quantity must be positive');
            assert(price_per_unit > 0, 'Price must be positive');

         
            assert(self.sellers.read(seller_id).active, 'Seller not active');          
            let caller = get_caller_address();
            let buyer_id = self.address_to_buyer.read(caller);
            assert(buyer_id != 0, 'Not registered as buyer');

          
            let total_price = price_per_unit * quantity.into();
            self.check_token_balance_and_allowance(caller, payment_token, total_price);

            // Create new order
            let order_id = self.order_count.read() + 1;
            self.order_count.write(order_id);

            let new_order = Order {
                order_id: order_id,
                buyer_id: buyer_id,
                seller_id: seller_id,
                description: description,
                quantity: quantity,
                price_per_unit: price_per_unit,
                total_price: total_price,
                payment_token: payment_token,
                creation_time: get_block_timestamp().into(),
                status: ORDER_STATUS_CREATED,
                delivery_assigned: false,
                estimated_delivery_time: 0,
                actual_delivery_time: 0,
                refund_reason: 0,
            };

            // Store order
            self.orders.write(order_id, new_order);

            let buyer_count = self.buyer_order_count.read(buyer_id);
            self.buyer_order_mapping.write((buyer_id, buyer_count), order_id);
            self.buyer_order_count.write(buyer_id, buyer_count + 1);

            // Update seller's order history
            let current_count = self.seller_order_count.read(seller_id);
            self.seller_order_mapping.write((seller_id, current_count), order_id);
            self.seller_order_count.write(seller_id, current_count + 1);

            // Emit event
            self
                .emit(
                    Event::OrderCreated(
                        OrderCreated {
                            order_id: order_id,
                            buyer_id: buyer_id,
                            seller_id: seller_id,
                            description: description,
                            quantity: quantity,
                            total_price: total_price,
                        },
                    ),
                );

            // Emit status change event
            self
                .emit(
                    Event::OrderStatusChanged(
                        OrderStatusChanged {
                            order_id: order_id,
                            previous_status: 0,
                            new_status: ORDER_STATUS_CREATED,
                            timestamp: get_block_timestamp().into(),
                        },
                    ),
                );
        }

        fn accept_order(ref self: ContractState, order_id: u64, estimated_delivery_time: u64) {
            // Verify order exists and is in correct state
            self.require_order_exists(order_id);
            let mut order = self.orders.read(order_id);
            assert(order.status == ORDER_STATUS_CREATED, 'Invalid order status');

            // Verify caller is the seller
            let caller = get_caller_address();
            let seller_id = self.address_to_seller.read(caller);
            assert(seller_id == order.seller_id, 'Not the seller');

            // Validate estimated delivery time
            let current_time = get_block_timestamp().into();
            assert(estimated_delivery_time > current_time, 'Invalid delivery time');

            // Update order
            let previous_status = order.status;
            order.status = ORDER_STATUS_ACCEPTED;
            order.estimated_delivery_time = estimated_delivery_time;
            self.orders.write(order_id, order);

            // Emit status change event
            self
                .emit(
                    Event::OrderStatusChanged(
                        OrderStatusChanged {
                            order_id: order_id,
                            previous_status: previous_status,
                            new_status: ORDER_STATUS_ACCEPTED,
                            timestamp: current_time,
                        },
                    ),
                );
        }

        fn reject_order(ref self: ContractState, order_id: u64, reason: felt252) {
            // Verify order exists and is in correct state
            self.require_order_exists(order_id);
            let mut order = self.orders.read(order_id);
            assert(order.status == ORDER_STATUS_CREATED, 'Invalid order status');

            // Verify caller is the seller
            let caller = get_caller_address();
            let seller_id = self.address_to_seller.read(caller);
            assert(seller_id == order.seller_id, 'Not the seller');

            // Update order
            let previous_status = order.status;
            order.status = ORDER_STATUS_REJECTED;
            order.refund_reason = reason;
            self.orders.write(order_id, order);

            // Emit status change event
            self
                .emit(
                    Event::OrderStatusChanged(
                        OrderStatusChanged {
                            order_id: order_id,
                            previous_status: previous_status,
                            new_status: ORDER_STATUS_REJECTED,
                            timestamp: get_block_timestamp().into(),
                        },
                    ),
                );
        }

        // Payment and escrow functions
        fn deposit_escrow(ref self: ContractState, order_id: u64) {
            // Verify order exists and is in correct state
            self.require_order_exists(order_id);
            let mut order = self.orders.read(order_id);
            assert(order.status == ORDER_STATUS_ACCEPTED, 'Order not accepted');

            // Verify caller is the buyer
            let caller = get_caller_address();
            let buyer_id = self.address_to_buyer.read(caller);
            assert(buyer_id == order.buyer_id, 'Not the buyer');

            // Check buyer has sufficient token balance and allowance
            self.check_token_balance_and_allowance(caller, order.payment_token, order.total_price);

            // Transfer tokens from buyer to contract (escrow)
            self
                .transfer_erc20(
                    order.payment_token, caller, get_contract_address(), order.total_price,
                );

            // Update order status
            let previous_status = order.status;
            order.status = ORDER_STATUS_PAID;
            self.orders.write(order_id, order);

            // Emit events
            self
                .emit(
                    Event::EscrowDeposited(
                        EscrowDeposited {
                            order_id: order_id,
                            buyer_id: buyer_id,
                            amount: order.total_price,
                            timestamp: get_block_timestamp().into(),
                        },
                    ),
                );

            self
                .emit(
                    Event::OrderStatusChanged(
                        OrderStatusChanged {
                            order_id: order_id,
                            previous_status: previous_status,
                            new_status: ORDER_STATUS_PAID,
                            timestamp: get_block_timestamp().into(),
                        },
                    ),
                );
        }

        fn release_payment(ref self: ContractState, order_id: u64) {
            // Verify order exists and is in correct state
            self.require_order_exists(order_id);
            let mut order = self.orders.read(order_id);
            assert(order.status == ORDER_STATUS_DELIVERED, 'Order not delivered');

            // Verify caller is the buyer
            let caller = get_caller_address();
            let buyer_id = self.address_to_buyer.read(caller);
            assert(buyer_id == order.buyer_id, 'Not the buyer');

            // Get seller's address
            let seller = self.sellers.read(order.seller_id);

            // Calculate platform fee
            let platform_fee_bps = self.platform_fee_bps.read();
            let platform_fee = (order.total_price * platform_fee_bps.into()) / 10000;
            let seller_payment = order.total_price - platform_fee;

            // Transfer tokens from contract to seller
            self
                .transfer_erc20(
                    order.payment_token, get_contract_address(), seller.address, seller_payment,
                );

            // Transfer platform fee to admin (if fee is positive)
            if platform_fee > 0 {
                self
                    .transfer_erc20(
                        order.payment_token,
                        get_contract_address(),
                        self.admin.read(),
                        platform_fee,
                    );
            }

            // Update order status
            let previous_status = order.status;
            order.status = ORDER_STATUS_COMPLETED;
            order.actual_delivery_time = get_block_timestamp().into();
            self.orders.write(order_id, order);

            // Emit events
            self
                .emit(
                    Event::PaymentReleased(
                        PaymentReleased {
                            order_id: order_id,
                            seller_id: order.seller_id,
                            amount: seller_payment,
                            timestamp: get_block_timestamp().into(),
                        },
                    ),
                );

            self
                .emit(
                    Event::OrderStatusChanged(
                        OrderStatusChanged {
                            order_id: order_id,
                            previous_status: previous_status,
                            new_status: ORDER_STATUS_COMPLETED,
                            timestamp: get_block_timestamp().into(),
                        },
                    ),
                );
        }

        // Delivery functions
        fn assign_delivery(ref self: ContractState, order_id: u64, delivery_id: u64) {
            // Verify order exists and is in correct state
            self.require_order_exists(order_id);
            let mut order = self.orders.read(order_id);
            assert(order.status == ORDER_STATUS_PAID, 'Order not paid');
            assert(!order.delivery_assigned, 'Delivery already assigned');

            // Verify caller is the seller
            let caller = get_caller_address();
            let seller_id = self.address_to_seller.read(caller);
            assert(seller_id == order.seller_id, 'Not the seller');

            // Verify delivery agent exists
            let delivery_agent = self.delivery_agents.read(delivery_id);
            assert(delivery_agent.active, 'Delivery agent not active');

            // Create delivery details
            let delivery_details = DeliveryDetails {
                order_id: order_id,
                delivery_id: delivery_id,
                status: DELIVERY_STATUS_ASSIGNED,
                pickup_time: 0,
                latest_update_time: get_block_timestamp().into(),
                delivery_notes: 0,
                tracking_info: 0,
            };

            // Update order
            order.delivery_assigned = true;
            order.status = ORDER_STATUS_PROCESSING;
            self.orders.write(order_id, order);
            self.order_delivery_details.write(order_id, delivery_details);

            // Update delivery agent's order history
            let delivery_order_idx = self.delivery_order_count.read(delivery_id);
            self.delivery_order_mapping.write((delivery_id, delivery_order_idx), order_id);
            self.delivery_order_count.write(delivery_id, delivery_order_idx + 1);

            // Emit events
            self
                .emit(
                    Event::DeliveryAssigned(
                        DeliveryAssigned {
                            order_id: order_id,
                            delivery_id: delivery_id,
                            timestamp: get_block_timestamp().into(),
                        },
                    ),
                );

            self
                .emit(
                    Event::OrderStatusChanged(
                        OrderStatusChanged {
                            order_id: order_id,
                            previous_status: ORDER_STATUS_PAID,
                            new_status: ORDER_STATUS_PROCESSING,
                            timestamp: get_block_timestamp().into(),
                        },
                    ),
                );
        }

        // delivery agent updates order status to delivered
        fn update_delivery_status(
            ref self: ContractState, order_id: u64, status: u8, notes: felt252,
        ) {
            // Verify order exists and has delivery assigned
            self.require_order_exists(order_id);
            let mut order = self.orders.read(order_id);
            assert(order.delivery_assigned, 'No delivery assigned');

            // Get delivery details
            let mut delivery_details = self.order_delivery_details.read(order_id);

            // Verify caller is the assigned delivery agent
            let caller = get_caller_address();
            let delivery_id = self.address_to_delivery.read(caller);
            assert(delivery_id == delivery_details.delivery_id, 'Not the delivery agent');

            // Validate status transition
            assert(
                status > delivery_details.status && status <= DELIVERY_STATUS_DELIVERED,
                'Invalid status',
            );

            // Update delivery details
            delivery_details.status = status;
            delivery_details.latest_update_time = get_block_timestamp().into();
            delivery_details.delivery_notes = notes;

            // If status is picked up, update pickup time
            if status == DELIVERY_STATUS_PICKED_UP {
                delivery_details.pickup_time = get_block_timestamp().into();
            }

            self.order_delivery_details.write(order_id, delivery_details);

            // Update order status if delivery is completed
            if status == DELIVERY_STATUS_DELIVERED {
                let previous_status = order.status;
                order.status = ORDER_STATUS_DELIVERED;
                self.orders.write(order_id, order);

                // Emit order status change event
                self
                    .emit(
                        Event::OrderStatusChanged(
                            OrderStatusChanged {
                                order_id: order_id,
                                previous_status: previous_status,
                                new_status: ORDER_STATUS_DELIVERED,
                                timestamp: get_block_timestamp().into(),
                            },
                        ),
                    );
            }

            // Emit delivery status update event
            self
                .emit(
                    Event::DeliveryStatusUpdated(
                        DeliveryStatusUpdated {
                            order_id: order_id,
                            delivery_id: delivery_id,
                            status: status,
                            notes: notes,
                            timestamp: get_block_timestamp().into(),
                        },
                    ),
                );
        }

        // user confirms order
        fn confirm_delivery(ref self: ContractState, order_id: u64) {
            // Verify order exists and is in correct state
            self.require_order_exists(order_id);
            let order = self.orders.read(order_id);
            assert(order.status == ORDER_STATUS_DELIVERED, 'Order not delivered');

            // Verify caller is the buyer
            let caller = get_caller_address();
            let buyer_id = self.address_to_buyer.read(caller);
            assert(buyer_id == order.buyer_id, 'Not the buyer');          
            self.release_payment(order_id);
        }

        // Refund functions
        fn request_refund(ref self: ContractState, order_id: u64, reason: felt252) {            
            self.require_order_exists(order_id);
            let mut order = self.orders.read(order_id);           
            assert(
                order.status == ORDER_STATUS_PAID
                    || order.status == ORDER_STATUS_PROCESSING
                    || order.status == ORDER_STATUS_SHIPPED,
                'Invalid order status for refund',
            );

            // Verify caller is the buyer
            let caller = get_caller_address();
            let buyer_id = self.address_to_buyer.read(caller);
            assert(buyer_id == order.buyer_id, 'Not the buyer');

            // Update order
            let previous_status = order.status;
            order.status = ORDER_STATUS_REFUND_REQUESTED;
            order.refund_reason = reason;
            self.orders.write(order_id, order);

            // Emit events
            self
                .emit(
                    Event::RefundRequested(
                        RefundRequested {
                            order_id: order_id,
                            buyer_id: buyer_id,
                            reason: reason,
                            timestamp: get_block_timestamp().into(),
                        },
                    ),
                );

            self
                .emit(
                    Event::OrderStatusChanged(
                        OrderStatusChanged {
                            order_id: order_id,
                            previous_status: previous_status,
                            new_status: ORDER_STATUS_REFUND_REQUESTED,
                            timestamp: get_block_timestamp().into(),
                        },
                    ),
                );
        }

        fn process_refund(ref self: ContractState, order_id: u64, approved: bool) {
            // Verify order exists and is in correct state
            self.require_order_exists(order_id);
            let mut order = self.orders.read(order_id);
            assert(order.status == ORDER_STATUS_REFUND_REQUESTED, 'No refund requested');

            // Verify caller is the seller
            let caller = get_caller_address();
            let seller_id = self.address_to_seller.read(caller);
            assert(seller_id == order.seller_id, 'Not the seller');

            let previous_status = order.status;

            if approved {
                // Get buyer's address
                let buyer = self.buyers.read(order.buyer_id);

                // Transfer tokens from contract to buyer
                self
                    .transfer_erc20(
                        order.payment_token,
                        get_contract_address(),
                        buyer.address,
                        order.total_price,
                    );

                // Update order status
                order.status = ORDER_STATUS_REFUNDED;
                self.orders.write(order_id, order);

                // Emit events
                self
                    .emit(
                        Event::RefundProcessed(
                            RefundProcessed {
                                order_id: order_id,
                                buyer_id: order.buyer_id,
                                approved: true,
                                amount: order.total_price,
                                timestamp: get_block_timestamp().into(),
                            },
                        ),
                    );
            } else {
                // If refund is rejected, return to previous state
                order.status = ORDER_STATUS_PAID; // Default to paid status if refund rejected
                self.orders.write(order_id, order);

                // Emit events
                self
                    .emit(
                        Event::RefundProcessed(
                            RefundProcessed {
                                order_id: order_id,
                                buyer_id: order.buyer_id,
                                approved: false,
                                amount: 0,
                                timestamp: get_block_timestamp().into(),
                            },
                        ),
                    );
            }

            // Emit status change event
            self
                .emit(
                    Event::OrderStatusChanged(
                        OrderStatusChanged {
                            order_id: order_id,
                            previous_status: previous_status,
                            new_status: order.status,
                            timestamp: get_block_timestamp().into(),
                        },
                    ),
                );
        }

        fn attach_certificate(
            ref self: ContractState,
            order_id: u64,
            certificate_type: felt252,
            certificate_hash: felt252
        ) {
            // Verify certificate parameters
            assert(certificate_type != 0, 'Certificate type required');
            assert(certificate_hash != 0, 'Certificate hash required');
            
            // Verify order exists
            self.require_order_exists(order_id);
            let order = self.orders.read(order_id);
            
            // Identify caller type and verify permission
            let caller = get_caller_address();
            let seller_id = self.address_to_seller.read(caller);
            let buyer_id = self.address_to_buyer.read(caller);
            let delivery_id = self.address_to_delivery.read(caller);
            let is_admin = caller == self.admin.read();
            
            let mut issuer_type: u8 = 0;
            
            // Check if caller is the seller, buyer, assigned delivery agent, or admin
            if seller_id == order.seller_id {
                issuer_type = USER_TYPE_SELLER;
            } else if buyer_id == order.buyer_id {
                issuer_type = USER_TYPE_BUYER;
            } else if order.delivery_assigned {
                let delivery_details = self.order_delivery_details.read(order_id);
                if delivery_id == delivery_details.delivery_id {
                    issuer_type = USER_TYPE_DELIVERY;
                }
            } else if is_admin {
                // Special type for admin-issued certificates (e.g., regulatory approval)
                issuer_type = 100; // Admin type
            }
            
            assert(issuer_type != 0, 'Not authorized');
            
            // Create new certificate
            let cert_idx = self.certificate_count.read(order_id);
            let new_cert_id = cert_idx + 1;
            
            let certificate = Certificate {
                order_id: order_id,
                certificate_id: new_cert_id,
                certificate_type: certificate_type,
                certificate_hash: certificate_hash,
                issuer: caller,
                issuer_type: issuer_type,
                timestamp: get_block_timestamp().into(),
            };
            
            // Store certificate
            self.order_certificates.write((order_id, cert_idx), certificate);
            self.certificate_count.write(order_id, new_cert_id);
            
            // Emit event
            self.emit(
                Event::CertificateAttached(
                    CertificateAttached {
                        order_id: order_id,
                        certificate_id: new_cert_id,
                        certificate_type: certificate_type,
                        certificate_hash: certificate_hash,
                        issuer: caller,
                        timestamp: get_block_timestamp().into(),
                    }
                )
            );
        }

        fn record_checkpoint(
            ref self: ContractState, 
            order_id: u64, 
            location: felt252,
            notes: felt252
        ) {
            // Verify order exists
            self.require_order_exists(order_id);
            let order = self.orders.read(order_id);
            
            // Identify caller type and verify permission
            let caller = get_caller_address();
            let seller_id = self.address_to_seller.read(caller);
            let buyer_id = self.address_to_buyer.read(caller);
            let delivery_id = self.address_to_delivery.read(caller);
            
            let mut handler_type: u8 = 0;
            
            // Check if caller is the seller, buyer, or assigned delivery agent
            if seller_id == order.seller_id {
                handler_type = USER_TYPE_SELLER;
            } else if buyer_id == order.buyer_id {
                handler_type = USER_TYPE_BUYER;
            } else if order.delivery_assigned {
                let delivery_details = self.order_delivery_details.read(order_id);
                if delivery_id == delivery_details.delivery_id {
                    handler_type = USER_TYPE_DELIVERY;
                }
            }
            
            assert(handler_type != 0, 'Not authorized');
            
            // Create new checkpoint
            let checkpoint_idx = self.checkpoint_count.read(order_id);
            let new_checkpoint_id = checkpoint_idx + 1;
            
            let checkpoint = SupplyChainCheckpoint {
                order_id: order_id,
                checkpoint_id: new_checkpoint_id,
                location: location,
                timestamp: get_block_timestamp().into(),
                handler: caller,
                handler_type: handler_type,
                notes: notes,
            };
            
            // Store checkpoint
            self.order_checkpoints.write((order_id, checkpoint_idx), checkpoint);
            self.checkpoint_count.write(order_id, new_checkpoint_id);
            
            // Emit event
            self.emit(
                Event::CheckpointRecorded(
                    CheckpointRecorded {
                        order_id: order_id,
                        checkpoint_id: new_checkpoint_id,
                        location: location,
                        timestamp: get_block_timestamp().into(),
                        handler: caller,
                        handler_type: handler_type,
                    }
                )
            );
        }


        fn deactivate_my_account(ref self: ContractState) {
            let caller = get_caller_address();
            
            // Check if caller is registered as any type of user
            let seller_id = self.address_to_seller.read(caller);
            let buyer_id = self.address_to_buyer.read(caller);
            let delivery_id = self.address_to_delivery.read(caller);
            
            // Track if any account was deactivated
            let mut deactivated = false;
            
            // Deactivate seller account if exists
            if seller_id != 0 {
                let mut seller = self.sellers.read(seller_id);
                if seller.active {
                    seller.active = false;
                    self.sellers.write(seller_id, seller);
                    
                    self.emit(
                        Event::UserDeactivated(
                            UserDeactivated {
                                user_id: seller_id,
                                user_type: USER_TYPE_SELLER,
                                user_address: caller,
                                timestamp: get_block_timestamp().into(),
                            }
                        )
                    );
                    deactivated = true;
                }
            }
            
            // Deactivate buyer account if exists
            if buyer_id != 0 {
                let mut buyer = self.buyers.read(buyer_id);
                if buyer.active {
                    buyer.active = false;
                    self.buyers.write(buyer_id, buyer);
                    
                    self.emit(
                        Event::UserDeactivated(
                            UserDeactivated {
                                user_id: buyer_id,
                                user_type: USER_TYPE_BUYER,
                                user_address: caller,
                                timestamp: get_block_timestamp().into(),
                            }
                        )
                    );
                    deactivated = true;
                }
            }
            
            // Deactivate delivery account if exists
            if delivery_id != 0 {
                let mut delivery = self.delivery_agents.read(delivery_id);
                if delivery.active {
                    delivery.active = false;
                    self.delivery_agents.write(delivery_id, delivery);
                    
                    self.emit(
                        Event::UserDeactivated(
                            UserDeactivated {
                                user_id: delivery_id,
                                user_type: USER_TYPE_DELIVERY,
                                user_address: caller,
                                timestamp: get_block_timestamp().into(),
                            }
                        )
                    );
                    deactivated = true;
                }
            }
            
            // Make sure at least one account was deactivated
            assert(deactivated, 'No active accounts found');
        }

        // Getter functions
        fn get_order_details(self: @ContractState, order_id: u64) -> Order {
            self.orders.read(order_id)
        }

        fn get_user_details(self: @ContractState, user_id: u64, user_type: u8) -> User {
            if user_type == USER_TYPE_SELLER {
                self.sellers.read(user_id)
            } else if user_type == USER_TYPE_BUYER {
                self.buyers.read(user_id)
            } else if user_type == USER_TYPE_DELIVERY {
                self.delivery_agents.read(user_id)
            } else {
                User {
                    id: 0,
                    user_type: 0,
                    address: contract_address_const::<0>(),
                    name: 0,
                    location_or_area: 0,
                    registration_time: 0,
                    active: false,
                    rating: 0,
                }
            }
        }

        fn get_user_orders(self: @ContractState, user_id: u64, user_type: u8) -> Array<u64> {
            if user_type == USER_TYPE_SELLER {
                // Seller orders logic
                let count = self.seller_order_count.read(user_id);
                let mut orders = ArrayTrait::<u64>::new();
                let mut i: u64 = 0;
                while i < count {
                    orders.append(self.seller_order_mapping.read((user_id, i)));
                    i += 1;
                }
                orders
            } else if user_type == USER_TYPE_BUYER {
                // Buyer orders logic
                let count = self.buyer_order_count.read(user_id);
                let mut orders = ArrayTrait::<u64>::new();
                let mut i: u64 = 0;
                while i < count {
                    orders.append(self.buyer_order_mapping.read((user_id, i)));
                    i += 1;
                }
                orders
            } else if user_type == USER_TYPE_DELIVERY {
                // Delivery orders logic
                let count = self.delivery_order_count.read(user_id);
                let mut orders = ArrayTrait::<u64>::new();
                let mut i: u64 = 0;
                while i < count {
                    orders.append(self.delivery_order_mapping.read((user_id, i)));
                    i += 1;
                }
                orders
            } else {
                ArrayTrait::<u64>::new()
            }
        }

        fn get_delivery_details(self: @ContractState, order_id: u64) -> DeliveryDetails {
            self.order_delivery_details.read(order_id)
        }

        fn get_order_certificates(self: @ContractState, order_id: u64) -> Array<Certificate> {
            let count = self.certificate_count.read(order_id);
            let mut certificates = ArrayTrait::<Certificate>::new();
            
            let mut i: u64 = 0;
            while i < count {
                certificates.append(self.order_certificates.read((order_id, i)));
                i += 1;
            }
            
            certificates
        }
        
        fn get_certificate_count(self: @ContractState, order_id: u64) -> u64 {
            self.certificate_count.read(order_id)
        }
        fn get_order_checkpoints(self: @ContractState, order_id: u64) -> Array<SupplyChainCheckpoint> {
            let count = self.checkpoint_count.read(order_id);
            let mut checkpoints = ArrayTrait::<SupplyChainCheckpoint>::new();
            
            let mut i: u64 = 0;
            while i < count {
                checkpoints.append(self.order_checkpoints.read((order_id, i)));
                i += 1;
            }
            
            checkpoints
        }
        
        fn get_checkpoint_count(self: @ContractState, order_id: u64) -> u64 {
            self.checkpoint_count.read(order_id)
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        // Access control for order existence
        fn require_order_exists(self: @ContractState, order_id: u64) {
            assert(order_id <= self.order_count.read(), 'Order does not exist');
            let order = self.orders.read(order_id);
            assert(order.buyer_id != 0, 'Invalid order');
        }

        // Ensures sufficient balance and approval for payments
        fn check_token_balance_and_allowance(
            ref self: ContractState, account: ContractAddress, token: ContractAddress, amount: u256,
        ) {
            let erc20 = IERC20Dispatcher { contract_address: token };
            assert(
                erc20.balance_of(account) >= amount
                    && erc20.allowance(account, get_contract_address()) >= amount,
                'Insufficient funds or allowance',
            );
        }

        // Safely transfers ERC20 tokens
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
    }
}
