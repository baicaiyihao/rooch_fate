#[test_only]
module fate::test_stake_and_harvest {
    use std::signer;
    use fate::admin::AdminCap;
    use moveos_std::object;
    use moveos_std::account;
    use moveos_std::timestamp::{update_global_time_for_test, fast_forward_seconds_for_test};
    use rooch_framework::account_coin_store;
    use fate::fate::FATE;
    use fate::stake_by_grow_votes::{StakeRecord, StakePool};

    const Millis_per_day: u64 = 24 * 60 * 60 * 1000;
    const Seconds_100: u64 = 100;

    #[test(sender = @fate)]
    fun test_stake_and_harvest(sender: &signer) {
        rooch_framework::genesis::init_for_test();
        fate::fate::test_init();
        fate::admin::test_init();
        fate::stake_by_grow_votes::test_init(sender);

        let sender_addr = signer::address_of(sender);
        let mock_votes = 1000u256;

        let total_fate_supply: u256 = 5184000000 * 1000000;
        let mining_duration_seconds: u64 = 60 * 86400;
        let start_time = 1739960100 * 1000;
        let end_time = 1739960100 * 1000 + mining_duration_seconds;

        let admin_cap_id = object::named_object_id<AdminCap>();
        let admin_cap_obj = object::borrow_mut_object<AdminCap>(sender,admin_cap_id);

        fate::stake_by_grow_votes::modify_stake_pool(admin_cap_obj,total_fate_supply,start_time,end_time);

        update_global_time_for_test(start_time);
        fate::stake_by_grow_votes::create_stake_record_for_test(sender, mock_votes);
        let stake_pool = account::borrow_mut_resource<StakePool>(sender_addr);
        let stake_record = account::borrow_mut_resource<StakeRecord>(sender_addr);
        fate::stake_by_grow_votes::test_set_stake_pool_end_time(stake_pool, start_time + (Millis_per_day * 60));
        fate::stake_by_grow_votes::test_stake(sender, stake_pool, stake_record);
        let (fate_grow_votes, stake_grow_votes) = fate::stake_by_grow_votes::query_stake_info(sender_addr);
        assert!(fate_grow_votes == 0, 1);
        assert!(stake_grow_votes == mock_votes, 2);

        let stake_pool = account::borrow_mut_resource<StakePool>(sender_addr);
        let stake_record = account::borrow_mut_resource<StakeRecord>(sender_addr);
        //set stake time and set query time 100s
        fast_forward_seconds_for_test(100);
        let rewards = fate::stake_by_grow_votes::test_query_fate_rewards(stake_pool, stake_record);
        assert!(rewards == 100000000000, 3);

        fate::stake_by_grow_votes::test_harvest(sender, stake_pool, stake_record);
        let balance = account_coin_store::balance<FATE>(sender_addr);
        assert!(balance == 100000000000, 4);

        update_global_time_for_test(start_time + (Millis_per_day * 60));
        let stake_pool = account::borrow_mut_resource<StakePool>(sender_addr);
        let stake_record = account::borrow_mut_resource<StakeRecord>(sender_addr);
        fate::stake_by_grow_votes::test_unstake(sender, stake_pool, stake_record);
        let (total_votes, staked_votes) = fate::stake_by_grow_votes::query_stake_info(sender_addr);
        assert!(staked_votes == 0, 5);
        assert!(total_votes == mock_votes, 6);
        let (_, _, total_supply, _, _, total_mined, _) = fate::stake_by_grow_votes::test_query_pool_info(sender);
        assert!(total_mined <= total_supply, 7);
    }

}