#[test_only]
module fate::test_fate {
    use std::string;
    // use std::signer;
    use moveos_std::object;
    use fate::admin::AdminCap;
    use moveos_std::timestamp::update_global_time_for_test;

    const Millis_per_day: u64 = 24 * 60 * 60 * 1000;

    #[test(user = @fate)]
    fun test_init(user: &signer) {
        rooch_framework::genesis::init_for_test();
        fate::fate::test_init();
        fate::daily_check_in::test_init(user);
        fate::raffle::test_init(user);
        fate::market::test_init(user);

        // let sender = signer::address_of(user);

        //check in a week
        update_global_time_for_test(1739960100);
        fate::daily_check_in::checkin(user);
        update_global_time_for_test(1739960100 + (Millis_per_day * 1)+ 1);
        fate::daily_check_in::checkin(user);
        update_global_time_for_test(1739960100 + (Millis_per_day * 2)+ 2);
        fate::daily_check_in::checkin(user);
        update_global_time_for_test(1739960100 + (Millis_per_day * 3)+ 3);
        fate::daily_check_in::checkin(user);
        update_global_time_for_test(1739960100 + (Millis_per_day * 4)+ 4);
        fate::daily_check_in::checkin(user);
        update_global_time_for_test(1739960100 + (Millis_per_day * 5)+ 5);
        fate::daily_check_in::checkin(user);
        update_global_time_for_test(1739960100 + (Millis_per_day * 6)+ 6);
        fate::daily_check_in::checkin(user);

        //check_in_raffle
        fate::daily_check_in::get_week_raffle(user);
        // // pay for taro
        let items = string::utf8(b"taro");
        let items2 = string::utf8(b"taro1");
        fate::market::pay(user,items);

        let admin_cap_id = object::named_object_id<AdminCap>();
        let admin_cap_obj = object::borrow_mut_object<AdminCap>(user,admin_cap_id);
        fate::market::update_price(admin_cap_obj,items2,(10 as u256));
        fate::raffle::get_check_in_raffle_by_fate(user);
    }
}
