module fate::utils {

    const SECONDS_PER_DAY: u64 = 24 * 60 * 60;

    public fun is_same_day(timestamp1: u64, timestamp2: u64): bool {
        timestamp1 / SECONDS_PER_DAY == timestamp2 / SECONDS_PER_DAY
    }

    public fun is_next_day(timestamp1: u64, timestamp2: u64): bool {
        let day1 = timestamp1 / SECONDS_PER_DAY;
        let day2 = timestamp2 / SECONDS_PER_DAY;
        day2 == day1 + 1
    }
}
