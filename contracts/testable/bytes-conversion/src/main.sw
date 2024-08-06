contract;

use std::hash::*;
use std::bytes::*;
use std::bytes_conversions::{
    u64::*,
    b256::*,
    u256::*
};

abi TestBytesConversion {
    fn bytes_to_b256(bytes: Bytes) -> b256;
    fn b256_to_bytes(bits: b256) -> Bytes;
    fn bytes_to_u256(bytes: Bytes) -> u256;
    fn u256_to_bytes(bits: u256) -> Bytes;
    fn bytes_to_u64(bytes: Bytes) -> u64;
    fn u64_to_bytes(bits: u64) -> Bytes;
}

impl TestBytesConversion for Contract {
    fn bytes_to_b256(bytes: Bytes) -> b256 {
        b256::from_le_bytes(bytes)
    }
    
    fn b256_to_bytes(bits: b256) -> Bytes {
        bits.to_le_bytes()
    }

    fn bytes_to_u256(bytes: Bytes) -> u256 {
        u256::from_le_bytes(bytes)
    }
    
    fn u256_to_bytes(bits: u256) -> Bytes {
        bits.to_le_bytes()
    }

    fn bytes_to_u64(bytes: Bytes) -> u64 {
        u64::from_le_bytes(bytes)
    }
    
    fn u64_to_bytes(bits: u64) -> Bytes {
        bits.to_le_bytes()
    }
}
