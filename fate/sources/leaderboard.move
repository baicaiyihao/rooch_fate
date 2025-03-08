module fate::leaderboard {
    use std::signer;
    use std::vector::{length, borrow};
    use moveos_std::timestamp::now_seconds;
    use moveos_std::table::Table;
    use fate::admin::AdminCap;
    use fate::fate::{FATE, burn_coin, get_treasury};
    use rooch_framework::gas_coin::RGas;
    use rooch_framework::coin_store::CoinStore;
    use rooch_framework::coin_store;
    use moveos_std::object::Object;
    use moveos_std::account;
    use moveos_std::object;
    use moveos_std::table;
    use moveos_std::timestamp;
    use rooch_framework::account_coin_store;
    use grow_bitcoin::grow_bitcoin::GROW;
    use fate::user_nft::{mint_usernft, query_user_nft, check_user_nft, update_nft, set_user_nft_burn_amount};
    use fate::stake_by_grow_votes::{query_pool_info, query_stake_info};

    // Error codes
    const E_LEADERBOARD_NOT_ALIVE: u64 = 101;  // Leaderboard is not active
    const E_INVALID_INPUT_LENGTH: u64 = 102;   // Input vector length mismatch or exceeds limit
    const E_INVALID_TIMESTAMP: u64 = 103;      // Invalid timestamp (snapshot interval not met or past end time)
    const E_INVALID_END_TIME: u64 = 104;       // End time must be in the future and not yet set
    const E_LEVEL_NOT_FOUND: u64 = 105;        // Specified level not found in config
    const E_TIER_NOT_FOUND: u64 = 106;         // Specified tier not found in rank_tiers
    const E_USER_ALREADY_EXISTS: u64 = 107;    // User NFT already exists
    const E_NFT_EXPIRED: u64 = 108;            // NFT has expired
    const E_INSUFFICIENT_RGAS: u64 = 110;      // Insufficient RGas balance in pool
    const E_INSUFFICIENT_GROW: u64 = 111;      // Insufficient GROW balance in pool
    const E_ALREADY_CLAIMED: u64 = 112;        // Rewards already claimed
    const E_NO_REWARDS: u64 = 113;             // No rewards available to claim
    const E_NFT_NOT_FOUND: u64 = 114;             // No rewards available to claim


    // Core leaderboard data structure
    struct Leaderboard has key {
        rankings: Table<address, u256>,         // User address -> Total FATE burned (cumulative)
        level_configs: Table<u64, LevelConfig>, // Level ID -> Level configuration (benefits)
        rank_tiers: Table<u64, RankTier>,       // Tier ID -> Rank range and corresponding level
        user_rewards: Table<address, UserRewards>, // User address -> Reward allocation info
        last_snapshot: u64,                     // Timestamp of the last snapshot
        end_time: u64,                          // End time of the current leaderboard cycle
        alive: bool,                            // Whether the leaderboard is active
        total_burned: u256,                     // Total FATE burned in the current cycle
        rgas_store: Object<CoinStore<RGas>>,    // RGas reward pool storage
        grow_store: Object<CoinStore<GROW>>     // GROW reward pool storage
    }

    // Rank tier structure for level mapping
    struct RankTier has store {
        min_rank: u64,                          // Minimum rank (inclusive)
        max_rank: u64,                          // Maximum rank (inclusive, or infinity)
        level: u64                              // Corresponding NFT level
    }

    // Level configuration structure for benefits
    struct LevelConfig has store {
        level: u64,                             // Level ID (1-7)
        checkin_bonus: u64,                     // Check-in bonus percentage
        raffle_discount: u64,                   // Market discount percentage
        stake_weight: u64                       // Stake weight bonus percentage
    }

    // User rewards structure
    struct UserRewards has store,drop {
        rgas_amount: u256,                      // RGas reward allocation
        grow_amount: u256,                      // GROW reward allocation
        is_claim: bool                          // Whether rewards have been claimed
    }

    // Initialize the leaderboard with default configurations
    fun init(admin: &signer) {
        let now = timestamp::now_seconds();
        let rgas_store = coin_store::create_coin_store<RGas>();
        let grow_store = coin_store::create_coin_store<GROW>();
        let leaderboard = Leaderboard {
            rankings: table::new(),
            level_configs: table::new(),
            rank_tiers: table::new(),
            user_rewards: table::new(),
            last_snapshot: now,
            end_time: 0,
            alive: true,
            total_burned: 0,
            rgas_store,
            grow_store
        };
        // Default level configurations (Lv1 to Lv7)
        table::add(&mut leaderboard.level_configs, 1, LevelConfig { level: 1, checkin_bonus: 5, raffle_discount: 0, stake_weight: 0 });
        table::add(&mut leaderboard.level_configs, 2, LevelConfig { level: 2, checkin_bonus: 10, raffle_discount: 10, stake_weight: 0 });
        table::add(&mut leaderboard.level_configs, 3, LevelConfig { level: 3, checkin_bonus: 15, raffle_discount: 15, stake_weight: 0 });
        table::add(&mut leaderboard.level_configs, 4, LevelConfig { level: 4, checkin_bonus: 20, raffle_discount: 20, stake_weight: 0 });
        table::add(&mut leaderboard.level_configs, 5, LevelConfig { level: 5, checkin_bonus: 25, raffle_discount: 25, stake_weight: 10 });
        table::add(&mut leaderboard.level_configs, 6, LevelConfig { level: 6, checkin_bonus: 30, raffle_discount: 30, stake_weight: 20 });
        table::add(&mut leaderboard.level_configs, 7, LevelConfig { level: 7, checkin_bonus: 40, raffle_discount: 40, stake_weight: 30 });
        // Default rank tiers (1-10: Lv7, 11-50: Lv6, etc.)
        table::add(&mut leaderboard.rank_tiers, 1, RankTier { min_rank: 1, max_rank: 10, level: 7 });
        table::add(&mut leaderboard.rank_tiers, 2, RankTier { min_rank: 11, max_rank: 50, level: 6 });
        table::add(&mut leaderboard.rank_tiers, 3, RankTier { min_rank: 51, max_rank: 100, level: 5 });
        table::add(&mut leaderboard.rank_tiers, 4, RankTier { min_rank: 101, max_rank: 200, level: 4 });
        table::add(&mut leaderboard.rank_tiers, 5, RankTier { min_rank: 201, max_rank: 500, level: 3 });
        table::add(&mut leaderboard.rank_tiers, 6, RankTier { min_rank: 501, max_rank: 1000, level: 2 });
        table::add(&mut leaderboard.rank_tiers, 7, RankTier { min_rank: 1001, max_rank: 0xFFFFFFFFFFFFFFFF, level: 1 });
        account::move_resource_to(admin, leaderboard);
    }

    // Burn FATE tokens to participate in the leaderboard
    public entry fun burn_fate(user: &signer, amount: u256) {
        let sender = signer::address_of(user);
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);

        mint_usernft(user,leaderboard.end_time);

        assert!(leaderboard.alive && (leaderboard.end_time > now_seconds()), E_LEADERBOARD_NOT_ALIVE);

        let coin = account_coin_store::withdraw<FATE>(user, amount);
        leaderboard.total_burned = leaderboard.total_burned + amount;

        let treasury = object::borrow_mut(get_treasury());
        burn_coin(treasury, coin);

        let current_amount = if (table::contains(&leaderboard.rankings, sender)) {
            *table::borrow(&leaderboard.rankings, sender)
        } else 0;

        table::upsert(&mut leaderboard.rankings, sender, current_amount + amount);

        set_user_nft_burn_amount(sender,amount);
    }

    // Snapshot top 1000 users and update their NFTs
    public entry fun snapshot_top_tiers(_: &mut Object<AdminCap>, top_users: vector<address>, top_ranks: vector<u64>,other_users: vector<address>) {
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        assert!(leaderboard.alive, E_LEADERBOARD_NOT_ALIVE);
        assert!(length(&top_users) == length(&top_ranks) && length(&top_users) <= 1000, E_INVALID_INPUT_LENGTH);
        let now = timestamp::now_seconds();
        assert!(now > leaderboard.last_snapshot && now <= leaderboard.end_time, E_INVALID_TIMESTAMP);

        let i = 0;
        while (i < length(&top_users)) {
            let user = *borrow(&top_users, i);
            let rank = *borrow(&top_ranks, i);
            let level = get_level_from_rank(leaderboard, rank);
            let config = table::borrow(&leaderboard.level_configs, level);
            update_user_nft(user, config, leaderboard.end_time);
            i = i + 1;
        };
        snapshot_others(other_users);
        leaderboard.last_snapshot = now;
    }

    // Snapshot users beyond top 1000 and set them to Level 1
    fun snapshot_others(other_users: vector<address>) {
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        let config_lv1 = table::borrow(&leaderboard.level_configs, 1);
        let j = 0;
        while (j < length(&other_users)) {
            let user = *borrow(&other_users, j);
            update_user_nft(user, config_lv1, leaderboard.end_time);
            j = j + 1;
        };
    }

    // Distribute RGas and GROW rewards after cycle ends
    public entry fun distribute_rewards(
        _: &mut Object<AdminCap>,
        users: vector<address>,
        rgas_reward_percent: u64,
        grow_reward_percent: u64,
        grow_weight: u64,
        fate_weight: u64
    ) {
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        assert!(leaderboard.alive, E_LEADERBOARD_NOT_ALIVE);
        assert!(length(&users) > 0, E_INVALID_INPUT_LENGTH);
        assert!(grow_weight + fate_weight == 100, E_INVALID_INPUT_LENGTH);
        let now = timestamp::now_seconds();
        assert!(now >= leaderboard.end_time, E_INVALID_TIMESTAMP);

        let rgas_reward_pool = coin_store::balance(&leaderboard.rgas_store) * (rgas_reward_percent as u256) / 100;
        let grow_reward_pool = coin_store::balance(&leaderboard.grow_store) * (grow_reward_percent as u256) / 100;

        calculate_and_fill_rewards(users, rgas_reward_pool, grow_reward_pool, grow_weight, fate_weight);
    }

    // Calculate and store rewards based on GROW votes and FATE burns, optimized for partial user lists
    fun calculate_and_fill_rewards(
        users: vector<address>,
        rgas_reward_pool: u256,
        grow_reward_pool: u256,
        grow_weight: u64,
        fate_weight: u64
    ) {
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        let (total_grow_votes, _, _, _, _, _, _, _, _, _) = query_pool_info();
        let total_fate_burned = leaderboard.total_burned;

        let i = 0;
        while (i < length(&users)) {
            let user = *borrow(&users, i);
            let (_, fate_grow_votes, stake_grow_votes, _, _) = query_stake_info(user);
            let user_grow_votes = fate_grow_votes + stake_grow_votes;
            let user_fate_burned = if (check_user_nft(user)) {
                let (_, _, _, burn_amount) = query_user_nft(user);
                burn_amount
            } else 0;

            // Calculate ratios with amplification to avoid precision loss
            let grow_ratio = if (total_grow_votes > 0) { (user_grow_votes * 10000) / total_grow_votes } else 0;
            let fate_ratio = if (total_fate_burned > 0) { (user_fate_burned * 10000) / total_fate_burned } else 0;

            // Weighted combined ratio
            let combined_ratio = if (grow_ratio == 0 && fate_ratio == 0) {
                0
            } else {
                (grow_ratio * (grow_weight as u256) + fate_ratio * (fate_weight as u256)) / 10000
            };

            // Directly calculate rewards based on the combined ratio
            let rgas_reward = if (combined_ratio > 0) {
                (rgas_reward_pool * combined_ratio) / 10000
            } else {
                0
            };
            let grow_reward = if (combined_ratio > 0) {
                (grow_reward_pool * combined_ratio) / 10000
            } else {
                0
            };

            // Store the rewards for the user
            table::upsert(&mut leaderboard.user_rewards, user, UserRewards {
                rgas_amount: rgas_reward,
                grow_amount: grow_reward,
                is_claim: false
            });

            i = i + 1;
        };
    }

    // Claim allocated RGas and GROW rewards
    public entry fun claim_rewards(user: &signer) {
        let sender = signer::address_of(user);
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        assert!(leaderboard.alive, E_LEADERBOARD_NOT_ALIVE);
        assert!(table::contains(&leaderboard.user_rewards, sender), E_NO_REWARDS);

        let rewards = table::borrow_mut(&mut leaderboard.user_rewards, sender);
        assert!(!rewards.is_claim, E_ALREADY_CLAIMED);

        if (rewards.rgas_amount > 0) {
            assert!(coin_store::balance(&leaderboard.rgas_store) >= rewards.rgas_amount, E_INSUFFICIENT_RGAS);
            let reward_coin = coin_store::withdraw(&mut leaderboard.rgas_store, rewards.rgas_amount);
            account_coin_store::deposit<RGas>(sender, reward_coin);
        };

        if (rewards.grow_amount > 0) {
            assert!(coin_store::balance(&leaderboard.grow_store) >= rewards.grow_amount, E_INSUFFICIENT_GROW);
            let reward_coin = coin_store::withdraw(&mut leaderboard.grow_store, rewards.grow_amount);
            account_coin_store::deposit<GROW>(sender, reward_coin);
        };

        rewards.is_claim = true;
    }

    // Admin deposits RGas into the reward pool
    public entry fun deposit_rgas_coin_from_module_address(account: &signer, amount: u256, _: &mut Object<AdminCap>) {
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        let rgas_coin = account_coin_store::withdraw<RGas>(account, amount);
        coin_store::deposit(&mut leaderboard.rgas_store, rgas_coin);
    }

    // Admin deposits GROW into the reward pool
    public entry fun deposit_grow_coin_from_module_address(account: &signer, amount: u256, _: &mut Object<AdminCap>) {
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        let grow_coin = account_coin_store::withdraw<GROW>(account, amount);
        coin_store::deposit(&mut leaderboard.grow_store, grow_coin);
    }

    // Admin deposits RGas into the reward pool
    public entry fun withdraw_rgas_coin_from_module_address(account: &signer, amount: u256, _admin: &mut Object<AdminCap>) {
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        let rgas_coin = coin_store::withdraw<RGas>(&mut leaderboard.rgas_store, amount);
        account_coin_store::deposit(signer::address_of(account), rgas_coin);
    }

    // Admin deposits GROW into the reward pool
    public entry fun withdraw_grow_coin_from_module_address(account: &signer, amount: u256, _admin: &mut Object<AdminCap>) {
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        let grow_coin = coin_store::withdraw<GROW>(&mut leaderboard.grow_store, amount);
        account_coin_store::deposit(signer::address_of(account), grow_coin);
    }

    // Get level based on rank
    fun get_level_from_rank(leaderboard: &Leaderboard, rank: u64): u64 {
        let i = 1;
        while (i <= 7) {
            let tier = table::borrow(&leaderboard.rank_tiers, i);
            if (rank >= tier.min_rank && (rank <= tier.max_rank || tier.max_rank == 0xFFFFFFFFFFFFFFFF)) {
                return tier.level
            };
            i = i + 1;
        };
        1  // Default to Level 1
    }

    // Update user NFT with new level configuration
    fun update_user_nft(user: address, config: &LevelConfig, end_time: u64) {
        update_nft(
            user,
            config.level,
            config.checkin_bonus,
            config.raffle_discount,
            config.stake_weight,
            end_time
        );
    }

    // Update level configuration (admin only)
    public entry fun update_level_config(_: &mut Object<AdminCap>, level: u64, checkin_bonus: u64, market_discount: u64, stake_weight: u64) {
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        assert!(table::contains(&leaderboard.level_configs, level), E_LEVEL_NOT_FOUND);
        let config = table::borrow_mut(&mut leaderboard.level_configs, level);
        config.checkin_bonus = checkin_bonus;
        config.raffle_discount = market_discount;
        config.stake_weight = stake_weight;
    }

    // Update rank tier configuration (admin only)
    public entry fun update_rank_tier(_: &mut Object<AdminCap>, tier_id: u64, min_rank: u64, max_rank: u64, level: u64) {
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        assert!(table::contains(&leaderboard.rank_tiers, tier_id), E_TIER_NOT_FOUND);
        let tier = table::borrow_mut(&mut leaderboard.rank_tiers, tier_id);
        tier.min_rank = min_rank;
        tier.max_rank = max_rank;
        tier.level = level;
    }

    // Set leaderboard cycle end time (admin only)
    public entry fun set_leaderboard_endtime(_: &mut Object<AdminCap>, end_time: u64) {
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        let now = timestamp::now_seconds();
        assert!(end_time > now && leaderboard.end_time == 0, E_INVALID_END_TIME);
        leaderboard.last_snapshot = now;
        leaderboard.end_time = end_time;
        leaderboard.alive = true;
    }

    // Query leaderboard information
    #[view]
    public fun query_leaderboard(): &Leaderboard {
        let leaderboard = account::borrow_resource<Leaderboard>(@fate);
        leaderboard
    }


    #[test_only]
    public fun test_init(admin: &signer) {
        init(admin);
    }

}