// SPDX-License-Identifier: Apache-2.0
library;

use helpers::signed_256::*;

pub struct BuyUSDG {
    account: Address,
    asset: AssetId,
    asset_amount: u64,
    usdg_amount: u256,
    fee_basis_points: u256,
}

pub struct SellUSDG {
    account: Address,
    asset: AssetId,
    asset_amount: u64,
    usdg_amount: u256,
    fee_basis_points: u256,
}

pub struct Swap {
    account: Address,
    asset_in: AssetId,
    asset_out: AssetId,
    amount_in: u256,
    amount_out: u256,
    amount_out_after_fees: u256,
    fee_basis_points: u256,
}

pub struct IncreasePosition {
    key: b256,
    account: Address,
    collateral_asset: AssetId,
    index_asset: AssetId,
    collateral_delta: u256,
    size_delta: u256,
    is_long: bool,
    price: u256,
    fee: u256,
}

pub struct DecreasePosition {
    key: b256,
    account: Address,
    collateral_asset: AssetId,
    index_asset: AssetId,
    collateral_delta: u256,
    size_delta: u256,
    is_long: bool,
    price: u256,
    fee: u256,
}

pub struct UpdatePosition {
    key: b256,
    size: u256,
    collateral: u256,
    average_price: u256,
    entry_funding_rate: u256,
    reserve_amount: u256,
    realized_pnl: Signed256,
    mark_price: u256,
}

pub struct ClosePosition {
    key: b256,
    size: u256,
    collateral: u256,
    average_price: u256,
    entry_funding_rate: u256,
    reserve_amount: u256,
    realized_pnl: Signed256,
}

pub struct LiquidatePosition {
    key: b256,
    account: Address,
    collateral_asset: AssetId,
    index_asset: AssetId,
    is_long: bool,
    size: u256,
    collateral: u256,
    reserve_amount: u256,
    realized_pnl: Signed256,
    mark_price: u256,
}

pub struct UpdateFundingRate {
    asset: AssetId,
    funding_rate: u256,
}

pub struct UpdatePnl {
    key: b256,
    has_profit: bool,
    delta: u256,
}

pub struct CollectSwapFees {
    asset: AssetId,
    fee_usd: u256,
    fee_assets: u64,
}

pub struct CollectMarginFees {
    asset: AssetId,
    fee_usd: u256,
    fee_assets: u256,
}

pub struct DirectPoolDeposit {
    asset: AssetId,
    amount: u256,
}

pub struct IncreasePoolAmount {
    asset: AssetId,
    amount: u256,
}

pub struct DecreasePoolAmount {
    asset: AssetId,
    amount: u256,
}

pub struct IncreaseUsdgAmount {
    asset: AssetId,
    amount: u256,
}

pub struct DecreaseUsdgAmount {
    asset: AssetId,
    amount: u256,
}

pub struct IncreaseReservedAmount {
    asset: AssetId,
    amount: u256,
}

pub struct DecreaseReservedAmount {
    asset: AssetId,
    amount: u256,
}

pub struct IncreaseGuaranteedAmount {
    asset: AssetId,
    amount: u256,
}

pub struct DecreaseGuaranteedAmount {
    asset: AssetId,
    amount: u256,
}
