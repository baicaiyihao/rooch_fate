module fate::random {
    use std::option;
    use std::vector;
    use moveos_std::timestamp::{Self};
    use moveos_std::tx_context;
    use moveos_std::address;
    use moveos_std::signer;
    use moveos_std::bcs;
    use moveos_std::hash::sha3_256;
    use rooch_framework::transaction::{Self, TransactionSequenceInfo};

    friend fate::raffle;

    fun u64_to_bytes(num: u64): vector<u8> {
        if (num == 0) {
            return b"0"
        };
        let bytes = vector::empty<u8>();
        while (num > 0) {
            let remainder = num % 10;
            num = num / 10;
            vector::push_back(&mut bytes, (remainder as u8) + 48);
        };
        vector::reverse(&mut bytes);
        bytes
    }

    fun bytes_to_u64(bytes: vector<u8>): u64 {
        let value = 0u64;
        let i = 0u64;
        while (i < 8) {
            value = value | ((*vector::borrow(&bytes, i) as u64) << ((8 * (7 - i)) as u8));
            i = i + 1;
        };
        return value
    }

    fun bytes_to_u256(bytes: vector<u8>): u256 {
        let output: u256 = 0;
        let bytes_length: u64 = 32;
        let idx: u64 = 0;
        while (idx < bytes_length) {
            let current_byte = *std::vector::borrow(&bytes, idx);
            output = (output << 8) | (current_byte as u256) ;
            idx = idx + 1;
        };
        output
    }

    fun generate_magic_number(): u64 {
        // generate a random number from tx_context
        let bytes = vector::empty<u8>();
        let tx_sequence_info_opt = tx_context::get_attribute<TransactionSequenceInfo>();
        if (option::is_some(&tx_sequence_info_opt)) {
            let tx_sequence_info = option::extract(&mut tx_sequence_info_opt);
            let tx_accumulator_root = transaction::tx_accumulator_root(&tx_sequence_info);
            let tx_accumulator_root_bytes = bcs::to_bytes(&tx_accumulator_root);
            vector::append(&mut bytes, tx_accumulator_root_bytes);
        } else {
            // if it doesn't exist, get the tx hash
            vector::append(&mut bytes, bcs::to_bytes(&tx_context::tx_hash()));
        };
        vector::append(&mut bytes, bcs::to_bytes(&tx_context::sequence_number()));
        vector::append(&mut bytes, bcs::to_bytes(&tx_context::sender()));
        vector::append(&mut bytes, bcs::to_bytes(&timestamp::now_milliseconds()));

        let seed = sha3_256(bytes);
        let magic_number = bytes_to_u64(seed);

        magic_number
    }

    public fun get_random(account: &signer, max: u256): u256 {
        let magic_number = generate_magic_number();
        let account_addr = signer::address_of(account);
        let now_seconds = timestamp::now_milliseconds();

        let random_vector = vector::empty<u8>();
        vector::append(&mut random_vector, address::to_bytes(&account_addr));
        vector::append(&mut random_vector, u64_to_bytes(now_seconds));
        vector::append(&mut random_vector, bcs::to_bytes(&tx_context::sequence_number()));
        vector::append(&mut random_vector, bcs::to_bytes(&tx_context::sender()));
        vector::append(&mut random_vector, bcs::to_bytes(&tx_context::tx_hash()));
        vector::append(&mut random_vector, bcs::to_bytes(&magic_number));

        let seed = sha3_256(random_vector);
        let value = bytes_to_u256(seed);
        value % max
    }

    #[test_only]
    public fun test_get_random(user: &signer, amount: u256) {
        get_random(user,amount);
    }
}
