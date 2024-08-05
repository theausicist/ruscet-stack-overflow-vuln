// SPDX-License-Identifier: Apache-2.0
contract;

use helpers::signed_256::*;

abi TestSigned256 { }

impl TestSigned256 for Contract { }

#[test]
fn test_new() {
    let a = Signed256::new();
    assert(a.value == 0);
    assert(a.is_neg == false);
}

#[test]
fn test_from() {
    let a = Signed256::from(0);
    assert(a.value == 0);
    assert(a.is_neg == false);

    let b = Signed256::from(69420);
    assert(b.value == 69420);
    assert(b.is_neg == false);
}

#[test]
fn test_pos_add() {
    let mut a = Signed256::from(0);
    let mut b = Signed256::from(69420);

    let result = a + b;
    assert(result.value == 69420);
    assert(result.is_neg == false);
}

#[test]
fn test_neg_add() {
    let mut a = Signed256::from_u256(1234567, true);
    let mut b = Signed256::from(69420);

    let result = a + b;
    assert(result.value == 1165147);
    assert(result.is_neg);
}

#[test]
fn test_pos_sub() {
    let mut a = Signed256::from(1234567);
    let mut b = Signed256::from(69420);

    let result = a - b;
    assert(result.value == 1165147);
    assert(result.is_neg == false);
}

#[test]
fn test_neg_sub() {
    let mut a = Signed256::from_u256(1234567, true);
    let mut b = Signed256::from(69420);

    let result = a - b;
    assert(result.value == 1303987);
    assert(result.is_neg);
}