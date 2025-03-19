use core::num::traits::Zero;
use starknet::ContractAddress;

#[derive(Copy, Drop, Hash)]
struct ProposalId {
    id: u64
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct Proposal {
    proposer: ContractAddress,
    description: felt252,
    for_votes: u256,
    against_votes: u256,
    start_block: u64,
    end_block: u64,
    executed: bool
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct Member {
    address: ContractAddress,
    voting_power: u256
}

#[starknet::interface]
pub trait IDAO<TContractState> {
    fn create_proposal(ref self: TContractState, description: felt252);
    fn vote(ref self: TContractState, proposal_id: ProposalId, support: bool);
    fn execute_proposal(ref self: TContractState, proposal_id: ProposalId);
    fn add_member(ref self: TContractState, member: ContractAddress, voting_power: u256);
    fn remove_member(ref self: TContractState, member: ContractAddress);
    fn get_proposal(self: @TContractState, proposal_id: ProposalId) -> Proposal;
    fn get_member(self: @TContractState, member: ContractAddress) -> Member;
}

#[starknet::contract]
mod dao {
    use core::num::traits::Zero;
    use starknet::{ContractAddress, get_caller_address, get_block_number};
    use super::{IDAO, ProposalId, Proposal, Member};

    #[storage]
    struct Storage {
        proposals: LegacyMap<ProposalId, Proposal>,
        members: LegacyMap<ContractAddress, Member>,
        next_proposal_id: u64
    }

    #[event]
    enum Event {
        ProposalCreated: ProposalCreatedEvent,
        Voted: VotedEvent,
        ProposalExecuted: ProposalExecutedEvent,
        MemberAdded: MemberAddedEvent,
        MemberRemoved: MemberRemovedEvent
    }

    #[derive(Drop, Serde)]
    struct ProposalCreatedEvent {
        proposal_id: ProposalId,
        proposer: ContractAddress,
        description: felt252,
        start_block: u64,
        end_block: u64
    }

    #[derive(Drop, Serde)]
    struct VotedEvent {
        proposal_id: ProposalId,
        voter: ContractAddress,
        support: bool
    }

    #[derive(Drop, Serde)]
    struct ProposalExecutedEvent {
        proposal_id: ProposalId
    }

    #[derive(Drop, Serde)]
    struct MemberAddedEvent {
        member: ContractAddress,
        voting_power: u256
    }

    #[derive(Drop, Serde)]
    struct MemberRemovedEvent {
        member: ContractAddress
    }

    #[abi(embed_v0)]
    impl IDAOImpl of IDAO<ContractState> {
        fn create_proposal(ref self: ContractState, description: felt252) {
            let caller: ContractAddress = get_caller_address();
            let member: Member = self.members.read(caller);

            assert!(member.voting_power > Zero::zero(), "Caller is not a member");

            let proposal_id = ProposalId { id: self.next_proposal_id.read() };
            let start_block = get_block_number();
            let end_block = start_block + 100; // Voting period: 100 blocks

            self.proposals.write(proposal_id, Proposal {
                proposer: caller,
                description,
                for_votes: Zero::zero(),
                against_votes: Zero::zero(),
                start_block,
                end_block,
                executed: false
            });

            self.next_proposal_id.write(self.next_proposal_id.read() + 1);

            self.emit(ProposalCreatedEvent {
                proposal_id,
                proposer: caller,
                description,
                start_block,
                end_block
            });
        }

        fn vote(ref self: ContractState, proposal_id: ProposalId, support: bool) {
            let caller: ContractAddress = get_caller_address();
            let member: Member = self.members.read(caller);
            let mut proposal: Proposal = self.proposals.read(proposal_id);

            assert!(get_block_number() < proposal.end_block, "Voting period has ended");
            assert!(!proposal.executed, "Proposal already executed");

            if support {
                proposal.for_votes += member.voting_power;
            } else {
                proposal.against_votes += member.voting_power;
            }

            self.proposals.write(proposal_id, proposal);

            self.emit(VotedEvent {
                proposal_id,
                voter: caller,
                support
            });
        }

        fn execute_proposal(ref self: ContractState, proposal_id: ProposalId) {
            let proposal: Proposal = self.proposals.read(proposal_id);

            assert!(get_block_number() > proposal.end_block, "Voting period has not ended");
            assert!(!proposal.executed, "Proposal already executed");
            assert!(proposal.for_votes > proposal.against_votes, "Proposal did not pass");

            // Execute the proposal (e.g., transfer funds, update state, etc.)
            // Placeholder for proposal execution logic

            self.proposals.write(proposal_id, Proposal { executed: true, ..proposal });

            self.emit(ProposalExecutedEvent { proposal_id });
        }

        fn add_member(ref self: ContractState, member: ContractAddress, voting_power: u256) {
            let caller: ContractAddress = get_caller_address();
            assert!(caller == self.admin.read(), "Only admin can add members");

            self.members.write(member, Member { address: member, voting_power });

            self.emit(MemberAddedEvent { member, voting_power });
        }

        fn remove_member(ref self: ContractState, member: ContractAddress) {
            let caller: ContractAddress = get_caller_address();
            assert!(caller == self.admin.read(), "Only admin can remove members");

            self.members.write(member, Member { address: member, voting_power: Zero::zero() });

            self.emit(MemberRemovedEvent { member });
        }

        fn get_proposal(self: @ContractState, proposal_id: ProposalId) -> Proposal {
            self.proposals.read(proposal_id)
        }

        fn get_member(self: @ContractState, member: ContractAddress) -> Member {
            self.members.read(member)
        }
    }
}