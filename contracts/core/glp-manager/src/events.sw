// SPDX-License-Identifier: Apache-2.0
library;

use helpers::context::*;

pub struct AddLiquidity {
    account: Account,
    asset: AssetId,
    amount: u64,
    aum_in_usdg: u256,
    glp_supply: u64,
    usdg_amount: u256,
    mint_amount: u256
}

pub struct RemoveLiquidity {
    account: Account,
    asset: AssetId,
    glp_amount: u64,
    aum_in_usdg: u256,
    glp_supply: u64,
    usdg_amount: u256,
    amount_out: u256
}