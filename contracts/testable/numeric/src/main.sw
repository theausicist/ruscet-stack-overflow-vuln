// SPDX-License-Identifier: Apache-2.0
contract;

use std::u128::U128;
use std::u256::U256;

type u128 = U128;

abi Numeric {
    fn u64_mul(val1: u64, val2: u64) -> u64;
    fn u128_mul(val1: u128, val2: u128) -> u128;
    fn u256_mul(val1: U256, val2: U256) -> U256;
}

impl Numeric for Contract {
    fn u64_mul(val1: u64, val2: u64) -> u64 {
        val1 * val2
    }

    fn u128_mul(val1: u128, val2: u128) -> u128 {
        val1 * val2
    }

    fn u256_mul(val1: U256, val2: U256) -> U256 {
        val1 * val2
    }
}
