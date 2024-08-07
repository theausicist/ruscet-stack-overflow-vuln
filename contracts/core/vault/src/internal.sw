// SPDX-License-Identifier: Apache-2.0
library;

use std::{
    block::timestamp,
    context::*,
    primitive_conversions::{
        u8::*,
        u64::*,
    }
};
use std::hash::*;
use core_interfaces::{
    vault_storage::{
        VaultStorage,
        Position,
        PositionKey,
    },
    vault_pricefeed::VaultPricefeed,
};
use asset_interfaces::usdg::USDG;
use helpers::{
    context::*,
    utils::*,
    transfer::transfer_assets,
    signed_256::*,
    zero::*
};
use ::constants::*;
use ::events::*;
use ::errors::*;

pub fn _get_position_key(
    account: Address,
    collateral_asset: AssetId,
    index_asset: AssetId,
    is_long: bool,
) -> b256 {
    keccak256(PositionKey {
        account,
        collateral_asset,
        index_asset,
        is_long,
    })
}

#[storage(read)]
pub fn _get_funding_fee(
    _account: Address,
    collateral_asset: AssetId,
    _index_asset: AssetId,
    _is_long: bool,
    size: u256,
    entry_funding_rate: u256,
    storj_: ContractId
) -> u256 {
    let storj = abi(VaultStorage, storj_.into());

    if size == 0 {
        return 0;
    }

    let mut funding_rate = storj.get_cumulative_funding_rates(collateral_asset);
    funding_rate = funding_rate - entry_funding_rate;
    if funding_rate == 0 {
        return 0;
    }

    size * funding_rate / FUNDING_RATE_PRECISION
}

#[storage(read)]
pub fn _get_position_fee(
    _account: Address,
    _collateral_asset: AssetId,
    _index_asset: AssetId,
    _is_long: bool,
    size_delta: u256,
    storj_: ContractId
) -> u256 {
    let storj = abi(VaultStorage, storj_.into());

    if size_delta == 0 {
        return 0;
    }

    let mut after_fee_usd = size_delta * (BASIS_POINTS_DIVISOR - storj.get_margin_fee_basis_points()).as_u256();
    after_fee_usd = after_fee_usd / BASIS_POINTS_DIVISOR.as_u256();

    size_delta - after_fee_usd
}

#[storage(read)]
pub fn _get_delta(
    index_asset: AssetId,
    size: u256,
    average_price: u256,
    is_long: bool,
    last_increased_time: u64,
    storj_: ContractId
) -> (bool, u256) {
    let storj = abi(VaultStorage, storj_.into());

    require(average_price > 0, Error::VaultInvalidAveragePrice);

    let price = if is_long {
        _get_min_price(index_asset, storj_)
    } else {
        _get_max_price(index_asset, storj_)
    };

    let price_delta = if average_price > price {
        average_price - price
    } else {
        price - average_price
    };

    let mut delta = size * price_delta / average_price;

    let mut has_profit = false;
    if is_long {
        has_profit = price > average_price;
    } else {
        has_profit = average_price > price;
    }

    // if the minProfitTime has passed then there will be no min profit threshold
    // the min profit threshold helps to prevent front-running issues
    let min_bps = if timestamp() > last_increased_time + storj.get_min_profit_time() {
        0
    } else {
        storj.get_min_profit_basis_points(index_asset)
    };

    if has_profit
        && (delta * BASIS_POINTS_DIVISOR.as_u256()) <= (size * min_bps.as_u256())
    {
        delta = 0;
    }
    (has_profit, delta)
}

#[storage(read)]
pub fn _get_max_price(asset: AssetId, storj_: ContractId) -> u256 {
    let storj = abi(VaultStorage, storj_.into());

    let vault_pricefeed = abi(VaultPricefeed, storj.get_pricefeed_provider().into());
    let include_amm_price = storj.get_include_amm_price();
    let use_swap_pricing = storj.get_use_swap_pricing();
    vault_pricefeed.get_price(
        asset, 
        true,
        include_amm_price,
        use_swap_pricing
    )
}

#[storage(read)]
pub fn _get_min_price(asset: AssetId, storj_: ContractId) -> u256 {
    let storj = abi(VaultStorage, storj_.into());

    let vault_pricefeed = abi(VaultPricefeed, storj.get_pricefeed_provider().into());
    let include_amm_price = storj.get_include_amm_price();
    let use_swap_pricing = storj.get_use_swap_pricing();
    vault_pricefeed.get_price(
        asset, 
        false,
        include_amm_price,
        use_swap_pricing
    )
}

