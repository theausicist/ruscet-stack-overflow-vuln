// SPDX-License-Identifier: Apache-2.0
library;

use helpers::signed_256::*;

pub struct IncreaseUsdgAmount {
    asset: AssetId,
    amount: u256,
}

pub struct DecreaseUsdgAmount {
    asset: AssetId,
    amount: u256,
}
