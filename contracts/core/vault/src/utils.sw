// SPDX-License-Identifier: Apache-2.0
library;

use helpers::context::Account;

pub fn update_cumulative_funding_rate(
    _collateral_asset: AssetId,
    _index_asset: AssetId,
) -> bool {
    true
}

pub fn validate_increase_position(
    _account: Address,
    _collateral_asset: AssetId,
    _index_asset: AssetId,
    _size_delta: u256,
    _is_long: bool
) {
    // No additional validations
}

pub fn validate_decrease_position(
    _account: Address,
    _collateral_asset: AssetId,
    _index_asset: AssetId,
    _collateral_delta: u256,
    _size_delta: u256,
    _is_long: bool,
    _receiver: Account
) {
    // No additional validations
}
