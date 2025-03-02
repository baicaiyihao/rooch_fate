module fate::daily_check_in {
    use std::signer::address_of;
    use std::vector::{borrow, length};
    use fate::raffle::get_check_in_raffle;
    use fate::admin::AdminCap;
    use fate::utils::{is_next_day, is_same_day};
    use moveos_std::account;
    use moveos_std::object::{Self, Object};
    use moveos_std::signer;
    use moveos_std::timestamp::{Self, now_seconds};
    use rooch_framework::account_coin_store;
    use fate::fate::{get_treasury, mint_coin};
    use fate::user_nft::{check_user_nft, query_user_nft};

    const Err_ALREADY_CHECKED_IN: u64 = 101;
    const Err_CHECKED_IN_RAFFLE: u64 = 102;
    const Err_OUT_OF_CONTINUE_DAYS: u64 = 103;
    const ONE_FATE: u256 = 1000000;

    struct Config has key {
        daily_rewards: vector<u256>,
        max_continue_days: u64
    }

    struct CheckInRecord has key {
        owner: address,
        register_time: u64,
        total_sign_in_days: u64,
        last_sign_in_timestamp: u64,
        continue_days: u64,
        lottery_count: u64,
    }

    struct ConfigView has copy, drop {
        daily_rewards: vector<u256>,
        max_continue_days: u64
    }

    struct CheckInRecordView  has copy, drop {
        owner: address,
        register_time: u64,
        total_sign_in_days: u64,
        last_sign_in_timestamp: u64,
        continue_days: u64,
        lottery_count: u64,
    }


    fun init(admin: &signer) {
        let daily_rewards = vector[150, 200, 250, 300, 350, 400, 500];
        let config = Config {
            daily_rewards,
            max_continue_days: 7
        };
        account::move_resource_to(admin, config);
    }


    fun mint_profile(user: &signer) {
        if (!account::exists_resource<CheckInRecord>(address_of(user))) {
            let checkinrecord = CheckInRecord {
                owner: address_of(user),
                register_time: timestamp::now_seconds(),
                total_sign_in_days: 0,
                last_sign_in_timestamp: 0,
                continue_days: 0,
                lottery_count: 0,
            };
            account::move_resource_to(user, checkinrecord);
        }
    }

    public entry fun checkin(user: &signer) {
        mint_profile(user);
        let sender = signer::address_of(user);
        let userCheckIn = account::borrow_mut_resource<CheckInRecord>(sender);
        let config = account::borrow_mut_resource<Config>(@fate);
        let this_epoch_time = timestamp::now_seconds();
        if (userCheckIn.last_sign_in_timestamp == 0) {
            userCheckIn.last_sign_in_timestamp = this_epoch_time;
            userCheckIn.total_sign_in_days = userCheckIn.total_sign_in_days + 1;
            let treasury = object::borrow_mut(get_treasury());
            let reward = *borrow(&config.daily_rewards, userCheckIn.continue_days);
            let coin = mint_coin(treasury, reward * ONE_FATE);
            account_coin_store::deposit(sender, coin);
            userCheckIn.continue_days = userCheckIn.continue_days + 1;
        } else {
            assert!(!is_same_day(this_epoch_time, userCheckIn.last_sign_in_timestamp), Err_ALREADY_CHECKED_IN);
            check_in_rewards(userCheckIn, config, this_epoch_time, sender);
        };
    }

    public entry fun update_config(_: &mut Object<AdminCap>, update_daily_claim: vector<u256>, update_max_continue_days: u64){
        assert!(length(&update_daily_claim) >= update_max_continue_days, Err_OUT_OF_CONTINUE_DAYS);
        let config = account::borrow_mut_resource<Config>(@fate);
        config.daily_rewards = update_daily_claim;
        config.max_continue_days = update_max_continue_days;
    }

    public entry fun get_week_raffle(user: &signer){
        let sender = signer::address_of(user);
        let userCheckIn = account::borrow_mut_resource<CheckInRecord>(sender);

        assert!(userCheckIn.lottery_count > 0,Err_CHECKED_IN_RAFFLE);
        userCheckIn.lottery_count = userCheckIn.lottery_count - 1;
        get_check_in_raffle(user);
    }

    #[view]
    public fun get_check_in_record(user: address): (address, u64, u64, u64, u64, u64){
        let userCheckIn = account::borrow_resource<CheckInRecord>(user);
        (
            userCheckIn.owner,
            userCheckIn.register_time,
            userCheckIn.total_sign_in_days,
            userCheckIn.last_sign_in_timestamp,
            userCheckIn.continue_days,
            userCheckIn.lottery_count,
        )
    }

    #[view]
    public fun query_config(): (vector<u256>, u64) {
        let config = account::borrow_resource<Config>(@fate);
        (
            config.daily_rewards,
            config.max_continue_days
        )
    }

    #[view]
    public fun get_check_in_record_view(user: address): &CheckInRecord{
        let userCheckIn = account::borrow_resource<CheckInRecord>(user);
        userCheckIn
    }

    #[view]
    public fun query_config_view(): &Config {
        let config = account::borrow_resource<Config>(@fate);
        config
    }

    fun check_in_rewards(userCheckIn: &mut CheckInRecord, config: &mut Config, this_epoch_time: u64, sender: address) {
        assert!(userCheckIn.continue_days < length(&config.daily_rewards),Err_OUT_OF_CONTINUE_DAYS);
        let reward = *borrow(&config.daily_rewards, userCheckIn.continue_days);
        if (is_next_day(userCheckIn.last_sign_in_timestamp, this_epoch_time)) {
            userCheckIn.continue_days = if (userCheckIn.continue_days + 1 >= config.max_continue_days) 0 else userCheckIn.continue_days + 1;
            if (userCheckIn.continue_days == 0) {
                userCheckIn.lottery_count = userCheckIn.lottery_count + 1;
            }
        } else {
            userCheckIn.continue_days = 1;
        };
        userCheckIn.last_sign_in_timestamp = this_epoch_time;
        userCheckIn.total_sign_in_days = userCheckIn.total_sign_in_days + 1;
        let treasury = object::borrow_mut(get_treasury());
        if (check_user_nft(sender)){
            let (_,checkin_bonus, _, _, _,endtime) = query_user_nft(sender);
            if(endtime > now_seconds()){
                let boosted_share = reward * (100 + (checkin_bonus as u256)) / 100;
                let coin = mint_coin(treasury, boosted_share * ONE_FATE);
                account_coin_store::deposit(sender, coin);
            }else {
                let coin = mint_coin(treasury, reward * ONE_FATE);
                account_coin_store::deposit(sender, coin);
            }
        }else {
            let coin = mint_coin(treasury, reward * ONE_FATE);
            account_coin_store::deposit(sender, coin);
        }
    }

    #[test_only]
    public fun test_init(user: &signer) {
        init(user);
    }
}
