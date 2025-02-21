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
        table::add(&mut pricerecordtable, items, 50);
        let pricerecord = PriceRecord { prices: pricerecordtable };
        account::move_resource_to(admin, pricerecord);
    }

    public entry fun add_price(_: &mut Object<AdminCap>, items: String, update_price: u256) {
        assert!(account::exists_resource<PriceRecord>(@fate), ErrorPriceRecordNotInitialized);
        let pricerecord = account::borrow_mut_resource<PriceRecord>(@fate);
        assert!(!table::contains(&pricerecord.prices, items), ErrorItemAlreadyExists);
        table::add(&mut pricerecord.prices, items, update_price);
        emit(PriceEvent { action: string::utf8(b"add"), item: items, price: update_price });
    }

    public entry fun update_price(_: &mut Object<AdminCap>, items: String, update_price: u256) {
        assert!(account::exists_resource<PriceRecord>(@fate), ErrorPriceRecordNotInitialized);
        let pricerecord = account::borrow_mut_resource<PriceRecord>(@fate);
        assert!(table::contains(&pricerecord.prices, items), ErrorItemNotFound);
        let price = table::borrow_mut(&mut pricerecord.prices, items);
        *price = update_price;
        emit(PriceEvent { action: string::utf8(b"update"), item: items, price: update_price });
    }

    public entry fun remove_price(_: &mut Object<AdminCap>, items: String) {
        assert!(account::exists_resource<PriceRecord>(@fate), ErrorPriceRecordNotInitialized);
        let pricerecord = account::borrow_mut_resource<PriceRecord>(@fate);
        assert!(table::contains(&pricerecord.prices, items), ErrorItemNotFound);
        table::remove(&mut pricerecord.prices, items);
        emit(PriceEvent { action: string::utf8(b"remove"), item: items, price: 0 });
    }

    public entry fun pay(user: &signer,items: String) {
        assert!(account::exists_resource<PriceRecord>(@fate), ErrorPriceRecordNotInitialized);
        let pricerecord = account::borrow_mut_resource<PriceRecord>(@fate);
        assert!(table::contains(&pricerecord.prices, items), ErrorItemNotFound);
        let price = table::borrow_mut(&mut pricerecord.prices, items);
        let treasury = object::borrow_mut(get_treasury());
        let cost_coin = account_coin_store::withdraw<FATE>(user, *price);
        burn_coin(treasury, cost_coin);
    }

    #[test_only]
    public fun test_init(user: &signer) {
        init(user);
    }
}