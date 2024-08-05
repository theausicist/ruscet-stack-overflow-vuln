// SPDX-License-Identifier: Apache-2.0
contract;

use std::hash::*;

abi Storage {
    #[storage(read)]
    fn read_val() -> u64;

    #[storage(write)]
    fn write_val(val: u64);

    #[storage(read)]
    fn read_map(key: u64) -> u64;

    #[storage(write)]
    fn write_map(key: u64, val: u64);
}

storage {
    val: u64 = 69,
    map: StorageMap<u64, u64> = StorageMap::<u64, u64> {}
}

impl Storage for Contract {
    #[storage(read)]
    fn read_val() -> u64 {
        storage.val.read()
    }

    #[storage(write)]
    fn write_val(val: u64) {
        storage.val.write(val)
    }

    #[storage(read)]
    fn read_map(key: u64) -> u64 {
        storage.map.get(key).try_read().unwrap_or(0)
    }

    #[storage(write)]
    fn write_map(key: u64, val: u64) {
        storage.map.insert(key, val)
    }
}