#[storage(read)]
pub fn _validate_buffer_amount(asset: AssetId, storj_: ContractId) {
    let storj = abi(VaultStorage, storj_.into());

    let pool_amount = storj.get_pool_amounts(asset);
    let buffer_amount = storj.get_buffer_amounts(asset);

    if pool_amount < buffer_amount {
        require(false, Error::VaultPoolAmountLtBuffer);
    }
}

#[storage(read)]
pub fn _validate_router(account: Account, storj_: ContractId) {
    let storj = abi(VaultStorage, storj_.into());

    let sender = get_sender();

    if sender == account || sender == Account::from(storj.get_router()) {
        return;
    }

    require(
        storj.is_approved_router(account, sender),
        Error::VaultInvalidMsgCaller
    );
}

pub fn _validate_position(size: u256, collateral: u256) {
    if size == 0 {
        require(
            collateral == 0,
            Error::VaultCollateralShouldBeWithdrawn
        );
        return;
    }

    require(
        size >= collateral,
        Error::VaultSizeMustBeMoreThanCollateral
    );
}

#[storage(read)]
pub fn _validate_assets(
    collateral_asset: AssetId,
    index_asset: AssetId,
    is_long: bool,
    storj_: ContractId
) {
    let storj = abi(VaultStorage, storj_.into());

    if is_long {
        require(
            collateral_asset == index_asset,
            Error::VaultLongCollateralIndexAssetsMismatch
        );
        require(
            storj.is_asset_whitelisted(collateral_asset),
            Error::VaultLongCollateralAssetNotWhitelisted
        );
        require(
            !storj.is_stable_asset(collateral_asset),
            Error::VaultLongCollateralAssetMustNotBeStableAsset
        );

        return;
    }

    require(
        storj.is_asset_whitelisted(collateral_asset),
        Error::VaultShortCollateralAssetNotWhitelisted
    );
    require(
        storj.is_stable_asset(collateral_asset),
        Error::VaultShortCollateralAssetMustBeStableAsset
    );
    require(
        !storj.is_stable_asset(index_asset),
        Error::VaultShortIndexAssetMustNotBeStableAsset
    );
    require(
        storj.is_shortable_asset(index_asset),
        Error::VaultShortIndexAssetNotShortable
    );
}

// for longs:  next_average_price = (next_price * next_size) / (next_size + delta)
// for shorts: next_average_price = (next_price * next_size) / (next_size - delta)
#[storage(read)]
pub fn _get_next_average_price(
    index_asset: AssetId,
    size: u256,
    average_price: u256,
    is_long: bool,
    next_price: u256,
    size_delta: u256,
    last_increased_time: u64,
    storj_: ContractId
) -> u256 {
    let (has_profit, delta) = _get_delta(
        index_asset,
        size,
        average_price,
        is_long,
        last_increased_time,
        storj_
    );

    let next_size = size + size_delta;
    let mut divisor = 0;
    if is_long {
        divisor = if has_profit { next_size + delta } else { next_size - delta }
    } else {
        divisor = if has_profit { next_size - delta } else { next_size + delta }
    }

    next_price * next_size / divisor
}

// for longs:  next_average_price = (next_price * next_size) / (next_size + delta)
// for shorts: next_average_price = (next_price * next_size) / (next_size - delta)
#[storage(read)]
pub fn _get_next_global_short_average_price(
    index_asset: AssetId,
    next_price: u256,
    size_delta: u256,
    storj_: ContractId
) -> u256 {
    let storj = abi(VaultStorage, storj_.into());

    let size = storj.get_global_short_sizes(index_asset);
    let average_price = storj.get_global_short_average_prices(index_asset);
    let has_profit = average_price > next_price;

    let price_delta = if has_profit {
        average_price - next_price
    } else {
        next_price - average_price
    };

    let delta = size * price_delta / average_price;

    let next_size = size + size_delta;

    let divisor = if has_profit {
        next_size - delta
    } else {
        next_size + delta
    };

    next_price * next_size / divisor
}

