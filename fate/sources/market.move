module fate::market {
    use std::string::{Self, String};
    use fate::admin::AdminCap;
    use fate::fate::FATE;
    use fate::fate::{get_treasury, burn_coin};
    use moveos_std::object::{Self, Object};
    use moveos_std::account;
    use moveos_std::table::{Self, Table};
    use moveos_std::event::emit;
    use rooch_framework::account_coin_store;

    const ErrorUnauthorized: u64 = 1;
    const ErrorItemAlreadyExists: u64 = 2;
    const ErrorItemNotFound: u64 = 3;
    const ErrorPriceRecordNotInitialized: u64 = 4;

    const ACTION_ADD: vector<u8> = b"add";
    const ACTION_UPDATE: vector<u8> = b"update";
    const ACTION_REMOVE: vector<u8> = b"remove";
    const ACTION_PAY: vector<u8> = b"pay";

    const ONE_FATE: u256 = 1000000;

    struct PriceRecord has key {
        prices: Table<String, u256>,
    }

    struct PriceEvent has copy, drop {
        action: String,
        item: String,
        price: u256,
    }

    fun init(admin: &signer) {
        let pricerecordtable = table::new<String, u256>();
        let items = string::utf8(b"taro");
        let price: u256 = 50;
        table::add(&mut pricerecordtable, items, 50);
        let pricerecord = PriceRecord { prices: pricerecordtable };
        account::move_resource_to(admin, pricerecord);
        emit(PriceEvent { action: string::utf8(b"add"), item: items, price });
    }

    public entry fun add_price(_: &mut Object<AdminCap>, items: String, update_price: u256) {
        assert!(account::exists_resource<PriceRecord>(@fate), ErrorPriceRecordNotInitialized);
        let pricerecord = account::borrow_mut_resource<PriceRecord>(@fate);
        assert!(!table::contains(&pricerecord.prices, items), ErrorItemAlreadyExists);
        table::add(&mut pricerecord.prices, items, update_price);
        emit(PriceEvent { action: string::utf8(ACTION_ADD), item: items, price: update_price });
    }

    public entry fun update_price(_: &mut Object<AdminCap>, items: String, update_price: u256) {
        assert!(account::exists_resource<PriceRecord>(@fate), ErrorPriceRecordNotInitialized);
        let pricerecord = account::borrow_mut_resource<PriceRecord>(@fate);
        assert!(table::contains(&pricerecord.prices, items), ErrorItemNotFound);
        let price = table::borrow_mut(&mut pricerecord.prices, items);
        *price = update_price;
        emit(PriceEvent { action: string::utf8(ACTION_UPDATE), item: items, price: update_price });
    }

    public entry fun remove_price(_: &mut Object<AdminCap>, items: String) {
        assert!(account::exists_resource<PriceRecord>(@fate), ErrorPriceRecordNotInitialized);
        let pricerecord = account::borrow_mut_resource<PriceRecord>(@fate);
        assert!(table::contains(&pricerecord.prices, items), ErrorItemNotFound);
        table::remove(&mut pricerecord.prices, items);
        emit(PriceEvent { action: string::utf8(ACTION_REMOVE), item: items, price: 0 });
    }

    public entry fun pay(user: &signer,items: String) {
        assert!(account::exists_resource<PriceRecord>(@fate), ErrorPriceRecordNotInitialized);
        let pricerecord = account::borrow_resource<PriceRecord>(@fate);
        assert!(table::contains(&pricerecord.prices, items), ErrorItemNotFound);
        let price = table::borrow(&pricerecord.prices, items);
        let treasury = object::borrow_mut(get_treasury());
        let cost_coin = account_coin_store::withdraw<FATE>(user, *price * ONE_FATE);
        burn_coin(treasury, cost_coin);
        emit(PriceEvent { action: string::utf8(ACTION_PAY), item: items, price: *price });
    }

    #[view]
    public fun query_price_by_items(items: String): u256 {
        let price_record = account::borrow_resource<PriceRecord>(@fate);
        assert!(table::contains(&price_record.prices, items),ErrorItemNotFound);
        let price = table::borrow(&price_record.prices,items);
        *price
    }

    #[test_only]
    public fun test_init(user: &signer) {
        init(user);
    }
}