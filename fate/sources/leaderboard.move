module fate::leaderboard {
    use std::signer;
    use std::vector;
    use moveos_std::table::Table;
    use fate::admin::AdminCap;
    use fate::fate::{FATE, burn_coin, get_treasury, mint_coin};
    use moveos_std::object::Object;
    use moveos_std::account;
    use moveos_std::table;
    use moveos_std::timestamp;
    use rooch_framework::account_coin_store;

    const E_LEADERBOARD_NOT_ALIVE: u64 = 101;           // "Leaderboard is not active"
    const E_INVALID_INPUT_LENGTH: u64 = 102;            // "Input vectors length mismatch or exceed limit"
    const E_INVALID_TIMESTAMP: u64 = 103;               // "Invalid timestamp: snapshot interval not met or past end time"
    const E_INVALID_END_TIME: u64 = 104;                // "End time must be in the future"
    const E_LEVEL_NOT_FOUND: u64 = 105;                 // "Specified level not found in configs"
    const E_TIER_NOT_FOUND: u64 = 106;                  // "Specified tier not found in rank_tiers"
    const E_USER_ALREADY_EXISTS: u64 = 107;             // "User NFT already exists"
    const E_NFT_EXPIRED: u64 = 108;                     // "NFT has expired"
    const E_TOP_TIER_NOT_FOUND: u64 = 109;              // "Top reward tier not found"

    struct Leaderboard has key {
        rankings: Table<address, u256>,
        level_configs: Table<u64, LevelConfig>,
        rank_tiers: Table<u64, RankTier>,
        top_reward_tiers: Table<u64, TopRewardTier>, // Top 100 reward tiers
        last_snapshot: u64,
        end_time: u64,
        alive: bool,
        total_burned: u256,
        reward_pool: u256
    }

    struct RankTier has store {
        min_rank: u64,
        max_rank: u64,
        level: u64
    }

    struct TopRewardTier has store {
        rank: u64,
        reward_percent: u64
    }

    struct LevelConfig has store {
        level: u64,
        checkin_bonus: u64,
        market_discount: u64,
        free_tarot: u64,
        stake_weight: u64
    }

    struct UserNft has key {
        owner: address,
        level: u64,
        checkin_bonus: u64,
        market_discount: u64,
        free_tarot: u64,
        stake_weight: u64,
        burn_amount: u256,
        end_time: u64
    }

    fun init(admin: &signer) {
        let now = timestamp::now_seconds();
        let leaderboard = Leaderboard {
            rankings: table::new(),
            level_configs: table::new(),
            rank_tiers: table::new(),
            top_reward_tiers: table::new(),
            last_snapshot: now,
            end_time: now + 30 * 24 * 60 * 60,
            alive: true,
            total_burned: 0,
            reward_pool: 0
        };
        // Level configs
        table::add(&mut leaderboard.level_configs, 1, LevelConfig { level: 1, checkin_bonus: 5, market_discount: 0, free_tarot: 0, stake_weight: 0 });
        table::add(&mut leaderboard.level_configs, 2, LevelConfig { level: 2, checkin_bonus: 10, market_discount: 10, free_tarot: 0, stake_weight: 0 });
        table::add(&mut leaderboard.level_configs, 3, LevelConfig { level: 3, checkin_bonus: 15, market_discount: 15, free_tarot: 1, stake_weight: 0 });
        table::add(&mut leaderboard.level_configs, 4, LevelConfig { level: 4, checkin_bonus: 20, market_discount: 20, free_tarot: 2, stake_weight: 0 });
        table::add(&mut leaderboard.level_configs, 5, LevelConfig { level: 5, checkin_bonus: 25, market_discount: 25, free_tarot: 2, stake_weight: 10 });
        table::add(&mut leaderboard.level_configs, 6, LevelConfig { level: 6, checkin_bonus: 30, market_discount: 30, free_tarot: 2, stake_weight: 20 });
        table::add(&mut leaderboard.level_configs, 7, LevelConfig { level: 7, checkin_bonus: 40, market_discount: 40, free_tarot: 2, stake_weight: 30 });
        // Rank tiers (levels only)
        table::add(&mut leaderboard.rank_tiers, 1, RankTier { min_rank: 1, max_rank: 10, level: 7 });
        table::add(&mut leaderboard.rank_tiers, 2, RankTier { min_rank: 11, max_rank: 50, level: 6 });
        table::add(&mut leaderboard.rank_tiers, 3, RankTier { min_rank: 51, max_rank: 100, level: 5 });
        table::add(&mut leaderboard.rank_tiers, 4, RankTier { min_rank: 101, max_rank: 200, level: 4 });
        table::add(&mut leaderboard.rank_tiers, 5, RankTier { min_rank: 201, max_rank: 500, level: 3 });
        table::add(&mut leaderboard.rank_tiers, 6, RankTier { min_rank: 501, max_rank: 1000, level: 2 });
        table::add(&mut leaderboard.rank_tiers, 7, RankTier { min_rank: 1001, max_rank: 0xFFFFFFFFFFFFFFFF, level: 1 });
        // Top reward tiers (top 100)
        table::add(&mut leaderboard.top_reward_tiers, 1, TopRewardTier { rank: 1, reward_percent: 10 });
        table::add(&mut leaderboard.top_reward_tiers, 2, TopRewardTier { rank: 2, reward_percent: 5 });
        table::add(&mut leaderboard.top_reward_tiers, 3, TopRewardTier { rank: 3, reward_percent: 4 });
        let i = 4;
        while (i <= 10) {
            table::add(&mut leaderboard.top_reward_tiers, i, TopRewardTier { rank: i, reward_percent: 3 });
            i = i + 1;
        };
        while (i <= 20) {
            table::add(&mut leaderboard.top_reward_tiers, i, TopRewardTier { rank: i, reward_percent: 2 });
            i = i + 1;
        };
        while (i <= 50) {
            table::add(&mut leaderboard.top_reward_tiers, i, TopRewardTier { rank: i, reward_percent: 1 });
            i = i + 1;
        };
        while (i <= 100) {
            table::add(&mut leaderboard.top_reward_tiers, i, TopRewardTier { rank: i, reward_percent: 2 }); // 0.2% as 2 in u64 (scaled later)
            i = i + 1;
        };
        account::move_resource_to(admin, leaderboard);
    }

    fun mint_usernft(user: &signer) {
        let user_addr = signer::address_of(user);
        assert!(!account::exists_resource<UserNft>(user_addr), E_USER_ALREADY_EXISTS);
        let leaderboard = account::borrow_resource<Leaderboard>(@fate);
        account::move_resource_to(user, UserNft {
            owner: user_addr,
            level: 0,
            checkin_bonus: 0,
            market_discount: 0,
            free_tarot: 0,
            stake_weight: 0,
            burn_amount: 0,
            end_time: leaderboard.end_time
        });
    }

    public entry fun burn_fate(user: &signer, amount: u256) {
        let sender = signer::address_of(user);
        if (!account::exists_resource<UserNft>(sender)) {
            mint_usernft(user);
        };
        let coin = account_coin_store::withdraw<FATE>(user, amount * 1000000);
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        assert!(leaderboard.alive, E_LEADERBOARD_NOT_ALIVE);
        let reward_amount = amount * 10 / 100; // 10% to reward pool
        leaderboard.total_burned = leaderboard.total_burned + amount;
        leaderboard.reward_pool = leaderboard.reward_pool + reward_amount;
        burn_coin(get_treasury(), coin);
        let usernft = account::borrow_mut_resource<UserNft>(sender);
        let current_amount = if (table::contains(&leaderboard.rankings, sender)) {
            *table::borrow(&leaderboard.rankings, sender)
        } else 0;
        table::upsert(&mut leaderboard.rankings, sender, current_amount + amount);
        usernft.burn_amount = usernft.burn_amount + amount;
    }

    public entry fun snapshot_top_tiers(_: &mut Object<AdminCap>, top_users: vector<address>, top_ranks: vector<u64>) {
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        assert!(leaderboard.alive, E_LEADERBOARD_NOT_ALIVE);
        assert!(vector::length(&top_users) == vector::length(&top_ranks) && vector::length(&top_users) <= 1000, E_INVALID_INPUT_LENGTH);
        let now = timestamp::now_seconds();
        assert!(now - leaderboard.last_snapshot >= 24 * 60 * 60 && now <= leaderboard.end_time, E_INVALID_TIMESTAMP);

        let treasury = object::borrow_mut(get_treasury());
        let i = 0;
        while (i < vector::length(&top_users)) {
            let user = *vector::borrow(&top_users, i);
            let rank = *vector::borrow(&top_ranks, i);
            if (!account::exists_resource<UserNft>(user)) {
                mint_usernft(&signer::create_signer(user));
            };
            let level = get_level_from_rank(leaderboard, rank);
            let config = table::borrow(&leaderboard.level_configs, level);
            let reward = if (rank <= 100) {
                let tier = table::borrow(&leaderboard.top_reward_tiers, rank);
                if (rank > 50) {
                    leaderboard.reward_pool * tier.reward_percent / 1000 // Scale 0.2% (stored as 2)
                } else {
                    leaderboard.reward_pool * tier.reward_percent / 100
                }
            } else 0;
            update_nft(user, config, leaderboard.end_time);
            if (reward > 0) {
                let reward_coin = mint_coin(treasury, reward);
                account_coin_store::deposit(user, reward_coin);
            };
            i = i + 1;
        };

        if (now >= leaderboard.end_time - 24 * 60 * 60) {
            leaderboard.reward_pool = leaderboard.total_burned * 10 / 100;
            leaderboard.total_burned = 0;
            leaderboard.end_time = now + 30 * 24 * 60 * 60;
        };
    }

    public entry fun snapshot_others(_: &mut Object<AdminCap>, other_users: vector<address>) {
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        assert!(leaderboard.alive, E_LEADERBOARD_NOT_ALIVE);
        let now = timestamp::now_seconds();
        assert!(now - leaderboard.last_snapshot >= 24 * 60 * 60 && now <= leaderboard.end_time, E_INVALID_TIMESTAMP);

        let config_lv1 = table::borrow(&leaderboard.level_configs, 1);
        let j = 0;
        while (j < vector::length(&other_users)) {
            let user = *vector::borrow(&other_users, j);
            if (!account::exists_resource<UserNft>(user)) {
                mint_usernft(&signer::create_signer(user));
            };
            update_nft(user, config_lv1, leaderboard.end_time);
            j = j + 1;
        };

        if (now >= leaderboard.end_time - 24 * 60 * 60) {
            leaderboard.reward_pool = leaderboard.total_burned * 10 / 100;
            leaderboard.total_burned = 0;
            leaderboard.end_time = now + 30 * 24 * 60 * 60;
        };
    }

    fun get_level_from_rank(leaderboard: &Leaderboard, rank: u64): u64 {
        let i = 1;
        while (i <= 7) {
            let tier = table::borrow(&leaderboard.rank_tiers, i);
            if (rank >= tier.min_rank && (rank <= tier.max_rank || tier.max_rank == 0xFFFFFFFFFFFFFFFF)) {
                return tier.level
            };
            i = i + 1;
        };
        1
    }

    fun update_nft(user: address, config: &LevelConfig, end_time: u64) {
        let nft = account::borrow_mut_resource<UserNft>(user);
        nft.level = config.level;
        nft.checkin_bonus = config.checkin_bonus;
        nft.market_discount = config.market_discount;
        nft.free_tarot = config.free_tarot;
        nft.stake_weight = config.stake_weight;
        nft.end_time = end_time;
    }

    public entry fun update_level_config(_: &mut Object<AdminCap>, level: u64, checkin_bonus: u64, market_discount: u64, free_tarot: u64, stake_weight: u64) {
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        assert!(table::contains(&leaderboard.level_configs, level), E_LEVEL_NOT_FOUND);
        let config = table::borrow_mut(&mut leaderboard.level_configs, level);
        config.checkin_bonus = checkin_bonus;
        config.market_discount = market_discount;
        config.free_tarot = free_tarot;
        config.stake_weight = stake_weight;
    }

    public entry fun update_rank_tier(_: &mut Object<AdminCap>, tier_id: u64, min_rank: u64, max_rank: u64, level: u64) {
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        assert!(table::contains(&leaderboard.rank_tiers, tier_id), E_TIER_NOT_FOUND);
        let tier = table::borrow_mut(&mut leaderboard.rank_tiers, tier_id);
        tier.min_rank = min_rank;
        tier.max_rank = max_rank;
        tier.level = level;
    }

    public entry fun update_top_reward_tier(_: &mut Object<AdminCap>, rank: u64, reward_percent: u64) {
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        assert!(rank <= 100, E_TIER_NOT_FOUND);
        assert!(table::contains(&leaderboard.top_reward_tiers, rank), E_TOP_TIER_NOT_FOUND);
        let tier = table::borrow_mut(&mut leaderboard.top_reward_tiers, rank);
        tier.reward_percent = reward_percent;
    }

    public entry fun set_leaderboard_endtime(_: &mut Object<AdminCap>, end_time: u64) {
        let leaderboard = account::borrow_mut_resource<Leaderboard>(@fate);
        let now = timestamp::now_seconds();
        assert!(end_time > now, E_INVALID_END_TIME);
        leaderboard.last_snapshot = now;
        leaderboard.end_time = end_time;
        leaderboard.alive = true;
    }
}