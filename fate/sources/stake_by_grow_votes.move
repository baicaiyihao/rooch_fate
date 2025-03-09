module fate::stake_by_grow_votes_v5 {
    use std::signer;
    use std::string::{Self, String};
    use fate::admin::AdminCap;
    use moveos_std::object::{Self, Object};
    use moveos_std::account;
    use moveos_std::timestamp;
    use moveos_std::event::emit;
    use moveos_std::table::{Self, Table};
    use rooch_framework::account_coin_store;
    use grow_bitcoin::grow_information_v3::{Self, GrowProjectList};
    use fate::fate::{Self, mint_coin};
    use fate::user_nft::{check_user_nft, query_user_nft};

    const ErrorNotAlive: u64 = 1;
    const ErrorNotStaked: u64 = 3;
    const ErrorZeroVotes: u64 = 4;
    const ErrorMiningEnded: u64 = 5;
    const ErrorInvalidParams: u64 = 6;
    const ErrorMiningNotEnded: u64 = 7;
    const ErrorDivideByZero: u64 = 8;
    const ErrorTimestampInvalid: u64 = 9;
    const ErrorHarvestIndexInvalid: u64 = 10;
    const ErrorBeforeStartTime: u64 = 11;

    const EXP_SCALE: u128 = 1000000000000000000; // 10^18

    struct Exp has copy, store, drop {
        mantissa: u128
    }

    fun exp_direct(num: u128): Exp {
        Exp { mantissa: num }
    }

    fun exp_direct_expand(num: u128): Exp {
        Exp { mantissa: mul_u128(num, EXP_SCALE) }
    }

    fun mantissa(a: Exp): u128 {
        a.mantissa
    }

    fun add_exp(a: Exp, b: Exp): Exp {
        Exp { mantissa: a.mantissa + b.mantissa }
    }

    fun exp(num: u128, denom: u128): Exp {
        let scaledNumerator = mul_u128(num, EXP_SCALE);
        let rational = div_u128(scaledNumerator, denom);
        Exp { mantissa: rational }
    }

    fun add_u128(a: u128, b: u128): u128 {
        a + b
    }

    fun sub_u128(a: u128, b: u128): u128 {
        a - b
    }

    fun mul_u128(a: u128, b: u128): u128 {
        if (a == 0 || b == 0) { return 0 };
        a * b
    }

    fun div_u128(a: u128, b: u128): u128 {
        if (b == 0) { abort ErrorDivideByZero };
        if (a == 0) { return 0 };
        a / b
    }

    fun truncate(exp: Exp): u128 {
        exp.mantissa / EXP_SCALE
    }

    struct StakePool has key {
        total_staked_votes: u256,
        last_update_timestamp: u64,
        start_time: u64,
        end_time: u64,
        total_fate_supply: u256,
        total_mined_fate: u256,
        release_per_second: u128,
        harvest_index: u128,
        alive: bool,
        stake_records: Table<address, StakeRecord>,
    }

    struct StakeRecord has key, store {
        user: address,
        fate_grow_votes: u256,
        stake_grow_votes: u256,
        last_harvest_timestamp: u64,
        accumulated_fate: u128,
        last_harvest_index: u128,
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
        harvest_index: u128,
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
            total_mined_fate: 0u256,
            release_per_second: 0,
            harvest_index: 0,
            alive: false,
            stake_records: table::new(),
        });
        account::move_resource_to(admin, Projectname {
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
        assert!(new_total_fate_supply > 0, ErrorInvalidParams);
        assert!(new_end_time > new_start_time, ErrorInvalidParams);

        stake_pool.total_fate_supply = new_total_fate_supply;
        stake_pool.start_time = new_start_time;
        stake_pool.end_time = new_end_time;

        let duration_seconds = ((new_end_time - new_start_time) as u128);
        assert!(duration_seconds > 0, ErrorInvalidParams);
        let total_fate_supply_u128 = (new_total_fate_supply as u128);

        stake_pool.release_per_second = total_fate_supply_u128 / duration_seconds;
        stake_pool.alive = true;
        stake_pool.last_update_timestamp = now_seconds;
        stake_pool.total_staked_votes = 0u256;
        stake_pool.total_mined_fate = 0u256;
        stake_pool.harvest_index = 0;
    }

    public entry fun set_project_name(
        _: &mut Object<AdminCap>,
        new_name: String
    ) {
        let project_name = account::borrow_mut_resource<Projectname>(@fate);
        project_name.name = new_name;
    }

    public entry fun update_grow_votes(
        user: &signer,
        grow_project_list_obj: &Object<GrowProjectList>,
    ) {
        let sender = signer::address_of(user);
        let stake_pool = account::borrow_mut_resource<StakePool>(@fate);

        if (!table::contains(&stake_pool.stake_records, sender)) {
            table::add(&mut stake_pool.stake_records, sender, StakeRecord {
                user: sender,
                fate_grow_votes: 0,
                stake_grow_votes: 0,
                last_harvest_timestamp: timestamp::now_seconds(),
                accumulated_fate: 0,
                last_harvest_index: 0,
            });
        };

        let project_name = account::borrow_resource<Projectname>(@fate);
        let name = project_name.name;
        let total_votes = grow_information_v3::get_vote(grow_project_list_obj, sender, name);
        let stake_record = table::borrow_mut(&mut stake_pool.stake_records, sender);
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
        assert!(now_seconds >= stake_pool.start_time, ErrorBeforeStartTime);
        assert!(now_seconds < stake_pool.end_time, ErrorMiningEnded);

        let stake_record = if (!table::contains(&stake_pool.stake_records, sender)) {
            table::add(&mut stake_pool.stake_records, sender, StakeRecord {
                user: sender,
                fate_grow_votes: 0,
                stake_grow_votes: 0,
                last_harvest_timestamp: now_seconds,
                accumulated_fate: 0,
                last_harvest_index: stake_pool.harvest_index,
            });
            table::borrow_mut(&mut stake_pool.stake_records, sender)
        } else {
            table::borrow_mut(&mut stake_pool.stake_records, sender)
        };
        assert!(stake_record.fate_grow_votes > 0, ErrorZeroVotes);

        let votes_to_stake = stake_record.fate_grow_votes;

        if (stake_pool.total_staked_votes <= 0) {
            let time_period = now_seconds - stake_pool.last_update_timestamp;
            stake_record.accumulated_fate = stake_pool.release_per_second * (time_period as u128);
            stake_record.last_harvest_index = 0;
            stake_record.stake_grow_votes = votes_to_stake;
            stake_record.fate_grow_votes = 0;
            stake_pool.harvest_index = 0;
            stake_pool.total_staked_votes = votes_to_stake;
        } else {
            let new_harvest_index = calculate_harvest_index(
                stake_pool.total_staked_votes,
                stake_pool.last_update_timestamp,
                stake_pool.start_time,
                stake_pool.release_per_second,
                stake_pool.harvest_index,
                now_seconds
            );
            if (stake_record.stake_grow_votes == 0) {
                stake_record.stake_grow_votes = votes_to_stake;
                stake_record.fate_grow_votes = 0;
                stake_record.last_harvest_index = new_harvest_index;
            } else {
                let period_gain = calculate_withdraw_amount(
                    new_harvest_index,
                    stake_record.last_harvest_index,
                    (stake_record.stake_grow_votes as u128)
                );
                stake_record.accumulated_fate = stake_record.accumulated_fate + period_gain;
                stake_record.stake_grow_votes = stake_record.stake_grow_votes + votes_to_stake;
                stake_record.fate_grow_votes = 0;
                stake_record.last_harvest_index = new_harvest_index;
            };
            stake_pool.total_staked_votes = stake_pool.total_staked_votes + votes_to_stake;
            stake_pool.harvest_index = new_harvest_index;
        };

        stake_record.last_harvest_timestamp = now_seconds;
        stake_pool.last_update_timestamp = now_seconds;

        emit(StakeEvent {
            user: sender,
            stake_grow_votes: votes_to_stake,
            total_staked_votes: stake_pool.total_staked_votes,
            harvest_index: stake_pool.harvest_index,
            timestamp: now_seconds
        });
    }

    // 新增方法：计算包含 NFT 加成的收益
    fun calculate_gain_with_nft_boost(user: address, period_gain: u128): u128 {
        if (check_user_nft(user)) {
            let (_, _, stake_weight, _) = query_user_nft(user);
            period_gain * (100 + (stake_weight as u128)) / 100
        } else {
            period_gain
        }
    }

    public entry fun harvest(user: &signer) {
        let sender = signer::address_of(user);
        let stake_pool = account::borrow_mut_resource<StakePool>(@fate);
        let now_seconds = timestamp::now_seconds();
        let effective_time = if (now_seconds > stake_pool.end_time) { stake_pool.end_time } else { now_seconds };
        assert!(effective_time >= stake_pool.start_time, ErrorBeforeStartTime);
        let new_harvest_index = calculate_harvest_index(
            stake_pool.total_staked_votes,
            stake_pool.last_update_timestamp,
            stake_pool.start_time,
            stake_pool.release_per_second,
            stake_pool.harvest_index,
            effective_time
        );
        assert!(stake_pool.alive, ErrorNotAlive);
        let stake_record = table::borrow_mut(&mut stake_pool.stake_records, sender);
        assert!(stake_record.stake_grow_votes > 0, ErrorNotStaked);

        let period_gain = calculate_withdraw_amount(
            new_harvest_index,
            stake_record.last_harvest_index,
            (stake_record.stake_grow_votes as u128)
        );
        let boosted_gain = calculate_gain_with_nft_boost(sender, period_gain);
        stake_record.accumulated_fate = stake_record.accumulated_fate + boosted_gain;

        let total_fate = stake_record.accumulated_fate;
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
        stake_record.last_harvest_index = new_harvest_index;
        stake_record.last_harvest_timestamp = effective_time;

        stake_pool.harvest_index = new_harvest_index;
        stake_pool.last_update_timestamp = effective_time;
    }

    public entry fun unstake(user: &signer) {
        let sender = signer::address_of(user);
        let stake_pool = account::borrow_mut_resource<StakePool>(@fate);
        let now_seconds = timestamp::now_seconds();
        let effective_time = if (now_seconds > stake_pool.end_time) { stake_pool.end_time } else { now_seconds };
        assert!(effective_time >= stake_pool.start_time, ErrorBeforeStartTime);

        let new_harvest_index = calculate_harvest_index(
            stake_pool.total_staked_votes,
            stake_pool.last_update_timestamp,
            stake_pool.start_time,
            stake_pool.release_per_second,
            stake_pool.harvest_index,
            effective_time
        );
        assert!(stake_pool.alive, ErrorNotAlive);

        let StakeRecord { user: _, fate_grow_votes, stake_grow_votes, last_harvest_timestamp: _, accumulated_fate, last_harvest_index } =
            table::remove(&mut stake_pool.stake_records, sender);
        assert!(stake_grow_votes > 0, ErrorNotStaked);

        let period_gain = calculate_withdraw_amount(
            new_harvest_index,
            last_harvest_index,
            (stake_grow_votes as u128)
        );
        let boosted_gain = calculate_gain_with_nft_boost(sender, period_gain);
        let total_fate = accumulated_fate + boosted_gain;

        let remaining_fate = stake_pool.total_fate_supply - stake_pool.total_mined_fate;
        let remaining_fate_u128 = (remaining_fate as u128);
        let fate_to_mint = if (total_fate > remaining_fate_u128) { remaining_fate_u128 } else { total_fate };
        if (fate_to_mint > 0) {
            let treasury_obj = fate::get_treasury();
            let treasury = object::borrow_mut(treasury_obj);
            let fate_coin = mint_coin(treasury, (fate_to_mint as u256));
            account_coin_store::deposit(sender, fate_coin);
            stake_pool.total_mined_fate = stake_pool.total_mined_fate + (fate_to_mint as u256);
        };

        stake_pool.total_staked_votes = stake_pool.total_staked_votes - stake_grow_votes;
        emit(UnstakeEvent {
            user: sender,
            stake_grow_votes,
            total_fate_grow_votes: fate_grow_votes + stake_grow_votes,
            fate_amount: fate_to_mint,
            timestamp: effective_time,
        });

        stake_pool.harvest_index = new_harvest_index;
        stake_pool.last_update_timestamp = effective_time;
    }

    fun calculate_harvest_index(
        total_staked_votes: u256,
        last_update_timestamp: u64,
        start_time: u64,
        release_per_second: u128,
        harvest_index: u128,
        now_seconds: u64
    ): u128 {
        if (total_staked_votes == 0 || now_seconds < start_time || now_seconds <= last_update_timestamp) {
            return harvest_index
        };
        assert!(total_staked_votes > 0, ErrorDivideByZero);
        assert!(now_seconds >= last_update_timestamp, ErrorTimestampInvalid);

        let time_period = now_seconds - last_update_timestamp;
        let numr = release_per_second * (time_period as u128);
        let denom = (total_staked_votes as u128);
        harvest_index + mantissa(exp(numr, denom))
    }

    fun calculate_withdraw_amount(harvest_index: u128, last_harvest_index: u128, stake_weight: u128): u128 {
        assert!(harvest_index >= last_harvest_index, ErrorHarvestIndexInvalid);
        let amount = stake_weight * (harvest_index - last_harvest_index);
        truncate(exp_direct(amount))
    }

    fun calculate_fate_rewards(stake_pool: &StakePool, stake_record: &StakeRecord, user: address, harvest_index: u128): u128 {
        if (stake_record.stake_grow_votes == 0 || stake_pool.total_staked_votes == 0) {
            return 0
        };
        let user_gain = calculate_withdraw_amount(
            harvest_index,
            stake_record.last_harvest_index,
            (stake_record.stake_grow_votes as u128)
        );
        calculate_gain_with_nft_boost(user, user_gain)
    }

    #[view]
    public fun query_stake_info(user: address): (address, u256, u256, u64, u128) {
        let stake_pool = account::borrow_resource<StakePool>(@fate);
        if (!table::contains(&stake_pool.stake_records, user)) {
            return (user, 0, 0, 0, 0)
        };
        let stake_record = table::borrow(&stake_pool.stake_records, user);
        let now_seconds = timestamp::now_seconds();
        let effective_time = if (now_seconds > stake_pool.end_time) { stake_pool.end_time } else { now_seconds };
        let new_harvest_index = calculate_harvest_index(
            stake_pool.total_staked_votes,
            stake_pool.last_update_timestamp,
            stake_pool.start_time,
            stake_pool.release_per_second,
            stake_pool.harvest_index,
            effective_time
        );
        let total_fate = stake_record.accumulated_fate + calculate_fate_rewards(stake_pool, stake_record, user, new_harvest_index);
        (
            stake_record.user,
            stake_record.fate_grow_votes,
            stake_record.stake_grow_votes,
            stake_record.last_harvest_timestamp,
            total_fate
        )
    }

    #[view]
    public fun query_pool_info(): (u256, u64, u64, u64, u256, u256, u128, u128, bool) {
        let stake_pool = account::borrow_resource<StakePool>(@fate);
        (
            stake_pool.total_staked_votes,
            stake_pool.last_update_timestamp,
            stake_pool.start_time,
            stake_pool.end_time,
            stake_pool.total_fate_supply,
            stake_pool.total_mined_fate,
            stake_pool.release_per_second,
            stake_pool.harvest_index,
            stake_pool.alive
        )
    }

    public fun query_pool_info_view(): &StakePool {
        let stake_pool = account::borrow_resource<StakePool>(@fate);
        stake_pool
    }

    #[view]
    public fun query_stake_info_view(user: address): StakeRecordView {
        let stake_pool = account::borrow_resource<StakePool>(@fate);
        if (!table::contains(&stake_pool.stake_records, user)) {
            return StakeRecordView {
                user,
                fate_grow_votes: 0,
                stake_grow_votes: 0,
                last_harvest_timestamp: 0,
                accumulated_fate: 0
            }
        };
        let stake_record = table::borrow(&stake_pool.stake_records, user);
        let now_seconds = timestamp::now_seconds();
        let effective_time = if (now_seconds > stake_pool.end_time) { stake_pool.end_time } else { now_seconds };
        let new_harvest_index = calculate_harvest_index(
            stake_pool.total_staked_votes,
            stake_pool.last_update_timestamp,
            stake_pool.start_time,
            stake_pool.release_per_second,
            stake_pool.harvest_index,
            effective_time
        );
        let total_fate = stake_record.accumulated_fate + calculate_fate_rewards(stake_pool, stake_record, user, new_harvest_index);
        StakeRecordView {
            user: stake_record.user,
            fate_grow_votes: stake_record.fate_grow_votes,
            stake_grow_votes: stake_record.stake_grow_votes,
            last_harvest_timestamp: stake_record.last_harvest_timestamp,
            accumulated_fate: total_fate
        }
    }

    #[view]
    public fun query_project_name(): String {
        let project_name = account::borrow_resource<Projectname>(@fate);
        project_name.name
    }
}