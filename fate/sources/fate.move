module fate::fate {
    use std::option;
    use std::string;
    use moveos_std::object::{Self, Object, to_shared};
    use rooch_framework::coin::{Self, Coin, CoinInfo};
    #[test_only]
    use std::signer::address_of;
    #[test_only]
    use rooch_framework::account_coin_store;

    friend fate::daily_check_in;
    friend fate::market;
    friend fate::raffle;
    friend fate::stake_by_grow_votes;

    const ErrorTransferAmountTooLarge: u64 = 1;
    const DECIMALS: u8 = 6u8;

    struct FATE has key, store {}

    struct Treasury has key {
        supply:u256,
        coin_info: Object<CoinInfo<FATE>>
    }

    fun init() {
        let coin_image= b"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?><!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\" \"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\"><svg version=\"1.1\" id=\"Layer_1\" xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" x=\"0px\" y=\"0px\" width=\"32px\" height=\"32px\" viewBox=\"0 0 32 32\" enable-background=\"new 0 0 32 32\" xml:space=\"preserve\">  <image id=\"image0\" width=\"32\" height=\"32\" x=\"0\" y=\"0\"    xlink:href=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAQAAADZc7J/AAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAACYktHRAD/h4/MvwAAAAd0SU1FB+kCEgIrF4togF4AAAL9SURBVEjHlVRvSFNxFD337c1SNwJNKa2QigyiIt/bojBbEfQhosikPlUEQf8oIhCKArMiiKT6UJZBVBRBrRKkD+GgZZjZNhONQKpFURT9IW3Tub29d/vwNre5zfbux3vvOZzfuec9EyYouzztXtnqMu+3oew7QrbBolKpRXtCbgqiT2p0WLLtmTI1HWLxfvEe/HSHPtIP6uLqyOnpf6r733L6LqW3lq6KXqRR3MVI5FHlb8BfIaxVC2kbwsJhz7P/EEizcI5q+BIWohZK0sBMD/EGe9DJ9b4PWZ7gmFx8BLfwipzCgOCFQv0wYSZayUv91Eu38Qu9bKbmsqJSz/fRNAXSRjSRn9oQKLzvDsZ6x9Eozut+N2ZsoXkzplANr0CD9Zo7CgAiAEjzcQGVuMJDmqvnffaT9Q3j5rJyJYwXtDO413bI44oRkBtOtNGAx4X/VtdXXJWqOERz+Qxc8Rwwfpqv5wLXy9dT4ERI9y9OgBmRXOGppROooJ9kBMZRkP78mAIBAUMEIoP1CwoAwKoqzDZEoKggTnhALCBoiMA8pkDUFUAIpRDIm7Eb4ApAvSGHAABXvM7EPKwilmJR9wAIpyoo4vkAWRmYw1EAoKLk8SSOMicUQAUmpXzY3ha06FE2rUhEOVH5PMyUkgNSDHlgYQ2cuAKpYLPJCIGfTdo4BVFDCqysISkHiIJJNEJQwuDkb8FwfcnDOAX5I7VSVa5w2xplJ0qSgkRH+TzVcIEsmx93fZ0YXDWX1mhTsBsDcIwReFyOJYFdaMDzyGR5MPKgbzgz2GEZroOV1/NsHPK16r2YB+6or1mthJ9OspS3Q96QwRuyrQ9u12zaCe6wLojD40kEAPQOol66SmexBc22cqGn+yWpHFYYAOyL1eXaVNqHDiz2fU7hzWDRSq0JebhFAWqv+HRftRfzJrZgK+eLB7ufpgnL9NY604dtdAqvhXb8xQiXsI3WcaP1sv4jz4FANyxQjwN0F7+xhx8ox/p+5HrkpJJmSbflTrs80c4/0E0ajI4UqFEAAAAldEVYdGRhdGU6Y3JlYXRlADIwMjUtMDItMThUMDI6NDM6MjMrMDA6MDCPa6PlAAAAJXRFWHRkYXRlOm1vZGlmeQAyMDI1LTAyLTE4VDAyOjQzOjIzKzAwOjAw/jYbWQAAACh0RVh0ZGF0ZTp0aW1lc3RhbXAAMjAyNS0wMi0xOFQwMjo0MzoyMyswMDowMKkjOoYAAAAASUVORK5CYII=\" /></svg>";
        let coin_info_obj = coin::register_extend<FATE>(
            string::utf8(b"Rooch FATE3AI"),
            string::utf8(b"FATE"),
            option::some(string::utf8(coin_image)), // placeholder URL
            DECIMALS,
        );

        let treasury_obj = object::new_named_object(Treasury {supply:0, coin_info: coin_info_obj });
        to_shared(treasury_obj);
    }

    public(friend) fun mint_coin(treasury: &mut Treasury, amount: u256): Coin<FATE> {
        treasury.supply = treasury.supply + amount;
        coin::mint(&mut treasury.coin_info, amount)
    }

    public(friend) fun burn_coin(treasury: &mut Treasury, c: Coin<FATE>) {
        let amount = coin::value(&c);
        treasury.supply = treasury.supply - amount;

        coin::burn(&mut treasury.coin_info, c)
    }

    public(friend) fun get_treasury(): &mut Object<Treasury> {
        let object_id = object::named_object_id<Treasury>();
        object::borrow_mut_object_shared<Treasury>(object_id)
    }


    #[test_only]
    public fun test_init() {
        init();
    }

    #[test_only]
    public fun test_mint(user: &signer, amount: u256) {
        let treasury = get_treasury();
        let treasury = object::borrow_mut(treasury);
        let token = mint_coin(treasury, amount);
        account_coin_store::deposit(address_of(user), token);
    }
}