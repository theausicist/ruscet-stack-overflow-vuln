
// SPDX-License-Identifier: Apache-2.0
library;

use helpers::{
    context::*, 
    utils::*,
};

pub struct SetHandler {
    handler: Account,
    is_active: bool
}

pub struct SetTraderReferralCode {
    account: Account,
    code: b256
}

pub struct SetTier {
    tier_id: u64,
    total_rebate: u64,
    discount_share: u64
}

pub struct SetReferrerTier {
    referrer: Account,
    tier_id: u64
}

pub struct SetReferrerDiscountShare {
    referrer: Account,
    discount_share: u64
}

pub struct RegisterCode {
    account: Account,
    code: b256
}

pub struct SetCodeOwner {
    account: Account,
    new_account: Account,
    code: b256
}

pub struct GovSetCodeOwner {
    new_account: Account,
    code: b256
}