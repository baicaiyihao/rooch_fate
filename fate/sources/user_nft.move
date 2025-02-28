module fate::user_nft {
    use std::signer;
    use std::vector;
    use moveos_std::account;
    use moveos_std::display;
    use std::string::{utf8};

    friend fate::leaderboard;

    const E_USER_ALREADY_EXISTS: u64 = 101;    // User NFT already exists
    const E_NFT_NOT_FOUND: u64 = 102;          // No rewards available to claim

    // User NFT structure for individual data
    struct UserNft has key {
        owner: address,                         // NFT owner address
        level: u64,                             // Current level (1-7)
        checkin_bonus: u64,                     // Check-in bonus percentage
        raffle_discount: u64,                   // raffle discount percentage
        stake_weight: u64,                      // Stake weight bonus percentage
        burn_amount: u256,                      // Total FATE burned by user
        end_time: u64                           // NFT benefit expiry, synced with leaderboard cycle
    }

    fun init() {
        let keys = vector[
            utf8(b"name"),
            utf8(b"description"),
            utf8(b"image_url")
        ];
        let values = vector[
            utf8(b"FateX NFT"),
            utf8(b"FateX User NFT with level {level} benefits"),
            utf8(b"https://fatex.zone/nft/user_level_{level}.png")
        ];

        let dis = display::display<UserNft>();
        let key_len = vector::length(&keys);
        while (key_len > 0) {
            let key = vector::pop_back(&mut keys);
            let value = vector::pop_back(&mut values);
            display::set_value(dis, key, value);
            key_len = key_len - 1;
        }
    }

    // Mint a new UserNFT for a user
    public(friend) fun mint_usernft(user: &signer, time: u64) {
        let user_addr = signer::address_of(user);
        if (!account::exists_resource<UserNft>(user_addr)) {
            account::move_resource_to(user, UserNft {
                owner: user_addr,
                level: 0,
                checkin_bonus: 0,
                raffle_discount: 0,
                stake_weight: 0,
                burn_amount: 0,
                end_time: time
            });
        };
    }

    public(friend) fun set_user_nft_burn_amount(user: address, amount: u256) {
        let usernft = account::borrow_mut_resource<UserNft>(user);
        usernft.burn_amount = usernft.burn_amount + amount;
    }

    // Update user NFT with new level configuration
    public(friend) fun update_nft(
        user: address,
        level: u64,
        checkin_bonus: u64,
        raffle_discount: u64,
        stake_weight: u64,
        end_time: u64
    ) {
        let nft = account::borrow_mut_resource<UserNft>(user);
        nft.level = level;
        nft.checkin_bonus = checkin_bonus;
        nft.raffle_discount = raffle_discount;
        nft.stake_weight = stake_weight;
        nft.end_time = end_time;
    }

    // Query user NFT information
    #[view]
    public fun query_user_nft_view(user: address): &UserNft {
        assert!(account::exists_resource<UserNft>(user), E_NFT_NOT_FOUND);
        let usernft = account::borrow_resource<UserNft>(user);
        usernft
    }

    // Query user NFT information
    #[view]
    public fun query_user_nft(user: address): (u64, u64, u64, u256) {
        assert!(account::exists_resource<UserNft>(user), E_NFT_NOT_FOUND);
        let usernft = account::borrow_resource<UserNft>(user);
        (usernft.checkin_bonus, usernft.raffle_discount, usernft.stake_weight, usernft.burn_amount)
    }

    #[view]
    public fun check_user_nft(user: address): bool {
        account::exists_resource<UserNft>(user)
    }

    #[test_only]
    public fun init_for_test() {
        init();
    }
}