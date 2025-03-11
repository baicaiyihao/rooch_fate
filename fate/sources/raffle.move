module fate::raffle {
    use std::signer;
    use moveos_std::object::Object;
    use fate::admin::AdminCap;
    use moveos_std::object;
    use moveos_std::signer::address_of;
    use moveos_std::event::emit;
    use moveos_std::account;
    use moveos_std::timestamp;
    use fate::utils::is_next_day;
    use rooch_framework::account_coin_store;
    use fate::random::get_random;
    use fate::fate::{get_treasury, mint_coin, FATE, burn_coin};
    use fate::user_nft::{check_user_nft, query_user_nft};

    friend fate::daily_check_in;

    const Err_Not_enough_raffle_times: u64 = 101;
    const Err_Daily_Raffle_Limit_Exceeded: u64 = 102;


    struct CheckInRaffle has key {
        grand_prize_duration: u256,
        second_prize_duration: u256,
        third_prize_duration: u256,
        grand_prize_weight: u256,
        second_prize_weight: u256,
        third_prize_weight: u256,
        max_raffle_count_weight: u64
    }

    struct CheckInRaffle_v1 has key {
        grand_prize_duration: u256,
        second_prize_duration: u256,
        third_prize_duration: u256,
        grand_prize_weight: u256,
        second_prize_weight: u256,
        third_prize_weight: u256,
        max_raffle_count_weight: u64,
        daily_max_raffle_count: u64,
    }


    struct CheckInRaffleRecord_v1 has key {
        user: address,
        raffle_count: u64,
        daily_raffle_count: u64,
        last_raffle_date: u64,
    }

    struct CheckInRaffleRecord has key{
        user: address,
        raffle_count: u64
    }

    struct CheckInRaffleView has copy, drop {
        grand_prize_duration: u256,
        second_prize_duration: u256,
        third_prize_duration: u256,
        grand_prize_weight: u256,
        second_prize_weight: u256,
        third_prize_weight: u256,
        max_raffle_count_weight: u64
    }

    struct CheckInRaffleRecordView has copy, drop{
        user: address,
        raffle_count: u64
    }

    struct CheckInRaffleEmit has copy, drop {
        user: address,
        result: u256,
    }

    fun init(admin: &signer){
        let checkinraffle = CheckInRaffle{
            grand_prize_duration: 1000,
            second_prize_duration: 500,
            third_prize_duration: 150,
            grand_prize_weight: 5,
            second_prize_weight: 25,
            third_prize_weight: 70,
            max_raffle_count_weight: 10
        };
        account::move_resource_to(admin, checkinraffle);


        let checkinraffle_v1 = CheckInRaffle_v1 {
            grand_prize_duration: 1000,
            second_prize_duration: 500,
            third_prize_duration: 150,
            grand_prize_weight: 5,
            second_prize_weight: 25,
            third_prize_weight: 70,
            max_raffle_count_weight: 10,
            daily_max_raffle_count: 50,
        };
        account::move_resource_to(admin, checkinraffle_v1);
    }

    fun init_check_in_raffle_record(admin: &signer){
        let caller_address = signer::address_of(admin);
        if (caller_address != @fate) {
            abort 403
        };
        if (!account::exists_resource<CheckInRaffleRecord>(address_of(admin))) {
            let checkInRaffleRecord = CheckInRaffleRecord {
                user: address_of(admin),
                raffle_count: 0
            };
            account::move_resource_to(admin, checkInRaffleRecord);
        }
    }

    fun init_check_in_raffle_record_v1(user: &signer) {
        if (!account::exists_resource<CheckInRaffleRecord_v1>(address_of(user))) {
            let checkInRaffleRecord = CheckInRaffleRecord_v1 {
                user: address_of(user),
                raffle_count: 0,
                daily_raffle_count: 0,
                last_raffle_date: 0,
            };
            account::move_resource_to(user, checkInRaffleRecord);
        }
    }

    public entry fun get_check_in_raffle_by_fate_v1(user: &signer) {
        init_check_in_raffle_record_v1(user);
        let sender = signer::address_of(user);
        let checkinraffle = account::borrow_mut_resource<CheckInRaffle_v1>(@fate);
        let checkInRaffleRecord = account::borrow_mut_resource<CheckInRaffleRecord_v1>(address_of(user));

        let current_time = timestamp::now_seconds();
        let last_date = checkInRaffleRecord.last_raffle_date;
        if (is_next_day(last_date, current_time)) {
            checkInRaffleRecord.daily_raffle_count = 0;
        };

        assert!(checkInRaffleRecord.daily_raffle_count < checkinraffle.daily_max_raffle_count, Err_Daily_Raffle_Limit_Exceeded);

        let avg_price = (checkinraffle.grand_prize_duration * checkinraffle.grand_prize_weight +
            checkinraffle.second_prize_duration * checkinraffle.second_prize_weight +
            checkinraffle.third_prize_duration * checkinraffle.third_prize_weight) / 100;

        let treasury = object::borrow_mut(get_treasury());

        if (check_user_nft(sender)) {
            let (_, raffle_discount, _, _) = query_user_nft(sender);
            let boosted_share = avg_price * (100 - (raffle_discount as u256)) / 100;
            let cost_coin = account_coin_store::withdraw<FATE>(user, boosted_share);
            burn_coin(treasury, cost_coin);
        } else {
            let cost_coin = account_coin_store::withdraw<FATE>(user, avg_price);
            burn_coin(treasury, cost_coin);
        };

        checkInRaffleRecord.raffle_count = checkInRaffleRecord.raffle_count + 1;
        checkInRaffleRecord.daily_raffle_count = checkInRaffleRecord.daily_raffle_count + 1;
        checkInRaffleRecord.last_raffle_date = current_time;
        get_check_in_raffle_v1(user);
    }

    public entry fun claim_max_raffle_v1(user: &signer) {
        let sender = address_of(user);
        let checkinraffle = account::borrow_mut_resource<CheckInRaffle_v1>(@fate);
        let checkInRaffleRecord = account::borrow_mut_resource<CheckInRaffleRecord_v1>(sender);
        assert!(checkInRaffleRecord.raffle_count >= checkinraffle.max_raffle_count_weight, Err_Not_enough_raffle_times);
        checkInRaffleRecord.raffle_count = checkInRaffleRecord.raffle_count - checkinraffle.max_raffle_count_weight;
        let treasury = object::borrow_mut(get_treasury());
        let coin = mint_coin(treasury, checkinraffle.grand_prize_duration);
        account_coin_store::deposit(sender, coin);
    }

    public(friend) fun get_check_in_raffle_v1(user: &signer) {
        let sender = address_of(user);
        let random_value = get_random(user, 100);
        let checkinraffle = account::borrow_mut_resource<CheckInRaffle_v1>(@fate);
        let treasury = object::borrow_mut(get_treasury());

        if (random_value <= checkinraffle.grand_prize_weight) {
            let coin = mint_coin(treasury, checkinraffle.grand_prize_duration);
            account_coin_store::deposit(sender, coin);
        } else if (random_value <= checkinraffle.grand_prize_weight + checkinraffle.second_prize_weight) {
            let coin = mint_coin(treasury, checkinraffle.second_prize_duration);
            account_coin_store::deposit(sender, coin);
        } else if (random_value <= checkinraffle.grand_prize_weight + checkinraffle.second_prize_weight + checkinraffle.third_prize_weight) {
            let coin = mint_coin(treasury, checkinraffle.third_prize_duration);
            account_coin_store::deposit(sender, coin);
        };

        emit(CheckInRaffleEmit {
            user: sender,
            result: random_value
        });
    }

    public entry fun set_check_in_raffle_v1(
        _: &mut Object<AdminCap>,
        grand_prize_duration: u256,
        second_prize_duration: u256,
        third_prize_duration: u256,
        grand_prize_weight: u256,
        second_prize_weight: u256,
        third_prize_weight: u256,
        max_raffle_count_weight: u64,
        daily_max_raffle_count: u64
    ) {
        let checkinraffle = account::borrow_mut_resource<CheckInRaffle_v1>(@fate);
        checkinraffle.grand_prize_duration = grand_prize_duration;
        checkinraffle.grand_prize_weight = grand_prize_weight;
        checkinraffle.second_prize_duration = second_prize_duration;
        checkinraffle.second_prize_weight = second_prize_weight;
        checkinraffle.third_prize_duration = third_prize_duration;
        checkinraffle.third_prize_weight = third_prize_weight;
        checkinraffle.max_raffle_count_weight = max_raffle_count_weight;
        checkinraffle.daily_max_raffle_count = daily_max_raffle_count;
    }

    public entry fun create_check_in_raffle_v1(
        admin: &signer,
        _: &mut Object<AdminCap>,
    ) {
        let checkinraffle_v1 = CheckInRaffle_v1 {
            grand_prize_duration: 1000,
            second_prize_duration: 500,
            third_prize_duration: 150,
            grand_prize_weight: 5,
            second_prize_weight: 25,
            third_prize_weight: 70,
            max_raffle_count_weight: 10,
            daily_max_raffle_count: 50,
        };
        account::move_resource_to(admin, checkinraffle_v1);
    }

    #[view]
    public fun query_check_in_raffle_v1(): (u256, u256, u256, u256, u256, u256, u64, u64) {
        let checkinraffle = account::borrow_resource<CheckInRaffle_v1>(@fate);
        (
            checkinraffle.grand_prize_duration,
            checkinraffle.grand_prize_weight,
            checkinraffle.second_prize_duration,
            checkinraffle.second_prize_weight,
            checkinraffle.third_prize_duration,
            checkinraffle.third_prize_weight,
            checkinraffle.max_raffle_count_weight,
            checkinraffle.daily_max_raffle_count
        )
    }

    #[view]
    public fun query_check_in_raffle_record_v1(user: address): (address, u64, u64, u64) {
        let check_in_raffle_record = account::borrow_resource<CheckInRaffleRecord_v1>(user);
        (
            check_in_raffle_record.user,
            check_in_raffle_record.raffle_count,
            check_in_raffle_record.daily_raffle_count,
            check_in_raffle_record.last_raffle_date
        )
    }

    #[view]
    public fun query_check_in_raffle_view_v1(): &CheckInRaffle_v1 {
        let checkinraffle = account::borrow_resource<CheckInRaffle_v1>(@fate);
        checkinraffle
    }

    #[view]
    public fun query_check_in_raffle_record_view_v1(user: address): &CheckInRaffleRecord_v1 {
        let check_in_raffle_record = account::borrow_resource<CheckInRaffleRecord_v1>(user);
        check_in_raffle_record
    }

    public entry fun get_check_in_raffle_by_fate(user: &signer){
        let caller_address = signer::address_of(user);
        if (caller_address != @fate) {
            abort 403
        };
        init_check_in_raffle_record(user);
        let sender = signer::address_of(user);
        let checkinraffle = account::borrow_mut_resource<CheckInRaffle>(@fate);
        let checkInRaffleRecord = account::borrow_mut_resource<CheckInRaffleRecord>(address_of(user));
        let avg_price = (checkinraffle.grand_prize_duration * checkinraffle.grand_prize_weight +
            checkinraffle.second_prize_duration * checkinraffle.second_prize_weight +
            checkinraffle.third_prize_duration * checkinraffle.third_prize_weight) / 100;

        let treasury = object::borrow_mut(get_treasury());

        if (check_user_nft(sender)){
            let (_, raffle_discount, _, _) = query_user_nft(sender);
            let boosted_share = avg_price * (100 - (raffle_discount as u256)) / 100;
            let cost_coin = account_coin_store::withdraw<FATE>(user, boosted_share);
            burn_coin(treasury,cost_coin);
        }else {
            let cost_coin = account_coin_store::withdraw<FATE>(user, avg_price);
            burn_coin(treasury,cost_coin);
        };
        checkInRaffleRecord.raffle_count = checkInRaffleRecord.raffle_count + 1;
        get_check_in_raffle(user);
    }

    public entry fun claim_max_raffle(user: &signer){
        let caller_address = signer::address_of(user);
        if (caller_address != @fate) {
            abort 403
        };
        let sender = address_of(user);
        let checkinraffle = account::borrow_mut_resource<CheckInRaffle>(@fate);
        let checkInRaffleRecord = account::borrow_mut_resource<CheckInRaffleRecord>(sender);
        assert!(checkInRaffleRecord.raffle_count >= checkinraffle.max_raffle_count_weight,Err_Not_enough_raffle_times);
        checkInRaffleRecord.raffle_count = checkInRaffleRecord.raffle_count - checkinraffle.max_raffle_count_weight;
        let treasury = object::borrow_mut(get_treasury());
        let coin = mint_coin(treasury,checkinraffle.grand_prize_duration);
        account_coin_store::deposit(sender, coin);
    }


    public(friend) fun get_check_in_raffle(user: &signer){
        let caller_address = signer::address_of(user);
        if (caller_address != @fate) {
            abort 403
        };
        let sender = address_of(user);
        let random_value = get_random(user,100);
        let checkinraffle = account::borrow_mut_resource<CheckInRaffle>(@fate);
        let treasury = object::borrow_mut(get_treasury());

        if (random_value <= checkinraffle.grand_prize_weight) {
            let coin = mint_coin(treasury,checkinraffle.grand_prize_duration);
            account_coin_store::deposit(sender, coin);
        } else if (random_value <= checkinraffle.grand_prize_weight + checkinraffle.second_prize_weight) {
            let coin = mint_coin(treasury,checkinraffle.second_prize_duration);
            account_coin_store::deposit(sender, coin);
        } else if (random_value <= checkinraffle.grand_prize_weight + checkinraffle.second_prize_weight + checkinraffle.third_prize_weight) {
            let coin = mint_coin(treasury,checkinraffle.third_prize_duration);
            account_coin_store::deposit(sender, coin);
        };

        emit(CheckInRaffleEmit{
            user: sender,
            result: random_value
        });
    }

    public entry fun set_check_in_raffle(
        _: &mut Object<AdminCap>,
        grand_prize_duration: u256,
        second_prize_duration: u256,
        third_prize_duration: u256,
        grand_prize_weight: u256,
        second_prize_weight: u256,
        third_prize_weight: u256,
        max_raffle_count_weight: u64
    ){
        let checkinraffle = account::borrow_mut_resource<CheckInRaffle>(@fate);
        checkinraffle.grand_prize_duration = grand_prize_duration;
        checkinraffle.grand_prize_weight = grand_prize_weight;
        checkinraffle.second_prize_duration = second_prize_duration;
        checkinraffle.second_prize_weight = second_prize_weight;
        checkinraffle.third_prize_duration = third_prize_duration;
        checkinraffle.third_prize_weight = third_prize_weight;
        checkinraffle.max_raffle_count_weight = max_raffle_count_weight;
    }

    #[view]
    public fun query_check_in_raffle(): (u256, u256, u256, u256, u256, u256, u64) {
        let checkinraffle = account::borrow_resource<CheckInRaffle>(@fate);
        (
            checkinraffle.grand_prize_duration,
            checkinraffle.grand_prize_weight,
            checkinraffle.second_prize_duration,
            checkinraffle.second_prize_weight,
            checkinraffle.third_prize_duration,
            checkinraffle.third_prize_weight,
            checkinraffle.max_raffle_count_weight,
        )
    }

    #[view]
    public fun query_check_in_raffle_record(user: address): (address, u64) {
        let check_in_raffle_record = account::borrow_resource<CheckInRaffleRecord>(user);
        (
            check_in_raffle_record.user,
            check_in_raffle_record.raffle_count
        )
    }

    #[view]
    public fun query_check_in_raffle_view(): &CheckInRaffle {
        let checkinraffle = account::borrow_resource<CheckInRaffle>(@fate);
        checkinraffle
    }

    #[view]
    public fun query_check_in_raffle_record_view(user: address): &CheckInRaffleRecord {
        let check_in_raffle_record = account::borrow_resource<CheckInRaffleRecord>(user);
        check_in_raffle_record
    }

    #[test_only]
    public fun test_init(user: &signer) {
        init(user);
    }
}
