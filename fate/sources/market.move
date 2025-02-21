module fate::market {
    use std::string;
    use std::string::String;
    use fate::admin::AdminCap;
    use fate::fate::FATE;
    use fate::fate::{get_treasury, burn_coin};
    use moveos_std::object::{Self, Object};
    use moveos_std::account;
    use moveos_std::table::{Self, Table};
    use rooch_framework::account_coin_store;

    const ErrorItemNotFound: u64 = 1;

    //AI agent price table
    struct PriceRecord has key {
        prices: Table<String, u256>,
    }

    fun init(admin: &signer){
        let pricerecordtable = table::new<String,u256>();
        let items = string::utf8(b"taro");
        table::add(&mut pricerecordtable,items,50);
        let pricerecord = PriceRecord{
            prices: pricerecordtable
        };
        account::move_resource_to(admin, pricerecord);
    }

    public entry fun pay(user: &signer,items: String){
        let pricerecord = account::borrow_mut_resource<PriceRecord>(@fate);
        assert!(table::contains(&pricerecord.prices, items), ErrorItemNotFound);
        let price = table::borrow_mut(&mut pricerecord.prices,items);

        let treasury = object::borrow_mut(get_treasury());
        let cost_coin = account_coin_store::withdraw<FATE>(user, *price);
        burn_coin(treasury,cost_coin);
    }

    public entry fun add_price(_: &mut Object<AdminCap>, items: String, update_price: u256){
        let pricerecord = account::borrow_mut_resource<PriceRecord>(@fate);
        table::add(&mut pricerecord.prices,items,update_price);
    }

    public entry fun update_price(_: &mut Object<AdminCap>, items: String, update_price: u256){
        let pricerecord = account::borrow_mut_resource<PriceRecord>(@fate);
        let price = table::borrow_mut(&mut pricerecord.prices,items);
        *price = update_price
    }

    public entry fun remove_price(_: &mut Object<AdminCap>, items: String){
        let pricerecord = account::borrow_mut_resource<PriceRecord>(@fate);
        table::remove(&mut pricerecord.prices,items);
    }

    #[test_only]
    public fun test_init(user: &signer) {
        init(user);
    }
}
