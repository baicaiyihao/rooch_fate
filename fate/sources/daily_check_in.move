module fate::daily_check_in {
    use std::signer::address_of;
    use std::vector;
    use fate::raffle::get_check_in_raffle;
    use fate::admin::AdminCap;
    use moveos_std::account;
    use moveos_std::object::{Self, Object};
    use moveos_std::signer;
    use moveos_std::timestamp::{Self};
    use rooch_framework::account_coin_store;
    use fate::fate::{get_treasury, mint_coin};

    const Err_ALREADY_CHECKED_IN: u64 = 101;
    const Err_CHECKED_IN_RAFFLE: u64 = 102;
    const SECONDS_PER_DAY: u64 = 24 * 60 * 60;

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
                register_time: timestamp::now_milliseconds(),
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
            userCheckIn.continue_days = userCheckIn.continue_days + 1;
            let treasury = object::borrow_mut(get_treasury());
            let reward = *vector::borrow(&config.daily_rewards, userCheckIn.continue_days);
            let coin = mint_coin(treasury, reward);
            account_coin_store::deposit(sender, coin);
        } else {
            assert!(!is_same_day(this_epoch_time, userCheckIn.last_sign_in_timestamp), Err_ALREADY_CHECKED_IN);
            check_in_rewards(userCheckIn, config, this_epoch_time, sender);
        };
    }

    public entry fun update_config(_: &mut Object<AdminCap>, update_daily_claim: vector<u256>, update_max_continue_days: u64){
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

    public fun get_continue_days(user: &signer): u64{
        let sender = signer::address_of(user);
        let userCheckIn = account::borrow_mut_resource<CheckInRecord>(sender);
        userCheckIn.continue_days
    }


    fun check_in_rewards(userCheckIn: &mut CheckInRecord, config: &mut Config, this_epoch_time: u64, sender: address) {
        let reward = *vector::borrow(&config.daily_rewards, userCheckIn.continue_days);
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
        let coin = mint_coin(treasury, reward);
        account_coin_store::deposit(sender, coin);
    }

    fun is_same_day(timestamp1: u64, timestamp2: u64): bool {
        timestamp1 / SECONDS_PER_DAY == timestamp2 / SECONDS_PER_DAY
    }

    fun is_next_day(timestamp1: u64, timestamp2: u64): bool {
        let day1 = timestamp1 / SECONDS_PER_DAY;
        let day2 = timestamp2 / SECONDS_PER_DAY;
        day2 > day1
    }

    #[test_only]
    public fun test_init(user: &signer) {
        init(user);
    }
}
