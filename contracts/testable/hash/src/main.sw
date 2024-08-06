// SPDX-License-Identifier: Apache-2.0
contract;

use std::hash::*;

abi TestHash {
    fn hash_key_keccak256(one: u256, two: u64, three: bool) -> b256;
    fn hash_key_sha256(one: u256, two: u64, three: bool) -> b256;
}

struct Key {
    one: u256,
    two: u64,
    three: bool,
}

impl Hash for Key {
    fn hash(self, ref mut state: Hasher) {
        self.one.hash(state);
        self.two.hash(state);
        self.three.hash(state);
    }
}

impl TestHash for Contract {
    fn hash_key_keccak256(one: u256, two: u64, three: bool) -> b256 {
        keccak256(Key {
            one,
            two,
            three
        })
    }

    fn hash_key_sha256(one: u256, two: u64, three: bool) -> b256 {
        sha256(Key {
            one,
            two,
            three
        })
    }
}

#[test]
fn test_from() {
    let contr = abi(TestHash, CONTRACT_ID);
    log(contr.hash_key());
    // assert_eq(contr.hash_key(), 0x0000000000000000000000000000000000000000000000000000000000000000);
}