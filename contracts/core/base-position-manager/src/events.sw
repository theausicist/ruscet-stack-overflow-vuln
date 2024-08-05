// SPDX-License-Identifier: Apache-2.0
library;

use helpers::{context::*};

pub struct SetDepositFee {
    deposit_fee: u64
}

pub struct SetIncreasePositionBufferBps {
    increase_position_buffer_bps: u64
}

pub struct SetReferralStorage {
    referral_storage: ContractId
}

pub struct SetAdmin {
    admin: Account
}

pub struct WithdrawFees {
    asset: AssetId,
    receiver: Account,
    amount: u64
}

pub struct SetMaxGlobalSizes {
    assets: Vec<AssetId>,
    long_sizes: Vec<u256>,
    short_sizes: Vec<u256>,
}

pub struct IncreasePositionReferral {
    account: Address,
    size_delta: u256,
    margin_fee_basis_points: u256,
    referral_code: b256,
    referrer: Address
}

pub struct DecreasePositionReferral {
    account: Address,
    size_delta: u256,
    margin_fee_basis_points: u256,
    referral_code: b256,
    referrer: Address
}

pub struct LeverageDecreased {
    collateral_delta: u256,
    prev_leverage: u256,
    next_leverage: u256
}