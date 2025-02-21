module fate::admin {
    use moveos_std::object;
    #[test_only]
    use moveos_std::object::Object;

    struct AdminCap has key, store {}

    fun init() {
        object::transfer(object::new_named_object(AdminCap {}), @fate);
    }

    #[test_only]
    public fun test_init() {
        init();
    }

    #[test_only]
    public fun test_create(): Object<AdminCap> {
        object::new_named_object(AdminCap {})
    }
}