#[storage(read, write)]
pub fn _collect_swap_fees(asset: AssetId, amount: u64, fee_basis_points: u64, storj_: ContractId) -> u64 {
    let storj = abi(VaultStorage, storj_.into());

    let after_fee_amount = amount * (BASIS_POINTS_DIVISOR - fee_basis_points) / BASIS_POINTS_DIVISOR;
    let fee_amount = amount - after_fee_amount;

    let fee_reserve = storj.get_fee_reserves(asset);
    storj.write_fee_reserves(asset, fee_reserve + fee_amount.as_u256());

    // log(CollectSwapFees {
    //     asset,
    //     fee_usd: _asset_to_usd_min(asset, fee_amount.as_u256()),
    //     fee_assets: fee_amount,
    // });

    after_fee_amount
}


#[storage(read)]
pub fn _get_swap_fee_basis_points(
    asset_in: AssetId,
    asset_out: AssetId,
    usdg_amount: u256,
    storj_: ContractId
) -> u256 {
    let storj = abi(VaultStorage, storj_.into());

    let is_stableswap = storj.is_stable_asset(asset_in) && storj.is_stable_asset(asset_out);

    let base_bps = if is_stableswap {
        storj.get_stable_swap_fee_basis_points()
    } else {
        storj.get_swap_fee_basis_points()
    };

    let tax_bps = if is_stableswap {
        storj.get_stable_tax_basis_points()
    } else {
        storj.get_tax_basis_points()
    };

    let fee_basis_points_0 = _get_fee_basis_points(
        asset_in,
        usdg_amount,
        base_bps.as_u256(),
        tax_bps.as_u256(),
        true,
        storj_
    );
    let fee_basis_points_1 = _get_fee_basis_points(
        asset_out,
        usdg_amount,
        base_bps.as_u256(),
        tax_bps.as_u256(),
        false,
        storj_
    );

    // use the higher of the two fee basis points
    if fee_basis_points_0 > fee_basis_points_1 {
        fee_basis_points_0
    } else {
        fee_basis_points_1
    }
}


// cases to consider
// 1. `initial_amount` is far from `target_amount`, action increases balance slightly => high rebate
// 2. `initial_amount` is far from `target_amount`, action increases balance largely => high rebate
// 3. `initial_amount` is close to `target_amount`, action increases balance slightly => low rebate
// 4. `initial_amount` is far from `target_amount`, action reduces balance slightly => high tax
// 5. `initial_amount` is far from `target_amount`, action reduces balance largely => high tax
// 6. `initial_amount` is close to `target_amount`, action reduces balance largely => low tax
// 7. `initial_amount` is above `target_amount`, nextAmount is below `target_amount` and vice versa
// 8. a large swap should have similar fees as the same trade split into multiple smaller swaps
#[storage(read)]
pub fn _get_fee_basis_points(
    asset: AssetId,
    usdg_delta: u256,
    fee_basis_points: u256,
    tax_basis_points: u256,
    should_increment: bool,
    storj_: ContractId
) -> u256 {
    let storj = abi(VaultStorage, storj_.into());

    if !storj.has_dynamic_fees() {
        return fee_basis_points;
    }

    let initial_amount = storj.get_usdg_amount(asset);
    let mut next_amount = initial_amount + usdg_delta;
    if !should_increment {
        next_amount = if usdg_delta > initial_amount {
            0
        } else {
            initial_amount - usdg_delta
        };
    }

    let target_amount = _get_target_usdg_amount(asset, storj_);
    if target_amount == 0 {
        return fee_basis_points;
    }

    let initial_diff = if initial_amount > target_amount {
        initial_amount - target_amount
    } else {
        target_amount - initial_amount
    };

    let next_diff = if next_amount > target_amount {
        next_amount - target_amount
    } else {
        target_amount - next_amount
    };

    // action improves relative asset balance
    if next_diff < initial_diff {
        let rebate_bps = tax_basis_points * initial_diff / target_amount;
        return if rebate_bps > fee_basis_points {
            0
        } else {
            fee_basis_points - rebate_bps
        };
    }

    let mut avg_diff = (initial_diff + next_diff) / 2;
    if avg_diff > target_amount {
        avg_diff = target_amount;
    }

    let tax_bps = tax_basis_points * avg_diff / target_amount;
    
    fee_basis_points + tax_bps
}

#[storage(read)]
pub fn _get_target_usdg_amount(asset: AssetId, storj_: ContractId) -> u256 {
    let storj = abi(VaultStorage, storj_.into());

    let supply = abi(USDG, storj.get_usdg_contr().into()).total_supply();
    if supply == 0 {
        return 0;
    }

    let weight = storj.get_asset_weight(asset);

    // @TODO: check if asset balance needs to be `u256`
    // @TODO: check if this return cast is needed
    (weight * supply / storj.get_total_asset_weights()).as_u256()
}