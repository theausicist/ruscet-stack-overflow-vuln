// SPDX-License-Identifier: Apache-2.0
library;

use std::{
    block::timestamp,
    call_frames::{
        msg_asset_id,
    },
    context::*,
    revert::require,
    storage::storage_vec::*,
    math::*,
    primitive_conversions::{
        u8::*,
        u64::*,
    }
};
use helpers::context::Account;
use core_interfaces::{
    vault::Vault,
    vault_storage::{
        VaultStorage,
        Position,
        PositionKey,
    },
    vault_pricefeed::VaultPricefeed,
};
use asset_interfaces::usdg::USDG;
use ::events::*;
use ::constants::*;
use ::errors::*;

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

pub fn _sell_usdg(
    asset: AssetId, 
    receiver: Account,
    storj_: ContractId
) -> u256 {
    _validate_manager();
    
    let storj = abi(VaultStorage, storj_.into());
    
    require(
        storj.is_asset_whitelisted(asset),
        Error::VaultAssetNotWhitelisted
    );

    storj.write_use_swap_pricing(true);

    let usdg = storj.get_usdg();

    let usdg_amount = _transfer_in(usdg).as_u256();
    require(usdg_amount > 0, Error::VaultInvalidUsdgAmount);

    _update_cumulative_funding_rate(asset, asset);

    let redemption_amount = _get_redemption_amount(asset, usdg_amount);
    require(redemption_amount > 0, Error::VaultInvalidRedemptionAmount);

    _decrease_usdg_amount(asset, usdg_amount);
    _decrease_pool_amount(asset, redemption_amount);

    // require usdg_amount to be less than u64::max
    require(
        usdg_amount < u64::max().as_u256(),
        Error::VaultInvalidUSDGBurnAmountGtU64Max
    );

    let _amount = u64::try_from(usdg_amount).unwrap();

    abi(USDG, storj.get_usdg_contr().into()).burn{
        // @TODO: this is prob a buggy implementation of the USDG native asset? 
        asset_id: usdg.into(),
        coins: _amount
    }(
        Account::from(ContractId::this()),
        _amount
    );

    // the _transferIn call increased the value of tokenBalances[usdg]
    // usually decreases in token balances are synced by calling _transferOut
    // however, for UDFG, the assets are burnt, so _updateTokenBalance should
    // be manually called to record the decrease in assets
    _update_asset_balance(usdg);

    let fee_basis_points = _get_sell_usdg_fee_basis_points(
        asset,
        usdg_amount,
    );
    let amount_out = _collect_swap_fees(
        asset, 
        u64::try_from(redemption_amount).unwrap(), 
        u64::try_from(fee_basis_points).unwrap(), 
    );
    require(amount_out > 0, Error::VaultInvalidAmountOut);

    _transfer_out(asset, amount_out, receiver);

    // log(SellUSDG {
    //     account: Address::from(receiver.into()),
    //     asset,
    //     usdg_amount,
    //     asset_amount: amount_out,
    //     fee_basis_points,
    // });

    storj.write_use_swap_pricing(false);

    amount_out.as_u256()
}