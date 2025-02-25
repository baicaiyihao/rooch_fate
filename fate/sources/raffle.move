module fate::raffle {
    use moveos_std::object::Object;
    use fate::admin::AdminCap;
    use moveos_std::object;
    use moveos_std::signer::address_of;
    use moveos_std::event::emit;
    use moveos_std::account;
    use rooch_framework::account_coin_store;
    use fate::random::get_random;
    use fate::fate::{get_treasury, mint_coin, FATE, burn_coin};

    friend fate::daily_check_in;

    const Err_Not_enough_raffle_times: u64 = 101;

    const ONE_FATE: u256 = 1000000;

    struct CheckInRaffle has key {
        grand_prize_duration: u256,
        second_prize_duration: u256,
        third_prize_duration: u256,
        grand_prize_weight: u256,
        second_prize_weight: u256,
        third_prize_weight: u256,
        max_raffle_count_weight: u64
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
    }

    fun init_check_in_raffle_record(admin: &signer){
        if (!account::exists_resource<CheckInRaffleRecord>(address_of(admin))) {
            let checkInRaffleRecord = CheckInRaffleRecord {
                user: address_of(admin),
                raffle_count: 0
            };
            account::move_resource_to(admin, checkInRaffleRecord);
        }
    }

    public entry fun get_check_in_raffle_by_fate(user: &signer){
        init_check_in_raffle_record(user);

        let checkinraffle = account::borrow_mut_resource<CheckInRaffle>(@fate);
        let checkInRaffleRecord = account::borrow_mut_resource<CheckInRaffleRecord>(address_of(user));
        let avg_price = (checkinraffle.grand_prize_duration * checkinraffle.grand_prize_weight +
            checkinraffle.second_prize_duration * checkinraffle.second_prize_weight +
            checkinraffle.third_prize_duration * checkinraffle.third_prize_weight) / 100;

        let treasury = object::borrow_mut(get_treasury());

        let cost_coin = account_coin_store::withdraw<FATE>(user, avg_price * ONE_FATE);
        burn_coin(treasury,cost_coin);
        checkInRaffleRecord.raffle_count = checkInRaffleRecord.raffle_count + 1;
        get_check_in_raffle(user);
    }

    public entry fun claim_max_raffle(user: &signer){
        let sender = address_of(user);
        let checkinraffle = account::borrow_mut_resource<CheckInRaffle>(@fate);
        let checkInRaffleRecord = account::borrow_mut_resource<CheckInRaffleRecord>(sender);
        assert!(checkInRaffleRecord.raffle_count >= checkinraffle.max_raffle_count_weight,Err_Not_enough_raffle_times);
        checkInRaffleRecord.raffle_count = checkInRaffleRecord.raffle_count - checkinraffle.max_raffle_count_weight;
        let treasury = object::borrow_mut(get_treasury());
        let coin = mint_coin(treasury,checkinraffle.grand_prize_duration * ONE_FATE);
        account_coin_store::deposit(sender, coin);
    }


    public(friend) fun get_check_in_raffle(user: &signer){
        let sender = address_of(user);
        let random_value = get_random(user,100);
        let checkinraffle = account::borrow_mut_resource<CheckInRaffle>(@fate);
        let treasury = object::borrow_mut(get_treasury());

        if (random_value <= checkinraffle.grand_prize_weight) {
            let coin = mint_coin(treasury,checkinraffle.grand_prize_duration * ONE_FATE);
            account_coin_store::deposit(sender, coin);
        } else if (random_value <= checkinraffle.grand_prize_weight + checkinraffle.second_prize_weight) {
            let coin = mint_coin(treasury,checkinraffle.second_prize_duration * ONE_FATE);
            account_coin_store::deposit(sender, coin);
        } else if (random_value <= checkinraffle.grand_prize_weight + checkinraffle.second_prize_weight + checkinraffle.third_prize_weight) {
            let coin = mint_coin(treasury,checkinraffle.third_prize_duration * ONE_FATE);
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
    public fun query_check_in_raffle_view(): CheckInRaffleView {
        let checkinraffle = account::borrow_resource<CheckInRaffle>(@fate);
        CheckInRaffleView {
            grand_prize_duration: checkinraffle.grand_prize_duration,
            grand_prize_weight: checkinraffle.grand_prize_weight,
            second_prize_duration: checkinraffle.second_prize_duration,
            second_prize_weight: checkinraffle.second_prize_weight,
            third_prize_duration: checkinraffle.third_prize_duration,
            third_prize_weight: checkinraffle.third_prize_weight,
            max_raffle_count_weight: checkinraffle.max_raffle_count_weight,
        }
    }

    #[view]
    public fun query_check_in_raffle_record_view(user: address): CheckInRaffleRecordView {
        let check_in_raffle_record = account::borrow_resource<CheckInRaffleRecord>(user);
        CheckInRaffleRecordView{
            user: check_in_raffle_record.user,
            raffle_count: check_in_raffle_record.raffle_count
        }
    }

    #[test_only]
    public fun test_init(user: &signer) {
        init(user);
    }
}
