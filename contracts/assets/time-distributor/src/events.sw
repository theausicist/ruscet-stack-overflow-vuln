// SPDX-License-Identifier: Apache-2.0
library;

use helpers::context::*;

pub struct Distribute {
    receiver: Account,
    amount: u64
}

pub struct DistributionChange {
    receiver: Account,
    amount: u64,
    reward_asset: AssetId
}

pub struct AssetsPerIntervalChange {
    receiver: Account,
    amount: u64
}