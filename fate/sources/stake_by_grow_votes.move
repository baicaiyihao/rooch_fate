module fate::stake_by_grow_votes {
    use std::signer;
    use std::signer::address_of;
    use std::string::{Self, String};
    use fate::admin::AdminCap;
    use moveos_std::object::{Self, Object};
    use moveos_std::account;
    use moveos_std::timestamp;
    use moveos_std::event::emit;
    use rooch_framework::account_coin_store;
    use grow_bitcoin::grow_information_v3::{Self, GrowProjectList};
    use fate::fate::{Self, mint_coin};
    use fate::user_nft::{check_user_nft, query_user_nft};

    const ErrorNotAlive: u64 = 1;
    const ErrorAlreadyStaked: u64 = 2;
    const ErrorNotStaked: u64 = 3;
    const ErrorZeroVotes: u64 = 4;
    const ErrorMiningEnded: u64 = 5;
    const ErrorInvalidParams: u64 = 6;
    const ErrorMiningNotEnded: u64 = 7;

    struct StakePool has key {
        total_staked_votes: u256,
        last_update_timestamp: u64,
        start_time: u64,
        end_time: u64,
        total_fate_supply: u256,
        mining_duration_seconds: u64,
        fate_per_day: u128,
        total_mined_fate: u256,
        release_per_second: u128,
        alive: bool,
    }

    struct StakeRecord has key {
        user: address,
        fate_grow_votes: u256,
        stake_grow_votes: u256,
        last_harvest_timestamp: u64,
        accumulated_fate: u128,
    }

    struct StakeRecordView has copy, drop {
        user: address,
        fate_grow_votes: u256,
        stake_grow_votes: u256,
        last_harvest_timestamp: u64,
        accumulated_fate: u128,
    }

    struct Projectname has key {
        name: String
    }

    struct StakeEvent has copy, drop {
        user: address,
        stake_grow_votes: u256,
        total_staked_votes: u256,
        timestamp: u64,
    }

    struct UnstakeEvent has copy, drop {
        user: address,
        stake_grow_votes: u256,
        total_fate_grow_votes: u256,
        fate_amount: u128,
        timestamp: u64,
    }

    struct HarvestEvent has copy, drop {
        user: address,
        fate_amount: u128,
        timestamp: u64,
    }

    struct VoteUpdateEvent has copy, drop {
        user: address,
        new_votes: u256,
        total_votes: u256,
    }

    fun init(admin: &signer) {
        let now_seconds = timestamp::now_seconds();
        account::move_resource_to(admin, StakePool {
            total_staked_votes: 0u256,
            last_update_timestamp: now_seconds,
            start_time: 0,
            end_time: 0,
            total_fate_supply: 0u256,
            mining_duration_seconds: 0,
            fate_per_day: 0,
            total_mined_fate: 0u256,
            release_per_second: 0,
            alive: false,
        });
        account::move_resource_to(admin,Projectname{
            name: string::utf8(b"goldminer"),
        });
    }

    public entry fun modify_stake_pool(
        _: &mut Object<AdminCap>,
        new_total_fate_supply: u256,
        new_start_time: u64,
        new_end_time: u64
    ) {
        let stake_pool = account::borrow_mut_resource<StakePool>(@fate);
        let now_seconds = timestamp::now_seconds();
        assert!(stake_pool.end_time == 0 || now_seconds > stake_pool.end_time, ErrorMiningNotEnded);
        assert!(new_total_fate_supply > 0u256, ErrorInvalidParams);
        assert!(new_end_time > new_start_time || (new_start_time == 0 && new_end_time == 0), ErrorInvalidParams);
        assert!(new_start_time >= now_seconds || new_start_time == 0, ErrorInvalidParams);

        stake_pool.total_fate_supply = new_total_fate_supply;
        stake_pool.start_time = new_start_time;
        stake_pool.end_time = new_end_time;

        if (new_start_time != 0 && new_end_time != 0) {
            let duration_seconds = ((new_end_time - new_start_time) as u128);
            assert!(duration_seconds > 0, ErrorInvalidParams);
            let total_fate_supply_u128 = (new_total_fate_supply as u128);

            stake_pool.mining_duration_seconds = (duration_seconds as u64);
            stake_pool.release_per_second = total_fate_supply_u128 / duration_seconds;
            stake_pool.fate_per_day = total_fate_supply_u128 / (duration_seconds / 86400u128);
            stake_pool.alive = true;
        } else {
            stake_pool.mining_duration_seconds = 0;
            stake_pool.release_per_second = 0;
            stake_pool.fate_per_day = 0;
            stake_pool.alive = false;
        };

        stake_pool.last_update_timestamp = now_seconds;
        stake_pool.total_staked_votes = 0u256;
        stake_pool.total_mined_fate = 0u256;
    }

    public entry fun set_project_name(
        _: &mut Object<AdminCap>,
        new_name: String
    ){
        let project_name = account::borrow_mut_resource<Projectname>(@fate);
        project_name.name = new_name;
    }


    public entry fun update_grow_votes(
        user: &signer,
        grow_project_list_obj: &Object<GrowProjectList>,
    ) {
        init_stake_record(user);
        let sender = signer::address_of(user);
        let project_name = account::borrow_resource<Projectname>(@fate);
        let name = project_name.name;
        let total_votes = grow_information_v3::get_vote(grow_project_list_obj, sender, name);
        let stake_record = account::borrow_mut_resource<StakeRecord>(sender);
        let already_staked = stake_record.stake_grow_votes;
        let current_unstaked = stake_record.fate_grow_votes;
        let new_votes = if (total_votes > already_staked + current_unstaked) {
            total_votes - already_staked - current_unstaked
        } else {
            0u256
        };
        stake_record.fate_grow_votes = current_unstaked + new_votes;

        emit(VoteUpdateEvent { user: sender, new_votes, total_votes });
    }

    public entry fun stake(user: &signer) {
        let sender = signer::address_of(user);
        let now_seconds = timestamp::now_seconds();
        let stake_pool = account::borrow_mut_resource<StakePool>(@fate);
        assert!(stake_pool.alive, ErrorNotAlive);
        assert!(now_seconds < stake_pool.end_time, ErrorMiningEnded);
        let stake_record = account::borrow_mut_resource<StakeRecord>(sender);
        assert!(stake_record.fate_grow_votes > 0, ErrorZeroVotes);
        let accumulated_fate = calculate_fate_rewards(stake_pool, stake_record, now_seconds,sender);
        stake_record.accumulated_fate = stake_record.accumulated_fate + accumulated_fate;
        let votes_to_stake = stake_record.fate_grow_votes;
        stake_record.stake_grow_votes = stake_record.stake_grow_votes + votes_to_stake;
        stake_record.fate_grow_votes = 0;
        stake_record.last_harvest_timestamp = now_seconds;
        stake_pool.total_staked_votes = stake_pool.total_staked_votes + votes_to_stake;
        stake_pool.last_update_timestamp = now_seconds;
        emit(StakeEvent { user: sender, stake_grow_votes: votes_to_stake, total_staked_votes: stake_record.stake_grow_votes, timestamp: now_seconds });
    }

    public entry fun unstake(user: &signer) {
        let sender = signer::address_of(user);
        let stake_pool = account::borrow_mut_resource<StakePool>(@fate);
        assert!(stake_pool.alive, ErrorNotAlive);
        let stake_record = account::borrow_mut_resource<StakeRecord>(sender);
        assert!(stake_record.stake_grow_votes > 0, ErrorNotStaked);
        let now_seconds = timestamp::now_seconds();
        let effective_time = if (now_seconds > stake_pool.end_time) { stake_pool.end_time } else { now_seconds };
        let accumulated_fate = calculate_fate_rewards(stake_pool, stake_record, effective_time,sender);
        let total_fate = stake_record.accumulated_fate + accumulated_fate;
        let remaining_fate = stake_pool.total_fate_supply - stake_pool.total_mined_fate;
        let remaining_fate_u128 = (remaining_fate as u128);
        let fate_to_mint = if (total_fate > remaining_fate_u128) { remaining_fate_u128 } else { total_fate };
        if (fate_to_mint > 0) {
            let treasury_obj = fate::get_treasury();
            let treasury = object::borrow_mut(treasury_obj);
            let fate_coin = fate::mint_coin(treasury, (fate_to_mint as u256));
            account_coin_store::deposit(sender, fate_coin);
            stake_pool.total_mined_fate = stake_pool.total_mined_fate + (fate_to_mint as u256);
        };
        stake_pool.total_staked_votes = stake_pool.total_staked_votes - stake_record.stake_grow_votes;
        stake_pool.last_update_timestamp = effective_time;
        emit(UnstakeEvent {
            user: sender,
            stake_grow_votes: stake_record.stake_grow_votes,
            total_fate_grow_votes: stake_record.fate_grow_votes + stake_record.stake_grow_votes,
            fate_amount: fate_to_mint,
            timestamp: effective_time,
        });
        stake_record.fate_grow_votes = stake_record.fate_grow_votes + stake_record.stake_grow_votes;
        stake_record.stake_grow_votes = 0;
        stake_record.accumulated_fate = 0;
        stake_record.last_harvest_timestamp = effective_time;
    }

    public entry fun harvest(user: &signer) {
        let sender = signer::address_of(user);
        let stake_pool = account::borrow_mut_resource<StakePool>(@fate);
        assert!(stake_pool.alive, ErrorNotAlive);
        let stake_record = account::borrow_mut_resource<StakeRecord>(sender);
        assert!(stake_record.stake_grow_votes > 0, ErrorNotStaked);
        let now_seconds = timestamp::now_seconds();
        let effective_time = if (now_seconds > stake_pool.end_time) { stake_pool.end_time } else { now_seconds };
        let accumulated_fate = calculate_fate_rewards(stake_pool, stake_record, effective_time,sender);
        let total_fate = stake_record.accumulated_fate + accumulated_fate;
        if (total_fate > 0) {
            let remaining_fate = stake_pool.total_fate_supply - stake_pool.total_mined_fate;
            let remaining_fate_u128 = (remaining_fate as u128);
            let fate_to_mint = if (total_fate > remaining_fate_u128) { remaining_fate_u128 } else { total_fate };
            if (fate_to_mint > 0) {
                let treasury_obj = fate::get_treasury();
                let treasury = object::borrow_mut(treasury_obj);
                let fate_coin = mint_coin(treasury, (fate_to_mint as u256));
                account_coin_store::deposit(sender, fate_coin);
                stake_pool.total_mined_fate = stake_pool.total_mined_fate + (fate_to_mint as u256);
                emit(HarvestEvent { user: sender, fate_amount: fate_to_mint, timestamp: effective_time });
            };
        };
        stake_record.accumulated_fate = 0;
        stake_record.last_harvest_timestamp = effective_time;
        stake_pool.last_update_timestamp = effective_time;
    }

    fun calculate_fate_rewards(stake_pool: &StakePool, stake_record: &StakeRecord, now_seconds: u64,user: address): u128 {
        if (stake_record.stake_grow_votes == 0 || stake_pool.total_staked_votes == 0 || now_seconds <= stake_record.last_harvest_timestamp || now_seconds < stake_pool.start_time) {
            return 0
        };
        let time_period = now_seconds - stake_record.last_harvest_timestamp;
        let total_release = stake_pool.release_per_second * (time_period as u128);
        let user_share = (stake_record.stake_grow_votes as u128) * total_release / (stake_pool.total_staked_votes as u128);

        if (check_user_nft(user)){
            let (_,_,stake_weight,_) = query_user_nft(user);
            let boosted_share = user_share * (100 + (stake_weight as u128)) / 100;
            return boosted_share
        }else {
            return user_share
        }
    }


    fun init_stake_record(user: &signer) {
        if (!account::exists_resource<StakeRecord>(address_of(user))) {
            account::move_resource_to(user, StakeRecord {
                user: address_of(user),
                fate_grow_votes: 0,
                stake_grow_votes: 0,
                last_harvest_timestamp: timestamp::now_seconds(),
                accumulated_fate: 0,
            });
        }
    }

    #[view]
    public fun query_stake_info(user: address): (address, u256, u256, u64, u128) {
        if (account::exists_resource<StakeRecord>(user)){
            let stake_pool = account::borrow_resource<StakePool>(@fate);
            let stake_record = account::borrow_resource<StakeRecord>(user);
            let now_seconds = timestamp::now_seconds();
            let effective_time = if (now_seconds > stake_pool.end_time) { stake_pool.end_time } else { now_seconds };
            let accumulated_fate = calculate_fate_rewards(stake_pool, stake_record, effective_time,user);
            let total_fate = stake_record.accumulated_fate + accumulated_fate;
            return (
                stake_record.user,
                stake_record.fate_grow_votes,
                stake_record.stake_grow_votes,
                stake_record.last_harvest_timestamp,
                total_fate
            )
        }else {
            return (user,0,0,0,0)
        }
    }

    #[view]
    public fun query_pool_info(): (u256, u64, u64, u64, u256, u64, u128, u256, u128, bool) {
        let stake_pool = account::borrow_resource<StakePool>(@fate);
        (
            stake_pool.total_staked_votes,
            stake_pool.last_update_timestamp,
            stake_pool.start_time,
            stake_pool.end_time,
            stake_pool.total_fate_supply,
            stake_pool.mining_duration_seconds,
            stake_pool.fate_per_day,
            stake_pool.total_mined_fate,
            stake_pool.release_per_second,
            stake_pool.alive
        )
    }

    #[view]
    public fun query_stake_info_view(user: address): StakeRecordView {
        let stake_pool = account::borrow_resource<StakePool>(@fate);
        let stake_record = account::borrow_resource<StakeRecord>(user);
        let now_seconds = timestamp::now_seconds();
        let effective_time = if (now_seconds > stake_pool.end_time) { stake_pool.end_time } else { now_seconds };
        let accumulated_fate = calculate_fate_rewards(stake_pool, stake_record, effective_time,user);
        let total_fate = stake_record.accumulated_fate + accumulated_fate;
        StakeRecordView{
            user: stake_record.user,
            fate_grow_votes: stake_record.fate_grow_votes,
            stake_grow_votes: stake_record.stake_grow_votes,
            last_harvest_timestamp: stake_record.last_harvest_timestamp,
            accumulated_fate: total_fate
        }
    }

    #[view]
    public fun query_pool_info_view(): &StakePool {
        let stake_pool = account::borrow_resource<StakePool>(@fate);
        stake_pool
    }

    #[view]
    public fun query_project_name(): String {
        let project_name = account::borrow_resource<Projectname>(@fate);
        project_name.name
    }

    #[test_only]
    public fun test_init(admin: &signer) {
        init(admin);
    }

    #[test_only]
    public fun create_stake_record_for_test(user: &signer, mock_votes: u256) {
        init_stake_record(user);
        test_update_grow_votes(user,mock_votes);
    }

    #[test_only]
    public fun test_set_stake_pool_start_time(stake_pool: &mut StakePool, end_time: u64) {
        stake_pool.start_time = end_time;
    }

    #[test_only]
    public fun test_set_stake_pool_end_time(stake_pool: &mut StakePool, end_time: u64) {
        stake_pool.end_time = end_time;
    }

    #[test_only]
    public fun test_set_stake_record_time(stake_record: &mut StakeRecord, end_time: u64) {
        stake_record.last_harvest_timestamp = end_time;
    }

    #[test_only]
    public fun test_stake(user: &signer, stake_pool: &mut StakePool, stake_record: &mut StakeRecord) {
        let sender = signer::address_of(user);
        let now_seconds = timestamp::now_seconds();
        assert!(stake_pool.alive, ErrorNotAlive);
        assert!(now_seconds < stake_pool.end_time, ErrorMiningEnded);
        assert!(stake_record.fate_grow_votes > 0, ErrorZeroVotes);
        let accumulated_fate = calculate_fate_rewards(stake_pool, stake_record, now_seconds,sender);
        stake_record.accumulated_fate = stake_record.accumulated_fate + accumulated_fate;
        let votes_to_stake = stake_record.fate_grow_votes;
        stake_record.stake_grow_votes = stake_record.stake_grow_votes + votes_to_stake;
        stake_record.fate_grow_votes = 0;
        stake_record.last_harvest_timestamp = now_seconds;
        stake_pool.total_staked_votes = stake_pool.total_staked_votes + votes_to_stake;
        stake_pool.last_update_timestamp = now_seconds;
        emit(StakeEvent { user: sender, stake_grow_votes: votes_to_stake, total_staked_votes: stake_record.stake_grow_votes, timestamp: now_seconds });
    }

    #[test_only]
    public fun test_query_fate_rewards(stake_pool: &mut StakePool, stake_record: &mut StakeRecord,user: address): u128 {
        let now_seconds = timestamp::now_seconds();
        let effective_time = if (now_seconds > stake_pool.end_time) { stake_pool.end_time } else { now_seconds };
        let accumulated_fate = calculate_fate_rewards(stake_pool, stake_record, effective_time,user);
        stake_record.accumulated_fate + accumulated_fate
    }

    #[test_only]
    public fun test_harvest(user: &signer, stake_pool: &mut StakePool, stake_record: &mut StakeRecord) {
        let sender = signer::address_of(user);
        let now_seconds = timestamp::now_seconds();
        assert!(stake_pool.alive, ErrorNotAlive);
        assert!(stake_record.stake_grow_votes > 0, ErrorNotStaked);
        let effective_time = if (now_seconds > stake_pool.end_time) { stake_pool.end_time } else { now_seconds };
        let accumulated_fate = calculate_fate_rewards(stake_pool, stake_record, effective_time,sender);
        let total_fate = stake_record.accumulated_fate + accumulated_fate;
        if (total_fate > 0) {
            let remaining_fate = stake_pool.total_fate_supply - stake_pool.total_mined_fate;
            let remaining_fate_u128 = (remaining_fate as u128);
            let fate_to_mint = if (total_fate > remaining_fate_u128) { remaining_fate_u128 } else { total_fate };
            if (fate_to_mint > 0) {
                let treasury_obj = fate::get_treasury();
                let treasury = object::borrow_mut(treasury_obj);
                let fate_coin = mint_coin(treasury, (fate_to_mint as u256));
                account_coin_store::deposit(sender, fate_coin);
                stake_pool.total_mined_fate = stake_pool.total_mined_fate + (fate_to_mint as u256);
                emit(HarvestEvent { user: sender, fate_amount: fate_to_mint, timestamp: effective_time });
            };
        };
        stake_record.accumulated_fate = 0;
        stake_record.last_harvest_timestamp = effective_time;
        stake_pool.last_update_timestamp = effective_time;
    }

    #[test_only]
    public fun test_unstake(user: &signer, stake_pool: &mut StakePool, stake_record: &mut StakeRecord) {
        let sender = signer::address_of(user);
        assert!(stake_pool.alive, ErrorNotAlive);
        assert!(stake_record.stake_grow_votes > 0, ErrorNotStaked);
        let now_seconds = timestamp::now_seconds();
        let effective_time = if (now_seconds > stake_pool.end_time) { stake_pool.end_time } else { now_seconds };
        let accumulated_fate = calculate_fate_rewards(stake_pool, stake_record, effective_time,sender);
        let total_fate = stake_record.accumulated_fate + accumulated_fate;
        let remaining_fate = stake_pool.total_fate_supply - stake_pool.total_mined_fate;
        let remaining_fate_u128 = (remaining_fate as u128);
        let fate_to_mint = if (total_fate > remaining_fate_u128) { remaining_fate_u128 } else { total_fate };
        if (fate_to_mint > 0) {
            let treasury_obj = fate::get_treasury();
            let treasury = object::borrow_mut(treasury_obj);
            let fate_coin = fate::mint_coin(treasury, (fate_to_mint as u256));
            account_coin_store::deposit(sender, fate_coin);
            stake_pool.total_mined_fate = stake_pool.total_mined_fate + (fate_to_mint as u256);
        };
        stake_pool.total_staked_votes = stake_pool.total_staked_votes - stake_record.stake_grow_votes;
        stake_pool.last_update_timestamp = effective_time;
        emit(UnstakeEvent {
            user: sender,
            stake_grow_votes: stake_record.stake_grow_votes,
            total_fate_grow_votes: stake_record.fate_grow_votes + stake_record.stake_grow_votes,
            fate_amount: fate_to_mint,
            timestamp: effective_time,
        });
        stake_record.fate_grow_votes = stake_record.stake_grow_votes;
        stake_record.stake_grow_votes = 0;
        stake_record.accumulated_fate = 0;
        stake_record.last_harvest_timestamp = effective_time;
    }

    #[test_only]
    public fun test_query_pool_info(user: &signer): (u256, u64, u256, u128, u64, u256, bool) {
        let stake_pool = account::borrow_resource<StakePool>(address_of(user));
        (
            stake_pool.total_staked_votes,
            stake_pool.end_time,
            stake_pool.total_fate_supply,
            stake_pool.fate_per_day,
            stake_pool.mining_duration_seconds,
            stake_pool.total_mined_fate,
            stake_pool.alive
        )
    }

    #[test_only]
    public entry fun test_update_grow_votes(
        user: &signer,
        test_total_votes: u256,
    ) {
        init_stake_record(user);
        let sender = signer::address_of(user);
        let total_votes = test_total_votes;
        let stake_record = account::borrow_mut_resource<StakeRecord>(sender);
        let already_staked = stake_record.stake_grow_votes;
        let current_unstaked = stake_record.fate_grow_votes;
        let new_votes = if (total_votes > already_staked + current_unstaked) {
            total_votes - already_staked - current_unstaked
        } else {
            0u256
        };
        stake_record.fate_grow_votes = current_unstaked + new_votes;
    }

    #[test_only]
    public fun test_query_time(): u64 {
        timestamp::now_seconds()
    }
}