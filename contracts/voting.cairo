#[starknet::interface]
trait IVoteContract<TContractState> {
    fn create_vote(
        ref self: TContractState,
        title: felt252,
        description: felt252,
        candidates: Span<felt252>,
        voting_delay: u64,
        voting_period: u64
    ) -> u32;
    fn get_candidate_count(self: @TContractState, vote_id: u32) -> u32;
    fn vote(ref self: TContractState, vote_id: u32, candidate_id: u32);
    fn get_vote_details(self: @TContractState, vote_id: u32) -> (felt252, felt252, u64, u64);
    fn get_vote_count(self: @TContractState) -> u32;
    fn get_vote_results(self: @TContractState, vote_id: u32) -> Span<(felt252, u32)>;
    fn is_voting_active(self: @TContractState, vote_id: u32) -> bool;
}

#[starknet::contract]
mod VoteContract {
    use core::starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use OwnableComponent::InternalTrait;
    use openzeppelin::access::ownable::OwnableComponent;
    use starknet::{
        ContractAddress, get_caller_address, get_block_timestamp, event::EventEmitter, storage::Map
    };

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        votes: Map<u32, VoteNode>,
        vote_count: u32,
        candidates: Map<(u32, u32), felt252>,
        votes_cast: Map<(u32, u32), u32>,
        voters: Map<(u32, ContractAddress), bool>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage
    }

    #[derive(Drop, Serde, starknet::Store, Clone)]
    struct VoteNode {
        title: felt252,
        description: felt252,
        candidates_count: u32,
        voting_start_time: u64,
        voting_end_time: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        VoteCast: VoteCast,
        VoteCreated: VoteCreated,
        #[flat]
        OwnableEvent: OwnableComponent::Event
    }

    #[derive(Drop, starknet::Event)]
    struct VoteCreated {
        #[key]
        vote_id: u32,
        title: felt252,
        description: felt252,
        voting_start_time: u64,
        voting_end_time: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct VoteCast {
        #[key]
        vote_id: u32,
        voter: ContractAddress,
        candidate_id: u32,
    }

    #[constructor]
    fn constructor(ref self: ContractState, initial_owner: ContractAddress) {
        self.vote_count.write(0);
        self.ownable.initializer(initial_owner);
    }

    #[abi(embed_v0)]
    impl IVoteContractImpl of super::IVoteContract<ContractState> {
        fn create_vote(
            ref self: ContractState,
            title: felt252,
            description: felt252,
            candidates: Span<felt252>,
            voting_delay: u64,
            voting_period: u64
        ) -> u32 {
            self.ownable.assert_only_owner();

            assert!(title != 0, "Title cannot be empty");
            assert!(description != 0, "Description cannot be empty");

            assert!(candidates.len() > 0, "At least one candidate is required");
            for i in 0
                ..candidates
                    .len() {
                        assert!(*candidates.at(i.into()) != 0, "Candidate name cannot be empty");
                    };

            assert!(voting_delay > 0, "Voting delay must be greater than 0");
            assert!(voting_period > 0, "Voting period must be greater than 0");

            let mut vote_count = self.vote_count.read() + 1;
            self.vote_count.write(vote_count);

            let current_time = get_block_timestamp();
            let voting_start_time = current_time + voting_delay;
            let voting_end_time = voting_start_time + voting_period;

            let vote = VoteNode {
                title,
                description,
                candidates_count: candidates.len(),
                voting_start_time,
                voting_end_time,
            };

            self.votes.write(vote_count, vote.clone());

            let mut i: u32 = 0;
            loop {
                if i >= candidates.len() {
                    break;
                }
                self.candidates.write((vote_count, i), *candidates.at(i.into()));
                i += 1;
            };

            self
                .emit(
                    Event::VoteCreated(
                        VoteCreated {
                            vote_id: vote_count,
                            title,
                            description,
                            voting_start_time,
                            voting_end_time,
                        }
                    )
                );
            vote_count
        }

        fn get_candidate_count(self: @ContractState, vote_id: u32) -> u32 {
            assert!(vote_id > 0 && vote_id <= self.vote_count.read(), "Invalid vote ID");
            let vote = self.votes.read(vote_id);
            vote.candidates_count
        }

        fn vote(ref self: ContractState, vote_id: u32, candidate_id: u32) {
            assert!(vote_id > 0 && vote_id <= self.vote_count.read(), "Invalid vote ID");
            let vote = self.votes.read(vote_id);
            assert!(candidate_id < vote.candidates_count, "Invalid candidate ID");

            let caller = get_caller_address();
            let current_time = get_block_timestamp();

            assert!(current_time >= vote.voting_start_time, "Voting has not started yet");
            assert!(current_time <= vote.voting_end_time, "Voting period has ended");
            assert!(!self.voters.read((vote_id, caller)), "Caller has already voted");

            let current_votes = self.votes_cast.read((vote_id, candidate_id));
            self.votes_cast.write((vote_id, candidate_id), current_votes + 1);
            self.voters.write((vote_id, caller), true);

            self.emit(Event::VoteCast(VoteCast { vote_id, voter: caller, candidate_id, }));
        }

        fn get_vote_details(self: @ContractState, vote_id: u32) -> (felt252, felt252, u64, u64) {
            assert!(vote_id > 0 && vote_id <= self.vote_count.read(), "Invalid vote ID");
            let vote = self.votes.read(vote_id);
            (vote.title, vote.description, vote.voting_start_time, vote.voting_end_time)
        }

        fn get_vote_count(self: @ContractState) -> u32 {
            self.vote_count.read()
        }

        fn get_vote_results(self: @ContractState, vote_id: u32) -> Span<(felt252, u32)> {
            assert!(vote_id > 0 && vote_id <= self.vote_count.read(), "Invalid vote ID");
            let vote = self.votes.read(vote_id);
            let mut results = ArrayTrait::new();
            let mut i: u32 = 0;
            loop {
                if i >= vote.candidates_count {
                    break;
                }
                let candidate = self.candidates.read((vote_id, i));
                let votes = self.votes_cast.read((vote_id, i));
                results.append((candidate, votes));
                i += 1;
            };
            results.span()
        }

        fn is_voting_active(self: @ContractState, vote_id: u32) -> bool {
            assert!(vote_id > 0 && vote_id <= self.vote_count.read(), "Invalid vote ID");
            let vote = self.votes.read(vote_id);
            let current_time = get_block_timestamp();
            current_time >= vote.voting_start_time && current_time <= vote.voting_end_time
        }
    }
}
