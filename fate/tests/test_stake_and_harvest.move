// #[test_only]
// module fate::test_stake_and_harvest {
//     use std::signer;
//     use fate::admin::AdminCap;
//     use moveos_std::object;
//     use moveos_std::account;
//     use moveos_std::timestamp::{fast_forward_seconds_for_test,
//         update_global_time_for_test_secs
//     };
//     use rooch_framework::account_coin_store;
//     use fate::fate::FATE;
//     use fate::stake_by_grow_votes::{StakeRecord, StakePool, test_update_grow_votes,test_query_time};
//
//     const Millis_per_day: u64 = 24 * 60 * 60;
//     const Seconds_100: u64 = 100;
//
//     #[test(sender = @fate)]
//     fun test_stake_and_harvest(sender: &signer) {
//         rooch_framework::genesis::init_for_test();
//         fate::fate::test_init();
//         fate::admin::test_init();
//         fate::stake_by_grow_votes::test_init(sender);
//
//
//         let sender_addr = signer::address_of(sender);
//         let mock_votes = 1000u256;
//
//         let total_fate_supply: u256 = 5184000000 * 1000000;
//         let start_time = 1740370604;
//         let end_time = start_time + (Millis_per_day * 60);
//
//         let admin_cap_id = object::named_object_id<AdminCap>();
//         let admin_cap_obj = object::borrow_mut_object<AdminCap>(sender,admin_cap_id);
//
//         fate::stake_by_grow_votes::modify_stake_pool(admin_cap_obj,total_fate_supply,start_time,end_time);
//         let (_, end_time, _, _, _, _, _) = fate::stake_by_grow_votes::test_query_pool_info(sender);
//         assert!(end_time == 1745554604, 101);
//
//         update_global_time_for_test_secs(start_time);
//         fate::stake_by_grow_votes::create_stake_record_for_test(sender, mock_votes);
//         let stake_pool = account::borrow_mut_resource<StakePool>(sender_addr);
//         let stake_record = account::borrow_mut_resource<StakeRecord>(sender_addr);
//         fate::stake_by_grow_votes::test_stake(sender, stake_pool, stake_record);
//         let (_, fate_grow_votes, stake_grow_votes, _, _) = fate::stake_by_grow_votes::query_stake_info(sender_addr);
//         assert!(fate_grow_votes == 0, 1);
//         assert!(stake_grow_votes == mock_votes, 2);
//
//         let stake_pool = account::borrow_mut_resource<StakePool>(sender_addr);
//         let stake_record = account::borrow_mut_resource<StakeRecord>(sender_addr);
//         //fast_forward_seconds 100s
//         fast_forward_seconds_for_test(100);
//         let now = test_query_time();
//         assert!(now >= 1740370704, 101);
//         let rewards = fate::stake_by_grow_votes::test_query_fate_rewards(stake_pool, stake_record,sender_addr);
//         assert!(rewards == 100000000000, 3);
//
//         fate::stake_by_grow_votes::test_harvest(sender, stake_pool, stake_record);
//         let balance = account_coin_store::balance<FATE>(sender_addr);
//         assert!(balance == 100000000000, 4);
//
//
//         //fast_forward_seconds 200s
//         test_update_grow_votes(sender,2000);
//         let stake_pool = account::borrow_mut_resource<StakePool>(sender_addr);
//         let stake_record = account::borrow_mut_resource<StakeRecord>(sender_addr);
//         fate::stake_by_grow_votes::test_stake(sender, stake_pool, stake_record);
//         let (_, fate_grow_votes, stake_grow_votes, _, _) = fate::stake_by_grow_votes::query_stake_info(sender_addr);
//         assert!(fate_grow_votes == 0, 1);
//         assert!(stake_grow_votes == 2000, 2);
//         fast_forward_seconds_for_test(100);
//         let rewards = fate::stake_by_grow_votes::test_query_fate_rewards(stake_pool, stake_record,sender_addr);
//         assert!(rewards == 100000000000, 3);
//         fate::stake_by_grow_votes::test_harvest(sender, stake_pool, stake_record);
//         let balance = account_coin_store::balance<FATE>(sender_addr);
//         assert!(balance == 200000000000, 4);
//
//
//         //fast_forward_seconds 300s
//         test_update_grow_votes(sender,3000);
//         let stake_pool = account::borrow_mut_resource<StakePool>(sender_addr);
//         let stake_record = account::borrow_mut_resource<StakeRecord>(sender_addr);
//         fate::stake_by_grow_votes::test_stake(sender, stake_pool, stake_record);
//         let (_, fate_grow_votes, stake_grow_votes, _, _) = fate::stake_by_grow_votes::query_stake_info(sender_addr);
//         assert!(fate_grow_votes == 0, 1);
//         assert!(stake_grow_votes == 3000, 2);
//         fast_forward_seconds_for_test(100);
//         let rewards = fate::stake_by_grow_votes::test_query_fate_rewards(stake_pool, stake_record,sender_addr);
//         assert!(rewards == 100000000000, 3);
//         fate::stake_by_grow_votes::test_unstake(sender, stake_pool, stake_record);
//         let balance = account_coin_store::balance<FATE>(sender_addr);
//         assert!(balance == 300000000000, 4);
//
//         let (_,total_votes, staked_votes, _, _) = fate::stake_by_grow_votes::query_stake_info(sender_addr);
//         assert!(staked_votes == 0, 5);
//         assert!(total_votes == 3000, 6);
//         let (_, _, total_supply, _, _, total_mined, _) = fate::stake_by_grow_votes::test_query_pool_info(sender);
//         assert!(total_mined <= total_supply, 7);
//
//         //end
//         // update_global_time_for_test_secs(start_time + (Millis_per_day * 60));
//         // let stake_pool = account::borrow_mut_resource<StakePool>(sender_addr);
//         // let stake_record = account::borrow_mut_resource<StakeRecord>(sender_addr);
//         // fate::stake_by_grow_votes::test_stake(sender, stake_pool, stake_record);
//     }
// }