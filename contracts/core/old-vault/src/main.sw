// SPDX-License-Identifier: Apache-2.0
contract;

mod events;
mod constants;
mod utils;
mod errors;

/*
__     __          _ _   
\ \   / /_ _ _   _| | |_ 
 \ \ / / _` | | | | | __|
  \ V / (_| | |_| | | |_ 
   \_/ \__,_|\__,_|_|\__|
*/

use std::{
    auth::msg_sender,
    block::timestamp,
    call_frames::{
        contract_id,
        msg_asset_id,
    },
    constants::BASE_ASSET_ID,
    context::*,
    revert::require,
    storage::storage_vec::*,
    asset::{
        force_transfer_to_contract,
        mint_to_address,
        transfer_to_address,
    },
    math::*,
    primitive_conversions::{
        u8::*,
        u64::*,
    }
};
use std::hash::*;
use helpers::{
    context::*, 
    utils::*,
    transfer::transfer_assets,
    signed_256::*,
    zero::*
};
use core_interfaces::{
    old_vault::OldVault,
    vault_storage::{
        Position,
        PositionKey
    },
    vault_pricefeed::VaultPricefeed,
};
use asset_interfaces::usdg::USDG;
use events::*;
use constants::*;
use errors::*;
use utils::{
    update_cumulative_funding_rate as utils_update_cumulative_funding_rate,
    validate_decrease_position as utils_validate_decrease_position,
    validate_increase_position as utils_validate_increase_position,
};

storage {
    // gov is not restricted to an `Address` (EOA) or a `Contract` (external)
    // because this can be either a regular EOA (Address) or a Multisig (Contract)
    gov: Account = ZERO_ACCOUNT,
    is_initialized: bool = false,
    is_swap_enabled: bool = true,
    is_leverage_enabled: bool = true,
    has_dynamic_fees: bool = false,
    include_amm_price: bool = true,
    use_swap_pricing: bool = true,
    min_profit_time: u64 = 0,
    max_leverage: u64 = 50 * 10000, // 50%

    // Fees
    liquidation_fee_usd: u256 = 0,
    tax_basis_points: u64 = 50, // 0.5%
    stable_tax_basis_points: u64 = 20, // 0.2%
    mint_burn_fee_basis_points: u64 = 30, // 0.3%
    swap_fee_basis_points: u64 = 30, // 0.3%
    stable_swap_fee_basis_points: u64 = 4, // 0.04%
    margin_fee_basis_points: u64 = 10, // 0.1%

    // Externals
    error_controller: Address = ZERO_ADDRESS,
    router: ContractId = ZERO_CONTRACT,
    // this is the USDG contract
    usdg_contr: ContractId = ZERO_CONTRACT,
    // this is the USDG native asset (AssetId::new(usdg_contr, ZERO))
    usdg: AssetId = ZERO_ASSET,
    pricefeed_provider: ContractId = ZERO_CONTRACT,

    // Funding
    funding_interval: u64 = 8 * 3600, // 8 hours
    funding_rate_factor: u64 = 0,
    stable_funding_rate_factor: u64 = 0,
    total_asset_weights: u64 = 0,

    // Admin
    in_manager_mode: bool = false,
    in_private_liquidation_mode: bool = false,

    // Misc
    approved_routers: StorageMap<Account, StorageMap<Account, bool>> = 
        StorageMap::<Account, StorageMap<Account, bool>> {},
    is_liquidator: StorageMap<Account, bool> = StorageMap::<Account, bool> {},
    is_manager: StorageMap<Account, bool> = StorageMap::<Account, bool> {},

    whitelisted_asset_count: u64 = 0,
    all_whitelisted_assets: StorageVec<AssetId> = StorageVec {},

    whitelisted_assets: StorageMap<AssetId, bool> = StorageMap::<AssetId, bool> {},
    asset_decimals: StorageMap<AssetId, u8> = StorageMap::<AssetId, u8> {},
    min_profit_basis_points: StorageMap<AssetId, u64> = StorageMap::<AssetId, u64> {},
    stable_assets: StorageMap<AssetId, bool> = StorageMap::<AssetId, bool> {},
    shortable_assets: StorageMap<AssetId, bool> = StorageMap::<AssetId, bool> {},

    // used only to determine _transfer_in values
    asset_balances: StorageMap<AssetId, u64> = StorageMap::<AssetId, u64> {},
    // allows customisation of index composition
    asset_weights: StorageMap<AssetId, u64> = StorageMap::<AssetId, u64> {},
    // tracks amount of USDG debt for each supported asset
    usdg_amounts: StorageMap<AssetId, u256> = StorageMap::<AssetId, u256> {},
    // allows setting a max amount of USDG debt for an asset
    max_usdg_amounts: StorageMap<AssetId, u256> = StorageMap::<AssetId, u256> {},
    // tracks the number of received tokens that can be used for leverage
    // tracked separately from asset_balances to exclude funds that are deposited 
    // as margin collateral
    pool_amounts: StorageMap<AssetId, u256> = StorageMap::<AssetId, u256> {},
    // tracks the number of tokens reserved for open leverage positions
    reserved_amounts: StorageMap<AssetId, u256> = StorageMap::<AssetId, u256> {},
    // allows specification of an amount to exclude from swaps
    // can be used to ensure a certain amount of liquidity is available for leverage positions
    buffer_amounts: StorageMap<AssetId, u256> = StorageMap::<AssetId, u256> {},
    // tracks the amount of USD that is "guaranteed" by opened leverage positions
    // this value is used to calculate the redemption values for selling of USDG
    // this is an estimated amount, it is possible for the actual guaranteed value to be lower
    // in the case of sudden price decreases, the guaranteed value should be corrected
    // after liquidations are carried out
    guaranteed_usd: StorageMap<AssetId, u256> = StorageMap::<AssetId, u256> {},
    // tracks the funding rates based on utilization
    cumulative_funding_rates: StorageMap<AssetId, u256> = StorageMap::<AssetId, u256> {},
    // tracks the last time funding was updated for a token
    last_funding_times: StorageMap<AssetId, u64> = StorageMap::<AssetId, u64> {},
    // tracks all open Positions
    positions: StorageMap<b256, Position> = StorageMap::<b256, Position> {},
    // tracks amount of fees per asset
    fee_reserves: StorageMap<AssetId, u256> = StorageMap::<AssetId, u256> {},
    global_short_sizes: StorageMap<AssetId, u256> = StorageMap::<AssetId, u256> {},
    global_short_average_prices: StorageMap<AssetId, u256> = StorageMap::<AssetId, u256> {},
    max_global_short_sizes: StorageMap<AssetId, u256> = StorageMap::<AssetId, u256> {},
}

impl OldVault for Contract {
    #[storage(read, write)]
    fn initialize(
        gov: Address,
        router: ContractId,
        usdg: AssetId,
        usdg_contr: ContractId,
        pricefeed_provider: ContractId,
        liquidation_fee_usd: u256,
        funding_rate_factor: u64,
        stable_funding_rate_factor: u64,
    ) {
        require(!storage.is_initialized.read(), Error::VaultAlreadyInitialized);
        storage.is_initialized.write(true);
        storage.gov.write(Account::from(gov));

        require(
            usdg == AssetId::new(usdg_contr, ZERO),
            Error::VaultInvalidUSDGAsset
        );

        storage.router.write(router);
        storage.usdg.write(usdg);
        storage.usdg_contr.write(usdg_contr);
        storage.pricefeed_provider.write(pricefeed_provider);
        storage.liquidation_fee_usd.write(liquidation_fee_usd);
        storage.funding_rate_factor.write(funding_rate_factor);
        storage.stable_funding_rate_factor.write(stable_funding_rate_factor);
    }

    /*
          ____     _       _           _       
         / / /    / \   __| |_ __ ___ (_)_ __  
        / / /    / _ \ / _` | '_ ` _ \| | '_ \ 
       / / /    / ___ \ (_| | | | | | | | | | |
      /_/_/    /_/   \_\__,_|_| |_| |_|_|_| |_|                         
    */
    #[storage(write)]
    fn set_manager(manager: Account, is_manager: bool) {
        _only_gov();
        storage.is_manager.insert(manager, is_manager)
    }

    #[storage(write)]
    fn set_liquidator(liquidator: Account, is_active: bool) {
        _only_gov();
        storage.is_liquidator.insert(liquidator, is_active)
    }

    #[storage(write)]
    fn set_gov(gov: Account) {
        _only_gov();
        storage.gov.write(gov);
    }

    #[storage(write)]
    fn set_in_manager_mode(mode: bool) {
        _only_gov();
        storage.in_manager_mode.write(mode);
    }

    #[storage(write)]
    fn set_in_private_liquidation_mode(mode: bool) {
        _only_gov();
        storage.in_private_liquidation_mode.write(mode);
    }

    #[storage(write)]
    fn set_is_swap_enabled(is_swap_enabled: bool) {
        _only_gov();
        storage.is_swap_enabled.write(is_swap_enabled);
    }

    #[storage(write)]
    fn set_is_leverage_enabled(is_leverage_enabled: bool) {
        _only_gov();
        storage.is_leverage_enabled.write(is_leverage_enabled);
    }

    #[storage(write)]
    fn set_pricefeed(pricefeed: ContractId) {
        _only_gov();
        storage.pricefeed_provider.write(pricefeed);
    }

    #[storage(write)]
    fn set_max_leverage(max_leverage: u64) {
        _only_gov();
        storage.max_leverage.write(max_leverage);
    }

    #[storage(write)]
    fn set_buffer_amount(asset: AssetId, buffer_amount: u256) {
        _only_gov();
        storage.buffer_amounts.insert(asset, buffer_amount);
    }

    #[storage(write)]
    fn set_max_global_short_size(asset: AssetId, amount: u256) {
        _only_gov();
        storage.max_global_short_sizes.insert(asset, amount);
    }

    #[storage(read, write)]
    fn set_fees(
        tax_basis_points: u64,
        stable_tax_basis_points: u64,
        mint_burn_fee_basis_points: u64,
        swap_fee_basis_points: u64,
        stable_swap_fee_basis_points: u64,
        margin_fee_basis_points: u64,
        liquidation_fee_usd: u256,
        min_profit_time: u64,
        has_dynamic_fees: bool,
    ) {
        _only_gov();
        require(tax_basis_points <= MAX_FEE_BASIS_POINTS, Error::VaultInvalidTaxBasisPoints);
        require(stable_tax_basis_points <= MAX_FEE_BASIS_POINTS, Error::VaultInvalidStableTaxBasisPoints);
        require(mint_burn_fee_basis_points <= MAX_FEE_BASIS_POINTS, Error::VaultInvalidMintBurnFeeBasisPoints);
        require(swap_fee_basis_points <= MAX_FEE_BASIS_POINTS, Error::VaultInvalidSwapFeeBasisPoints);
        require(stable_swap_fee_basis_points <= MAX_FEE_BASIS_POINTS, Error::VaultInvalidStableSwapFeeBasisPoints);
        require(margin_fee_basis_points <= MAX_FEE_BASIS_POINTS, Error::VaultInvalidMarginFeeBasisPoints);
        require(liquidation_fee_usd <= MAX_LIQUIDATION_FEE_USD, Error::VaultInvalidLiquidationFeeUsd);

        storage.tax_basis_points.write(tax_basis_points);
        storage.stable_tax_basis_points.write(stable_tax_basis_points);
        storage.mint_burn_fee_basis_points.write(mint_burn_fee_basis_points);
        storage.swap_fee_basis_points.write(swap_fee_basis_points);
        storage.stable_swap_fee_basis_points.write(stable_swap_fee_basis_points);
        storage.margin_fee_basis_points.write(margin_fee_basis_points);
        storage.liquidation_fee_usd.write(liquidation_fee_usd);
        storage.min_profit_time.write(min_profit_time);
        storage.has_dynamic_fees.write(has_dynamic_fees);
    }

    #[storage(read, write)]
    fn set_funding_rate(
        funding_interval: u64,
        funding_rate_factor: u64,
        stable_funding_rate_factor: u64,
    ) {
        _only_gov();
        require(funding_interval >= MIN_FUNDING_RATE_INTERVAL, Error::VaultInvalidFundingInterval);
        require(funding_rate_factor <= MAX_FUNDING_RATE_FACTOR, Error::VaultInvalidFundingRateFactor);
        require(stable_funding_rate_factor <= MAX_FUNDING_RATE_FACTOR, Error::VaultInvalidStableFundingRateFactor);

        storage.funding_interval.write(funding_interval);
        storage.funding_rate_factor.write(funding_rate_factor);
        storage.stable_funding_rate_factor.write(stable_funding_rate_factor);
    }

    #[storage(read, write)]
    fn withdraw_fees(asset: AssetId, receiver: Account) -> u64 {
        _only_gov();
        // @TODO: potential revert here
        let amount = u64::try_from(storage.fee_reserves.get(asset).try_read().unwrap_or(0)).unwrap();
        if amount == 0 {
            return 0;
        }

        storage.fee_reserves.insert(asset, 0);
        _transfer_out(asset, amount, receiver);

        amount
    }

    #[storage(read, write)]
    fn set_asset_config(
        asset: AssetId,
        asset_decimals: u8,
        asset_weight: u64,
        min_profit_bps: u64,
        max_usdg_amount: u256,
        is_stable: bool,
        is_shortable: bool
    ) {
        _only_gov();

        require(
            asset.non_zero(),
            Error::VaultZeroAsset
        );

        // increment token count for the first time
        if !storage.whitelisted_assets.get(asset).try_read().unwrap_or(false) {
            storage.whitelisted_asset_count.write(storage.whitelisted_asset_count.read() + 1);
            storage.all_whitelisted_assets.push(asset);
        }

        let total_asset_weights = storage.total_asset_weights.read() - storage.asset_weights.get(asset).try_read().unwrap_or(0);

        storage.whitelisted_assets.insert(asset, true);
        storage.asset_decimals.insert(asset, asset_decimals);
        storage.asset_weights.insert(asset, asset_weight);
        storage.min_profit_basis_points.insert(asset, min_profit_bps);
        storage.max_usdg_amounts.insert(asset, max_usdg_amount);
        storage.stable_assets.insert(asset, is_stable);
        storage.shortable_assets.insert(asset, is_shortable);

        storage.total_asset_weights.write(total_asset_weights + asset_weight);

        // validate pricefeed
        _get_max_price(asset);
    }

    #[storage(read, write)]
    fn clear_asset_config(asset: AssetId) {
        _only_gov();

        require(
            storage.whitelisted_assets.get(asset).try_read().unwrap_or(false),
            Error::VaultAssetNotWhitelisted
        );

        // `asset_weights` is guaranteed to have a value, hence no need to gracefully unwrap
        storage.total_asset_weights.write(storage.total_asset_weights.read() - storage.asset_weights.get(asset).read());

        storage.whitelisted_assets.remove(asset);
        storage.asset_decimals.remove(asset);
        storage.asset_weights.remove(asset);
        storage.min_profit_basis_points.remove(asset);
        storage.max_usdg_amounts.remove(asset);
        storage.stable_assets.remove(asset);
        storage.shortable_assets.remove(asset);

        storage.whitelisted_asset_count.write(storage.whitelisted_asset_count.read() - 1);
    }

    #[storage(write)]
    fn set_router(router: Account, is_active: bool) {
        storage.approved_routers.get(get_sender()).insert(router, is_active);
    }

    #[storage(write)]
    fn set_usdg_amount(asset: AssetId, amount: u256) {
        _only_gov();

        let usdg_amount = storage.usdg_amounts.get(asset).try_read().unwrap_or(0);
        if amount > usdg_amount {
            _increase_usdg_amount(asset, amount - usdg_amount);
        } else {
            _decrease_usdg_amount(asset, usdg_amount - amount);
        }
    }

    #[storage(read)]
    fn upgrade_vault(new_vault: ContractId, asset: AssetId, amount: u64) {
        _only_gov();

        force_transfer_to_contract(new_vault, asset, amount);
    }

    /*
          ____ __     ___               
         / / / \ \   / (_) _____      __
        / / /   \ \ / /| |/ _ \ \ /\ / /
       / / /     \ V / | |  __/\ V  V / 
      /_/_/       \_/  |_|\___| \_/\_/  
    */
    #[storage(read)]
    fn get_position(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
    ) -> (
        u256, u256, u256,
        u256, u256, Signed256,
        bool, u64,
        Position
    ) {
        let position_key = _get_position_key(
            account, 
            collateral_asset, 
            index_asset, 
            is_long
        );

        let position = storage.positions.get(position_key).try_read().unwrap_or(Position::default());
        (
            position.size, // 0
            position.collateral, // 1
            position.average_price, // 2
            position.entry_funding_rate, // 3
            position.reserve_amount, // 4
            position.realized_pnl, // 5
            // position.realized_pnl >= 0, // 6
            !position.realized_pnl.is_neg, // 6
            position.last_increased_time, // 7
            position
        )
    }

    fn get_position_key(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
    ) -> b256 {
        _get_position_key(
            account,
            collateral_asset,
            index_asset,
            is_long
        )
    }

    #[storage(read)]
    fn get_position_delta(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
    ) -> (bool, u256) {
        _get_position_delta(
            account,
            collateral_asset,
            index_asset,
            is_long
        )
    }

    #[storage(read)]
    fn get_delta(
        index_asset: AssetId,
        size: u256,
        average_price: u256,
        is_long: bool,
        last_increased_time: u64,
    ) -> (bool, u256) {
        _get_delta(
            index_asset,
            size,
            average_price,
            is_long,
            last_increased_time
        )
    }

    #[storage(read)]
    fn get_entry_funding_rate(
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
    ) -> u256 {
        _get_entry_funding_rate(
            collateral_asset,
            index_asset,
            is_long
        )
    }

    #[storage(read)]
    fn get_funding_fee(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
        size: u256,
        entry_funding_rate: u256,
    ) -> u256 {
        _get_funding_fee(
            account,
            collateral_asset,
            index_asset,
            is_long,
            size,
            entry_funding_rate
        )
    }

    #[storage(read)]
    fn get_position_fee(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
        size_delta: u256,
    ) -> u256 {
        _get_position_fee(
            account,
            collateral_asset,
            index_asset,
            is_long,
            size_delta
        )
    }

    #[storage(read)]
    fn get_global_short_sizes(asset: AssetId) -> u256 {
        storage.global_short_sizes.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_global_short_average_prices(asset: AssetId) -> u256 {
        storage.global_short_average_prices.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_guaranteed_usd(asset: AssetId) -> u256 {
        storage.guaranteed_usd.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_max_price(asset: AssetId) -> u256 {
        _get_max_price(asset)
    }

    #[storage(read)]
    fn get_min_price(asset: AssetId) -> u256 {
        _get_min_price(asset)
    }

    #[storage(read)]
    fn asset_to_usd_min(asset: AssetId, asset_amount: u256) -> u256 {
        _asset_to_usd_min(asset, asset_amount)
    }

    #[storage(read)]
    fn usd_to_asset_max(asset: AssetId, usd_amount: u256) -> u256 {
        _usd_to_asset_max(asset, usd_amount)
    }

    #[storage(read)]
    fn usd_to_asset_min(asset: AssetId, usd_amount: u256) -> u256 {
        _usd_to_asset_min(asset, usd_amount)
    }

    #[storage(read)]
    fn usd_to_asset(asset: AssetId, usd_amount: u256, price: u256) -> u256 {
        _usd_to_asset(asset, usd_amount, price)
    }

    #[storage(read)]
    fn get_pool_amounts(asset: AssetId) -> u256 {
        storage.pool_amounts.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_fee_reserves(asset: AssetId) -> u256 {
        storage.fee_reserves.get(asset).try_read().unwrap_or(0)
    }
    
    #[storage(read)]
    fn get_reserved_amounts(asset: AssetId) -> u256 {
        storage.reserved_amounts.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_usdg_amounts(asset: AssetId) -> u256 {
        storage.usdg_amounts.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_max_usdg_amounts(asset: AssetId) -> u256 {
        storage.max_usdg_amounts.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_buffer_amounts(asset: AssetId) -> u256 {
        storage.buffer_amounts.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_asset_weights(asset: AssetId) -> u64 {
        storage.asset_weights.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_redemption_amount(
        asset: AssetId, 
        usdg_amount: u256
    ) -> u256 {
        _get_redemption_amount(asset, usdg_amount)
    }

    #[storage(read)]
    fn get_redemption_collateral(asset: AssetId) -> u256 {
        _get_redemption_collateral(asset)
    }

    #[storage(read)]
    fn get_redemption_collateral_usd(asset: AssetId) -> u256 {
        _asset_to_usd_min(
            asset,
            _get_redemption_collateral(asset)
        )
    }

    #[storage(read)]
    fn get_pricefeed_provider() -> ContractId {
        storage.pricefeed_provider.try_read().unwrap_or(ZERO_CONTRACT)
    }

    #[storage(read)]
    fn get_all_whitelisted_assets_length() -> u64 {
        storage.all_whitelisted_assets.len()
    }

    #[storage(read)]
    fn get_whitelisted_asset_by_index(index: u64) -> AssetId {
        if index >= storage.all_whitelisted_assets.len() {
            return ZERO_ASSET;
        }

        storage.all_whitelisted_assets.get(index).unwrap().read()
    }

    #[storage(read)]
    fn is_asset_whitelisted(asset: AssetId) -> bool {
        storage.whitelisted_assets.get(asset).try_read().unwrap_or(false)
    }

    #[storage(read)]
    fn get_asset_decimals(asset: AssetId) -> u8 {
        storage.asset_decimals.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn is_stable_asset(asset: AssetId) -> bool {
        storage.stable_assets.get(asset).try_read().unwrap_or(false)
    }

    #[storage(read)]
    fn is_shortable_asset(asset: AssetId) -> bool {
        storage.shortable_assets.get(asset).try_read().unwrap_or(false)
    }

    #[storage(read)]
    fn get_position_leverage(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
    ) -> u256 {
        let position_key = _get_position_key(
            account, 
            collateral_asset, 
            index_asset, 
            is_long
        );
        let position = storage.positions.get(position_key).try_read().unwrap_or(Position::default());
        require(
            position.collateral > 0,
            Error::VaultInvalidPosition
        );

        position.size * BASIS_POINTS_DIVISOR.as_u256() / position.collateral
    }

    #[storage(read)]
    fn get_cumulative_funding_rate(asset: AssetId) -> u256 {
        storage.cumulative_funding_rates.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_fee_basis_points(
        asset: AssetId,
        usdg_delta: u256,
        fee_basis_points: u256,
        tax_basis_points: u256,
        increment: bool
    ) -> u256 {
        _get_fee_basis_points(
            asset,
            usdg_delta,
            fee_basis_points,
            tax_basis_points,
            increment,
        )
    }

    #[storage(read)]
    fn get_liquidation_fee_usd() -> u256 {
        storage.liquidation_fee_usd.read()
    }

    #[storage(read)]
    fn get_tax_basis_points() -> u64 {
        storage.tax_basis_points.read()
    }

    #[storage(read)]
    fn get_stable_tax_basis_points() -> u64 {
        storage.stable_tax_basis_points.read()
    }

    #[storage(read)]
    fn get_mint_burn_fee_basis_points() -> u64 {
        storage.mint_burn_fee_basis_points.read()
    }

    #[storage(read)]
    fn get_swap_fee_basis_points() -> u64 {
        storage.swap_fee_basis_points.read()
    }

    #[storage(read)]
    fn get_stable_swap_fee_basis_points() -> u64 {
        storage.stable_swap_fee_basis_points.read()
    }

    #[storage(read)]
    fn get_margin_fee_basis_points() -> u64 {
        storage.margin_fee_basis_points.read()
    }

    #[storage(read)]
    fn get_min_profit_time() -> u64 {
        storage.min_profit_time.read()
    }

    #[storage(read)]
    fn get_has_dynamic_fees() -> bool {
        storage.has_dynamic_fees.read()
    }

    #[storage(read)]
    fn get_target_usdg_amount(asset: AssetId) -> u256 {
        _get_target_usdg_amount(asset)
    }

    #[storage(read)]
    fn get_utilization(asset: AssetId) -> u256 {
        let pool_amount = storage.pool_amounts.get(asset).try_read().unwrap_or(0);
        if pool_amount == 0 {
            return 0;
        }

        let reserved_amount = storage.reserved_amounts.get(asset).try_read().unwrap_or(0);
        
        reserved_amount * FUNDING_RATE_PRECISION / pool_amount
    }

    #[storage(read)]
    fn get_global_short_delta(asset: AssetId) -> (bool, u256) {
        _get_global_short_delta(asset)
    }

    #[storage(read)]
    fn is_liquidator(account: Account) -> bool {
        storage.is_liquidator.get(account).try_read().unwrap_or(false)
    }

    #[storage(read)]
    fn is_in_private_liquidation_mode() -> bool {
        storage.in_private_liquidation_mode.read()
    }

    #[storage(read)]
    fn validate_liquidation(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
        should_raise: bool,
    ) -> (u256, u256) {
        _validate_liquidation(
            account,
            collateral_asset,
            index_asset,
            is_long,
            should_raise
        )
    }

    /*
          ____  ____        _     _ _      
         / / / |  _ \ _   _| |__ | (_) ___ 
        / / /  | |_) | | | | '_ \| | |/ __|
       / / /   |  __/| |_| | |_) | | | (__ 
      /_/_/    |_|    \__,_|_.__/|_|_|\___|
    */
    #[storage(read, write)]
    fn update_cumulative_funding_rate(collateral_asset: AssetId, index_asset: AssetId) {
        _update_cumulative_funding_rate(collateral_asset, index_asset);
    }

    #[payable]
    #[storage(read, write)]
    fn direct_pool_deposit(asset: AssetId) {
        // deposit into the pool without minting USDG tokens
        // useful in allowing the pool to become over-collaterised
        require(
            storage.whitelisted_assets.get(asset).try_read().unwrap_or(false),
            Error::VaultAssetNotWhitelisted
        );

        let amount = _transfer_in(asset).as_u256();
        // @TODO: check this
        require(amount > 0, Error::VaultInvalidAssetAmount);
        _increase_pool_amount(asset, amount);

        // log(DirectPoolDeposit {
        //     asset: asset,
        //     amount: amount,
        // });
    }

    #[storage(read, write)]
    fn buy_usdg(asset: AssetId, receiver: Account) -> u256 {
        _validate_manager();
        require(
            storage.whitelisted_assets.get(asset).try_read().unwrap_or(false),
            Error::VaultAssetNotWhitelisted
        );

        storage.use_swap_pricing.write(true);

        let asset_amount = _transfer_in(asset);
        require(asset_amount > 0, Error::VaultInvalidAssetAmount);

        _update_cumulative_funding_rate(asset, asset);

        let price = _get_min_price(asset);

        let mut usdg_amount = asset_amount.as_u256() * price / PRICE_PRECISION;
        usdg_amount = _adjust_for_decimals(usdg_amount, asset, storage.usdg.read());
        require(usdg_amount > 0, Error::VaultInvalidUsdgAmount);

        let fee_basis_points = _get_buy_usdg_fee_basis_points(
            asset,
            usdg_amount
        );

        let amount_after_fees = 
            _collect_swap_fees(asset, asset_amount, u64::try_from(fee_basis_points).unwrap()).as_u256();

        let mut mint_amount = amount_after_fees * price / PRICE_PRECISION;
        mint_amount = _adjust_for_decimals(mint_amount, asset, storage.usdg.read());

        _increase_usdg_amount(asset, mint_amount);
        _increase_pool_amount(asset, amount_after_fees);

        // require usdg_amount to be less than u64::max
        require(
            mint_amount < u64::max().as_u256(),
            Error::VaultInvalidMintAmountGtU64Max
        );

        let usdg = abi(USDG, storage.usdg_contr.read().into());
        usdg.mint(
            receiver,
            u64::try_from(mint_amount).unwrap()
        );

        // log(BuyUSDG {
        //     account: Address::from(receiver.into()),
        //     asset,
        //     asset_amount,
        //     usdg_amount: mint_amount,
        //     fee_basis_points,
        // });

        storage.use_swap_pricing.write(false);

        mint_amount
    }

    #[storage(read, write)]
    fn sell_usdg(asset: AssetId, receiver: Account) -> u256 {
        _validate_manager();
        require(
            storage.whitelisted_assets.get(asset).try_read().unwrap_or(false),
            Error::VaultAssetNotWhitelisted
        );

        storage.use_swap_pricing.write(true);

        let usdg = storage.usdg.read();

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

        abi(USDG, storage.usdg_contr.read().into()).burn{
            // @TODO: this is prob a buggy implementation of the USDG native asset? 
            asset_id: storage.usdg.read().into(),
            coins: _amount
        }(
            Account::from(contract_id()),
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

        storage.use_swap_pricing.write(false);

        amount_out.as_u256()
    }

    #[payable]
    #[storage(read, write)]
    fn swap(
        asset_in: AssetId,
        asset_out: AssetId,
        receiver: Account
    ) -> u64 {
        require(
            storage.is_swap_enabled.read() == true,
            Error::VaultSwapsNotEnabled
        );
        require(
            storage.whitelisted_assets.get(asset_in).try_read().unwrap_or(false),
            Error::VaultAssetInNotWhitelisted
        );
        require(
            storage.whitelisted_assets.get(asset_out).try_read().unwrap_or(false),
            Error::VaultAssetOutNotWhitelisted
        );
        require(asset_in != asset_out, Error::VaultAssetsAreEqual);

        storage.use_swap_pricing.write(true);

        _update_cumulative_funding_rate(asset_in, asset_in);
        _update_cumulative_funding_rate(asset_out, asset_out);

        let amount_in = _transfer_in(asset_in).as_u256();
        require(amount_in > 0, Error::VaultInvalidAmountIn);

        let price_in = _get_min_price(asset_in);
        let price_out = _get_max_price(asset_out);

        let mut amount_out = amount_in * price_in / price_out;
        amount_out = _adjust_for_decimals(amount_out, asset_in, asset_out);

        // adjust usdgAmounts by the same usdgAmount as debt is shifted between the assets
        let mut usdg_amount = amount_in * price_in / PRICE_PRECISION;
        usdg_amount = _adjust_for_decimals(usdg_amount, asset_in, storage.usdg.read());

        let fee_basis_points = _get_swap_fee_basis_points(
            asset_in, 
            asset_out, 
            usdg_amount,
        );

        let amount_out_after_fees = _collect_swap_fees(
            asset_out, 
            u64::try_from(amount_out).unwrap(),
            u64::try_from(fee_basis_points).unwrap()
        );

        _increase_usdg_amount(asset_in, usdg_amount);
        _decrease_usdg_amount(asset_out, usdg_amount);

        _increase_pool_amount(asset_in, amount_in);
        _decrease_pool_amount(asset_out, amount_out);

        _validate_buffer_amount(asset_out);

        _transfer_out(asset_out, amount_out_after_fees, receiver);

        // log(Swap {
        //     account: Address::from(receiver.into()),
        //     asset_in,
        //     asset_out,
        //     amount_in,
        //     amount_out,
        //     amount_out_after_fees: amount_out_after_fees.as_u256(),
        //     fee_basis_points,
        // });

        storage.use_swap_pricing.write(false);

        amount_out_after_fees
    }

    #[payable]
    #[storage(read, write)]
    fn increase_position(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        size_delta: u256,
        is_long: bool,
    ) {
        require(
            storage.is_leverage_enabled.read(),
            Error::VaultLeverageNotEnabled
        );
        _validate_router(Account::from(account));
        _validate_assets(collateral_asset, index_asset, is_long);

        utils_validate_increase_position(
            account,
            collateral_asset,
            index_asset,
            size_delta,
            is_long 
        );

        _update_cumulative_funding_rate(collateral_asset, index_asset);

        let position_key = _get_position_key(
            account, 
            collateral_asset, 
            index_asset, 
            is_long
        );

        let mut position = storage.positions.get(position_key).try_read().unwrap_or(Position::default());

        let price = if is_long {
            _get_max_price(index_asset)
        } else {
            _get_min_price(index_asset)
        };

        if position.size == 0 {
            position.average_price = price;
        }

        if position.size > 0 && size_delta > 0 {
            position.average_price = _get_next_average_price(
                index_asset,
                position.size,
                position.average_price,
                is_long,
                price,
                size_delta,
                position.last_increased_time
            );
        }

        let fee = _collect_margin_fees(
            account,
            collateral_asset,
            index_asset,
            is_long,
            size_delta,
            position.size,
            position.entry_funding_rate,
        );

        let collateral_delta = _transfer_in(collateral_asset).as_u256();
        let collateral_delta_usd = _asset_to_usd_min(collateral_asset, collateral_delta);

        position.collateral = position.collateral + collateral_delta_usd;

        require(
            position.collateral >= fee,
            Error::VaultInsufficientCollateralForFees
        );
        position.collateral = position.collateral - fee;
        position.entry_funding_rate = _get_entry_funding_rate(
            collateral_asset,
            index_asset,
            is_long
        );
        position.size = position.size + size_delta;
        position.last_increased_time = timestamp();

        require(
            position.size > 0,
            Error::VaultInvalidPositionSize
        );

        _validate_position(position.size, position.collateral);
        // we need to have a storage write here because _validate_liquidation constructs the position key and 
        // validates the average_price. If not for this position write, it would receive a stale avg price (could be 0)
        storage.positions.insert(position_key, position);
        _validate_liquidation(
            account,
            collateral_asset,
            index_asset,
            is_long,
            true 
        );

        // reserve assets to pay profits on the position
        let reserve_delta = _usd_to_asset_max(collateral_asset, size_delta);
        position.reserve_amount = position.reserve_amount + reserve_delta;
        _increase_reserved_amount(collateral_asset, reserve_delta);

        if is_long {
            // guaranteed_usd stores the sum of (position.size - position.collateral) for all positions
            // if a fee is charged on the collateral then guaranteed_usd should be increased by that 
            // fee amount since (position.size - position.collateral) would have increased by `fee`
            _increase_guaranteed_usd(collateral_asset, size_delta + fee);
            _decrease_guaranteed_usd(collateral_asset, collateral_delta_usd);

            // treat the deposited collateral as part of the pool
            _increase_pool_amount(collateral_asset, collateral_delta);

            // fees need to be deducted from the pool since fees are deducted from position.collateral
            // and collateral is treated as part of the pool
            _decrease_pool_amount(collateral_asset, _usd_to_asset_min(collateral_asset, fee));
        } else {
            let global_short_size = storage.global_short_sizes.get(index_asset).try_read().unwrap_or(0);
            if global_short_size == 0 {
                storage.global_short_average_prices.insert(index_asset, price);
            } else {
                let new_price = _get_next_global_short_average_price(
                    index_asset,
                    price,
                    size_delta
                );

                storage.global_short_average_prices.insert(index_asset, new_price);
            }

            _increase_global_short_size(index_asset, size_delta);
        }
 
        // log(IncreasePosition {
        //     key: position_key,
        //     account,
        //     collateral_asset,
        //     index_asset,
        //     collateral_delta: collateral_delta_usd,
        //     size_delta,
        //     is_long,
        //     price,
        //     fee,
        // });
        // log(UpdatePosition {
        //     key: position_key,
        //     size: position.size,
        //     collateral: position.collateral,
        //     average_price: position.average_price,
        //     entry_funding_rate: position.entry_funding_rate,
        //     reserve_amount: position.reserve_amount,
        //     realized_pnl: position.realized_pnl,
        //     mark_price: price,
        // });

        storage.positions.insert(position_key, position);
    }

    #[storage(read, write)]
    fn decrease_position(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        collateral_delta: u256,
        size_delta: u256,
        is_long: bool,
        receiver: Account
    ) -> u256 {
        _validate_router(Account::from(account));
        _decrease_position(
            account,
            collateral_asset,
            index_asset,
            collateral_delta,
            size_delta,
            is_long,
            receiver
        )
    }

    #[storage(read, write)]
    fn liquidate_position(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
        fee_receiver: Account
    ) {
        if storage.in_private_liquidation_mode.read() {
            require(
                storage.is_liquidator.get(get_sender()).try_read().unwrap_or(false),
                Error::VaultInvalidLiquidator
            );
        }

        // set includeAmmPrice to false to prevent manipulated liquidations
        storage.include_amm_price.write(false);

        _update_cumulative_funding_rate(collateral_asset, index_asset);

        let position_key = _get_position_key(
            account, 
            collateral_asset, 
            index_asset, 
            is_long
        );

        let position = storage.positions.get(position_key).try_read().unwrap_or(Position::default());
        require(position.size > 0, Error::VaultEmptyPosition);

        let liquidation_fee_usd = storage.liquidation_fee_usd.read();

        let (liquidation_state, margin_fees) = _validate_liquidation(
            account,
            collateral_asset,
            index_asset,
            is_long,
            false 
        );
        require(
            liquidation_state != 0,
            Error::VaultPositionCannotBeLiquidated
        );

        if liquidation_state == 2 {
            // max leverage exceeded but there is collateral remaining after deducting losses 
            // so decreasePosition instead
            _decrease_position(
                account,
                collateral_asset,
                index_asset,
                0,
                position.size,
                is_long,
                Account::from(account)
            );
            storage.include_amm_price.write(true);
            return;
        }

        let fee_assets = _usd_to_asset_min(collateral_asset, margin_fees);
        storage.fee_reserves.insert(
            collateral_asset,
            storage.fee_reserves.get(collateral_asset).try_read().unwrap_or(0) + fee_assets
        );
        // log(CollectMarginFees {
        //     asset: collateral_asset,
        //     fee_usd: margin_fees,
        //     fee_assets,
        // });

        _decrease_reserved_amount(collateral_asset, position.reserve_amount);

        if is_long {
            _decrease_guaranteed_usd(collateral_asset, position.size - position.collateral);
            _decrease_pool_amount(collateral_asset, _usd_to_asset_min(collateral_asset, margin_fees));
        }

        let mark_price = if is_long {
            _get_min_price(index_asset)
        } else {
            _get_max_price(index_asset)
        };

        // log(LiquidatePosition {
        //     key: position_key,
        //     account,
        //     collateral_asset,
        //     index_asset,
        //     is_long,
        //     size: position.size,
        //     collateral: position.collateral,
        //     reserve_amount: position.reserve_amount,
        //     realized_pnl: position.realized_pnl,
        //     mark_price,
        // });

        if !is_long && margin_fees < position.collateral {
            let remaining_collateral = position.collateral - margin_fees;
            _increase_pool_amount(collateral_asset, _usd_to_asset_min(collateral_asset, remaining_collateral));
        }

        if !is_long {
            _decrease_global_short_size(index_asset, position.size);
        }

        storage.positions.remove(position_key);

        // pay the fee receiver using the pool, we assume that in general the liquidated amount should be sufficient to cover
        // the liquidation fees
        _decrease_pool_amount(collateral_asset, _usd_to_asset_min(collateral_asset, liquidation_fee_usd));
        _transfer_out(
            collateral_asset, 
            // @TODO: potential revert here
            u64::try_from(_usd_to_asset_min(collateral_asset, liquidation_fee_usd)).unwrap(),
            fee_receiver
        );

        storage.include_amm_price.write(true);
    }
}

/*
    ____  ___       _                        _ 
   / / / |_ _|_ __ | |_ ___ _ __ _ __   __ _| |
  / / /   | || '_ \| __/ _ \ '__| '_ \ / _` | |
 / / /    | || | | | ||  __/ |  | | | | (_| | |
/_/_/    |___|_| |_|\__\___|_|  |_| |_|\__,_|_|
*/

#[storage(read)]
fn _only_gov() {
    require(get_sender() == storage.gov.read(), Error::VaultForbiddenNotGov);
}

#[storage(read)]
fn _validate_manager() {
    if storage.in_manager_mode.read() == true {
        require(
            storage.is_manager.get(get_sender()).try_read().unwrap_or(false), 
            Error::VaultForbiddenNotManager
        );
    }
}

#[storage(read, write)]
fn _transfer_in(asset_id: AssetId) -> u64 {
    let prev_balance = storage.asset_balances.get(asset_id).try_read().unwrap_or(0);
    let next_balance = balance_of(contract_id(), asset_id);
    storage.asset_balances.insert(asset_id, next_balance);

    return next_balance - prev_balance;
}

#[storage(read, write)]
fn _transfer_out(asset_id: AssetId, amount: u64, receiver: Account) {
    // Native asset docs: https://docs.fuel.network/docs/sway/blockchain-development/native_assets/
    transfer_assets(
        asset_id, 
        receiver,
        amount
    );
    storage.asset_balances.insert(asset_id, balance_of(contract_id(), asset_id));
}

#[storage(read, write)]
fn _increase_usdg_amount(asset: AssetId, amount: u256) {
    let new_usdg_amount = storage.usdg_amounts.get(asset).try_read().unwrap_or(0) + amount;
    storage.usdg_amounts.insert(asset, new_usdg_amount);

    let max_usdg_amount = storage.max_usdg_amounts.get(asset).try_read().unwrap_or(0);
    if max_usdg_amount != 0 {
        require(new_usdg_amount <= max_usdg_amount, Error::VaultMaxUsdgExceeded);
    }
    // log(IncreaseUsdgAmount {
    //     asset: asset,
    //     amount: amount,
    // });
}

#[storage(read, write)]
fn _decrease_usdg_amount(asset: AssetId, amount: u256) {
    let value = storage.usdg_amounts.get(asset).try_read().unwrap_or(0);
    // since USDG can be minted using multiple assets
    // it is possible for the USDG debt for a single asset to be less than zero
    // the USDG debt is capped to zero for this case
    if value <= amount {
        storage.usdg_amounts.insert(asset, 0);
        // log(DecreaseUsdgAmount {
        //     asset: asset,
        //     amount: value,
        // });
    } else {
        storage.usdg_amounts.insert(asset, value - amount);
        // log(DecreaseUsdgAmount {
        //     asset: asset,
        //     amount: amount,
        // });
    }
}

#[storage(read, write)]
fn _increase_pool_amount(asset: AssetId, amount: u256) {
    let new_pool_amount = storage.pool_amounts.get(asset).try_read().unwrap_or(0) + amount;
    storage.pool_amounts.insert(asset, new_pool_amount);

    let balance = balance_of(contract_id(), asset);

    require(new_pool_amount <= balance.as_u256(), Error::VaultInvalidIncrease);

    // log(IncreasePoolAmount {
    //     asset: asset,
    //     amount: amount,
    // });
}

#[storage(read, write)]
fn _decrease_pool_amount(asset: AssetId, amount: u256) {
    let pool_amount = storage.pool_amounts.get(asset).try_read().unwrap_or(0);

    require(pool_amount >= amount, Error::VaultPoolAmountExceeded);

    let new_pool_amount = pool_amount - amount;

    storage.pool_amounts.insert(asset, new_pool_amount);

    require(
        storage.reserved_amounts.get(asset).try_read().unwrap_or(0) <= new_pool_amount,
        Error::VaultReserveExceedsPool
    );
}

#[storage(read, write)]
fn _increase_global_short_size(asset: AssetId, amount: u256) {
    storage.global_short_sizes.insert(
        asset,
        storage.global_short_sizes.get(asset).try_read().unwrap_or(0) + amount
    );

    let max_size = storage.max_global_short_sizes.get(asset).try_read().unwrap_or(0);
    if max_size != 0 {
        require(
            storage.global_short_sizes.get(asset).try_read().unwrap_or(0) <= max_size,
            Error::VaultMaxShortsExceeded
        );
    }
}

#[storage(read, write)]
fn _decrease_global_short_size(asset: AssetId, amount: u256) {
    let global_short_size = storage.global_short_sizes.get(asset);

    if amount > global_short_size.read() {
        storage.global_short_sizes.insert(asset, 0);
        return;
    }

    storage.global_short_sizes.insert(
        asset,
        global_short_size.read() - amount
    );
}

#[storage(read, write)]
fn _increase_guaranteed_usd(asset: AssetId, usd_amount: u256) {
    storage.guaranteed_usd.insert(
        asset,
        storage.guaranteed_usd.get(asset).try_read().unwrap_or(0) + usd_amount
    );

    // log(IncreaseGuaranteedAmount {
    //     asset: asset,
    //     amount: usd_amount,
    // });
}

#[storage(read, write)]
fn _decrease_guaranteed_usd(asset: AssetId, usd_amount: u256) {
    storage.guaranteed_usd.insert(
        asset,
        storage.guaranteed_usd.get(asset).try_read().unwrap_or(0) - usd_amount
    );

    // log(DecreaseGuaranteedAmount {
    //     asset: asset,
    //     amount: usd_amount,
    // });
}

#[storage(read, write)]
fn _increase_reserved_amount(asset: AssetId, amount: u256) {
    storage.reserved_amounts.insert(
        asset,
        storage.reserved_amounts.get(asset).try_read().unwrap_or(0) + amount
    );

    require(
        storage.reserved_amounts.get(asset).try_read().unwrap_or(0) <= 
            storage.pool_amounts.get(asset).try_read().unwrap_or(0),
        Error::VaultReserveExceedsPool
    );
    
    // log(IncreaseReservedAmount {
    //     asset: asset,
    //     amount: amount,
    // });
}

#[storage(read, write)]
fn _decrease_reserved_amount(asset: AssetId, amount: u256) {
    if storage.reserved_amounts.get(asset).try_read().unwrap_or(0) < amount {
        require(false, Error::VaultInsufficientReserve);
    }

    storage.reserved_amounts.insert(
        asset,
        storage.reserved_amounts.get(asset).try_read().unwrap_or(0) - amount
    );

    // log(DecreaseReservedAmount {
    //     asset: asset,
    //     amount: amount,
    // });
}

#[storage(read, write)]
fn _update_cumulative_funding_rate(collateral_asset: AssetId, index_asset: AssetId) {
    let should_update = utils_update_cumulative_funding_rate(collateral_asset, index_asset);
    if !should_update {
        return;
    }

    let last_funding_time = storage.last_funding_times.get(collateral_asset).try_read().unwrap_or(0);
    let funding_interval = storage.funding_interval.read();

    if last_funding_time == 0 {
        storage.last_funding_times.insert(
            collateral_asset, 
            timestamp() /* * funding_interval / funding_interval */
        );
        return;
    }

    if last_funding_time + funding_interval > timestamp() {
        return;
    }

    let funding_rate = _get_next_funding_rate(collateral_asset);
    storage.cumulative_funding_rates.insert(
        collateral_asset, 
        storage.cumulative_funding_rates
            .get(collateral_asset).try_read().unwrap_or(0) + funding_rate
    );
    storage.last_funding_times.insert(collateral_asset, timestamp() /* * funding_interval / funding_interval */ );

    // log(UpdateFundingRate {
    //     asset: collateral_asset,
    //     funding_rate: storage.cumulative_funding_rates
    //         .get(collateral_asset).try_read().unwrap_or(0),
    // });
}

#[storage(read)]
fn _get_next_funding_rate(asset: AssetId) -> u256 {
    let last_funding_time = storage.last_funding_times.get(asset).try_read().unwrap_or(0);
    let funding_interval = storage.funding_interval.read();

    if last_funding_time + funding_interval > timestamp() {
        return 0;
    }

    let intervals = timestamp() - last_funding_time / funding_interval;
    let pool_amount = storage.pool_amounts.get(asset).try_read().unwrap_or(0);
    if pool_amount == 0 {
        return 0;
    }

    let funding_rate_factor = if storage.stable_assets.get(asset).try_read().unwrap_or(false) {
        storage.stable_funding_rate_factor.read()
    } else {
        storage.funding_rate_factor.read()
    };

    return 
        funding_rate_factor.as_u256() * storage.reserved_amounts.get(asset).try_read().unwrap_or(0) 
        * intervals.as_u256() / pool_amount;
}

#[storage(read)]
fn _adjust_for_decimals(amount: u256, asset_div: AssetId, asset_mul: AssetId) -> u256 {
    let usdg = storage.usdg.read();
    let decimals_div = if asset_div == usdg {
        USDG_DECIMALS
    } else {
        storage.asset_decimals.get(asset_div).try_read().unwrap_or(0)
    };

    let decimals_mul = if asset_mul == usdg {
        USDG_DECIMALS
    } else {
        storage.asset_decimals.get(asset_mul).try_read().unwrap_or(0)
    };

    // @TODO: prob will need to switch to a bigger type like u128 or even u256 to handle
    // large arithmetic operations without overflow
    amount * 10.pow(decimals_mul.as_u32()).as_u256() / 10.pow(decimals_div.as_u32()).as_u256()
}

#[storage(read)]
fn _get_max_price(asset: AssetId) -> u256 {
    let vault_pricefeed = abi(VaultPricefeed, storage.pricefeed_provider.read().into());
    vault_pricefeed.get_price(
        asset, 
        true,
        storage.include_amm_price.read(),
        storage.use_swap_pricing.read()
    )
}

#[storage(read)]
fn _get_min_price(asset: AssetId) -> u256 {
    let vault_pricefeed = abi(VaultPricefeed, storage.pricefeed_provider.read().into());
    vault_pricefeed.get_price(
        asset, 
        false,
        storage.include_amm_price.read(),
        storage.use_swap_pricing.read()
    )
}

#[storage(read)]
fn _asset_to_usd_min(asset: AssetId, asset_amount: u256) -> u256 {
    if asset_amount == 0 {
        return 0;
    }

    let price = _get_min_price(asset);
    let decimals = storage.asset_decimals.get(asset).try_read().unwrap_or(0);

    (asset_amount * price) / 10.pow(decimals.as_u32()).as_u256()
}

#[storage(read)]
fn _usd_to_asset_max(asset: AssetId, usd_amount: u256) -> u256 {
    if usd_amount == 0 {
        return 0;
    }

    // @notice this is CORRECT (asset_max -> get_min_price)
    _usd_to_asset(asset, usd_amount, _get_min_price(asset))
}

#[storage(read)]
fn _usd_to_asset_min(asset: AssetId, usd_amount: u256) -> u256 {
    if usd_amount == 0 {
        return 0;
    }

    // @notice this is CORRECT (asset_min -> get_max_price)
    _usd_to_asset(asset, usd_amount, _get_max_price(asset))
}

#[storage(read)]
fn _usd_to_asset(asset: AssetId, usd_amount: u256, price: u256) -> u256 {
    require(price != 0, Error::VaultPriceQueriedIsZero);

    if usd_amount == 0 {
        return 0;
    }

    let decimals = storage.asset_decimals.get(asset).try_read().unwrap_or(0);

    (usd_amount * 10.pow(decimals.as_u32()).as_u256()) / price
}

#[storage(read)]
fn _get_target_usdg_amount(asset: AssetId) -> u256 {
    let supply = abi(USDG, storage.usdg_contr.read().into()).total_supply();
    if supply == 0 {
        return 0;
    }

    let weight = storage.asset_weights.get(asset).try_read().unwrap_or(0);

    // @TODO: check if asset balance needs to be `u256`
    // @TODO: check if this return cast is needed
    (weight * supply / storage.total_asset_weights.read()).as_u256()
}

#[storage(read, write)]
fn _collect_swap_fees(asset: AssetId, amount: u64, fee_basis_points: u64) -> u64 {
    let after_fee_amount = amount * (BASIS_POINTS_DIVISOR - fee_basis_points) / BASIS_POINTS_DIVISOR;
    let fee_amount = amount - after_fee_amount;

    let fee_reserve = storage.fee_reserves.get(asset).try_read().unwrap_or(0);
    storage.fee_reserves.insert(asset, fee_reserve + fee_amount.as_u256());

    // log(CollectSwapFees {
    //     asset,
    //     fee_usd: _asset_to_usd_min(asset, fee_amount.as_u256()),
    //     fee_assets: fee_amount,
    // });

    after_fee_amount
}

#[storage(read, write)]
fn _collect_margin_fees(
    account: Address,
    collateral_asset: AssetId,
    index_asset: AssetId,
    is_long: bool,
    size_delta: u256,
    size: u256,
    entry_funding_rate: u256
) -> u256 {
    let fee_usd: u256 = _get_position_fee(
        account,
        collateral_asset,
        index_asset,
        is_long,
        size_delta
    ) + _get_funding_fee(
        account,
        collateral_asset,
        index_asset,
        is_long,
        size,
        entry_funding_rate
    );

    let fee_assets = _usd_to_asset_min(collateral_asset, fee_usd);
    storage.fee_reserves.insert(
        collateral_asset,
        storage.fee_reserves.get(collateral_asset).try_read().unwrap_or(0) + fee_assets
    );

    // log(CollectMarginFees {
    //     asset: collateral_asset,
    //     fee_usd,
    //     fee_assets,
    // });

    return fee_usd;
}

#[storage(read)]
fn _get_redemption_amount(asset: AssetId, usdg_amount: u256) -> u256 {
    let price = _get_max_price(asset);
    let redemption_amount = usdg_amount * PRICE_PRECISION / price;

    _adjust_for_decimals(redemption_amount, storage.usdg.read(), asset)
}

#[storage(read)]
fn _get_redemption_collateral(asset: AssetId) -> u256 {
    if storage.stable_assets.get(asset).try_read().unwrap_or(false) {
        return storage.pool_amounts.get(asset).try_read().unwrap_or(0);
    }
    let collateral = _usd_to_asset_min(
        asset,
        storage.guaranteed_usd.get(asset).try_read().unwrap_or(0)
    );

    collateral + 
        storage.pool_amounts.get(asset).try_read().unwrap_or(0) - 
            storage.reserved_amounts.get(asset).try_read().unwrap_or(0)
}

#[storage(write)]
fn _update_asset_balance(asset: AssetId) {
    let next_balance = balance_of(contract_id(), asset);
    storage.asset_balances.insert(asset, next_balance);
}

#[storage(read)]
fn _validate_buffer_amount(asset: AssetId) {
    let pool_amount = storage.pool_amounts.get(asset).try_read().unwrap_or(0);
    let buffer_amount = storage.buffer_amounts.get(asset).try_read().unwrap_or(0);

    if pool_amount < buffer_amount {
        require(false, Error::VaultPoolAmountLtBuffer);
    }
}

#[storage(read)]
fn _validate_router(account: Account) {
    let sender = get_sender();

    if sender == account || sender == Account::from(storage.router.read()) {
        return;
    }

    require(
        storage.approved_routers.get(account).get(sender)
            .try_read().unwrap_or(false),
        Error::VaultInvalidMsgCaller
    );
}

fn _validate_position(size: u256, collateral: u256) {
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
fn _validate_assets(
    collateral_asset: AssetId,
    index_asset: AssetId,
    is_long: bool,
) {
    if is_long {
        require(
            collateral_asset == index_asset,
            Error::VaultLongCollateralIndexAssetsMismatch
        );
        require(
            storage.whitelisted_assets.get(collateral_asset).try_read().unwrap_or(false),
            Error::VaultLongCollateralAssetNotWhitelisted
        );
        require(
            !storage.stable_assets.get(collateral_asset).try_read().unwrap_or(false),
            Error::VaultLongCollateralAssetMustNotBeStableAsset
        );

        return;
    }

    require(
        storage.whitelisted_assets.get(collateral_asset).try_read().unwrap_or(false),
        Error::VaultShortCollateralAssetNotWhitelisted
    );
    require(
        storage.stable_assets.get(collateral_asset).try_read().unwrap_or(false),
        Error::VaultShortCollateralAssetMustBeStableAsset
    );
    require(
        !storage.stable_assets.get(index_asset).try_read().unwrap_or(false),
        Error::VaultShortIndexAssetMustNotBeStableAsset
    );
    require(
        storage.shortable_assets.get(index_asset).try_read().unwrap_or(false),
        Error::VaultShortIndexAssetNotShortable
    );
}

fn _get_position_key(
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

// note that if calling this function independently the cumulativeFundingRates 
// used in getFundingFee will not be the latest value
#[storage(read)]
fn _validate_liquidation(
    account: Address,
    collateral_asset: AssetId,
    index_asset: AssetId,
    is_long: bool,
    should_raise: bool,
) -> (u256, u256) {
    let position_key = _get_position_key(
        account, 
        collateral_asset, 
        index_asset, 
        is_long
    );

    let position = storage.positions.get(position_key).try_read().unwrap_or(Position::default());

    let (has_profit, delta) = _get_delta(
        index_asset,
        position.size,
        position.average_price,
        is_long,
        position.last_increased_time
    );

    let mut margin_fees: u256 = _get_funding_fee(
        account,
        collateral_asset,
        index_asset,
        is_long,
        position.size,
        position.entry_funding_rate
    ) + _get_position_fee(
        account,
        collateral_asset,
        index_asset,
        is_long,
        position.size,
    );

    if !has_profit && position.collateral < delta {
        if should_raise {
            require(false, Error::VaultLossesExceedCollateral);
        }

        return (1, margin_fees);
    }

    let mut remaining_collateral = position.collateral;
    if !has_profit {
        remaining_collateral = position.collateral - delta;
    }

    if remaining_collateral < margin_fees {
        if should_raise {
            require(false, Error::VaultFeesExceedCollateral);
        }

        // cap the fees to the remainingCollateral
        return (1, remaining_collateral);
    }

    if remaining_collateral < margin_fees + storage.liquidation_fee_usd.read() {
        if should_raise {
            require(false, Error::VaultLiquidationFeesExceedCollateral);
        }

        return (1, margin_fees);
    }

    if (remaining_collateral * storage.max_leverage.read().as_u256()) < (position.size * BASIS_POINTS_DIVISOR.as_u256()) {
        if should_raise {
            require(false, Error::VaultMaxLeverageExceeded);
        }

        return (2, margin_fees);
    }

    return (0, margin_fees);
}

// for longs:  next_average_price = (next_price * next_size) / (next_size + delta)
// for shorts: next_average_price = (next_price * next_size) / (next_size - delta)
#[storage(read)]
fn _get_next_average_price(
    index_asset: AssetId,
    size: u256,
    average_price: u256,
    is_long: bool,
    next_price: u256,
    size_delta: u256,
    last_increased_time: u64
) -> u256 {
    let (has_profit, delta) = _get_delta(
        index_asset,
        size,
        average_price,
        is_long,
        last_increased_time
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
fn _get_next_global_short_average_price(
    index_asset: AssetId,
    next_price: u256,
    size_delta: u256,
) -> u256 {
    let size = storage.global_short_sizes.get(index_asset).try_read().unwrap_or(0);
    let average_price = storage.global_short_average_prices.get(index_asset).try_read().unwrap_or(0);
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

#[storage(read)]
fn _get_global_short_delta(asset: AssetId) -> (bool, u256) {
    let size = storage.global_short_sizes.get(asset).try_read().unwrap_or(0);
    if size == 0 {
        return (false, 0);
    }

    let next_price = _get_max_price(asset);
    let average_price = storage.global_short_average_prices.get(asset).try_read().unwrap_or(0);
    let has_profit = average_price > next_price;
    let price_delta = if has_profit {
        average_price - next_price
    } else {
        next_price - average_price
    };
    let delta = size * price_delta / average_price;
    (has_profit, delta)
}

#[storage(read)]
fn _get_position_delta(
    account: Address,
    collateral_asset: AssetId,
    index_asset: AssetId,
    is_long: bool,
) -> (bool, u256) {
    let position_key = _get_position_key(
        account, 
        collateral_asset, 
        index_asset, 
        is_long
    );

    let position = storage.positions.get(position_key).try_read().unwrap_or(Position::default());

    _get_delta(
        index_asset,
        position.size,
        position.average_price,
        is_long,
        position.last_increased_time
    )
}

#[storage(read)]
fn _get_delta(
    index_asset: AssetId,
    size: u256,
    average_price: u256,
    is_long: bool,
    last_increased_time: u64
) -> (bool, u256) {
    require(average_price > 0, Error::VaultInvalidAveragePrice);

    let price = if is_long {
        _get_min_price(index_asset)
    } else {
        _get_max_price(index_asset)
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
    let min_bps = if timestamp() > last_increased_time + storage.min_profit_time.read() {
        0
    } else {
        storage.min_profit_basis_points.get(index_asset).try_read().unwrap_or(0)
    };

    if has_profit
        && (delta * BASIS_POINTS_DIVISOR.as_u256()) <= (size * min_bps.as_u256())
    {
        delta = 0;
    }
    (has_profit, delta)
}

#[storage(read)]
fn _get_entry_funding_rate(
    collateral_asset: AssetId,
    _index_asset: AssetId,
    _is_long: bool,
) -> u256 {
    storage.cumulative_funding_rates.get(collateral_asset).try_read().unwrap_or(0)
}

#[storage(read)]
fn _get_funding_fee(
    _account: Address,
    collateral_asset: AssetId,
    _index_asset: AssetId,
    _is_long: bool,
    size: u256,
    entry_funding_rate: u256
) -> u256 {
    if size == 0 {
        return 0;
    }

    let mut funding_rate = storage.cumulative_funding_rates.get(collateral_asset).try_read().unwrap_or(0);
    funding_rate = funding_rate - entry_funding_rate;
    if funding_rate == 0 {
        return 0;
    }

    size * funding_rate / FUNDING_RATE_PRECISION
}

#[storage(read)]
fn _get_position_fee(
    _account: Address,
    _collateral_asset: AssetId,
    _index_asset: AssetId,
    _is_long: bool,
    size_delta: u256,
) -> u256 {
    if size_delta == 0 {
        return 0;
    }

    let mut after_fee_usd = size_delta * (BASIS_POINTS_DIVISOR - storage.margin_fee_basis_points.read()).as_u256();
    after_fee_usd = after_fee_usd / BASIS_POINTS_DIVISOR.as_u256();

    size_delta - after_fee_usd
}

#[storage(read, write)]
fn _decrease_position(
    account: Address,
    collateral_asset: AssetId,
    index_asset: AssetId,
    collateral_delta: u256,
    size_delta: u256,
    is_long: bool,
    receiver: Account
) -> u256 {
    utils_validate_decrease_position(
        account,
        collateral_asset,
        index_asset,
        collateral_delta,
        size_delta,
        is_long,
        receiver
    );

    _update_cumulative_funding_rate(collateral_asset, index_asset);

    let position_key = _get_position_key(
        account, 
        collateral_asset, 
        index_asset, 
        is_long
    );
    let mut position = storage.positions.get(position_key).try_read().unwrap_or(Position::default());
    require(position.size > 0, Error::VaultEmptyPosition);
    require(position.size >= size_delta, Error::VaultPositionSizeExceeded);
    require(position.collateral >= collateral_delta, Error::VaultPositionCollateralExceeded);

    let collateral = position.collateral;

    let reserve_delta = position.reserve_amount * size_delta / position.size;
    position.reserve_amount = position.reserve_amount - reserve_delta;
    // update storage because the above changes are ignored by call to other fn `_reduce_collateral`
    storage.positions.insert(position_key, position);
    
    _decrease_reserved_amount(collateral_asset, reserve_delta);

    let (usd_out, usd_out_after_fee) = _reduce_collateral(
        account,
        collateral_asset,
        index_asset,
        collateral_delta,
        size_delta,
        is_long
    );
    // re-initialize position here because storage was updated in `_reduce_collateral`
    position = storage.positions.get(position_key).try_read().unwrap_or(Position::default());

    if position.size != size_delta {
        position.entry_funding_rate = _get_entry_funding_rate(collateral_asset, index_asset, is_long);
        position.size = position.size - size_delta;

        _validate_position(position.size, position.collateral);
        _validate_liquidation(
            account,
            collateral_asset,
            index_asset,
            is_long,
            true
        );

        if is_long {
            _increase_guaranteed_usd(collateral_asset, collateral - position.collateral);
            _decrease_guaranteed_usd(collateral_asset, size_delta);
        }

        let price = if is_long {
            _get_min_price(index_asset)
        } else {
            _get_max_price(index_asset)
        };

        // log(DecreasePosition {
        //     key: position_key,
        //     account,
        //     collateral_asset,
        //     index_asset,
        //     collateral_delta,
        //     size_delta,
        //     is_long,
        //     price,
        //     fee: usd_out - usd_out_after_fee,
        // });
        // log(UpdatePosition {
        //     key: position_key,
        //     size: position.size,
        //     collateral: position.collateral,
        //     average_price: position.average_price,
        //     entry_funding_rate: position.entry_funding_rate,
        //     reserve_amount: position.reserve_amount,
        //     realized_pnl: position.realized_pnl,
        //     mark_price: price,
        // });

        storage.positions.insert(position_key, position);
    } else {
        if is_long {
            _increase_guaranteed_usd(collateral_asset, collateral);
            _decrease_guaranteed_usd(collateral_asset, size_delta);
        }

        let price = if is_long {
            _get_min_price(index_asset)
        } else {
            _get_max_price(index_asset)
        };

        // log(DecreasePosition {
        //     key: position_key,
        //     account,
        //     collateral_asset,
        //     index_asset,
        //     collateral_delta,
        //     size_delta,
        //     is_long,
        //     price,
        //     fee: usd_out - usd_out_after_fee,
        // });
        // log(ClosePosition {
        //     key: position_key,
        //     size: position.size,
        //     collateral: position.collateral,
        //     average_price: position.average_price,
        //     entry_funding_rate: position.entry_funding_rate,
        //     reserve_amount: position.reserve_amount,
        //     realized_pnl: position.realized_pnl,
        // });

        storage.positions.remove(position_key);
        position = storage.positions.get(position_key).try_read().unwrap_or(Position::default());
    }

    if !is_long {
        _decrease_global_short_size(index_asset, size_delta);
    }

    if usd_out > 0 {
        if is_long {
            _decrease_pool_amount(collateral_asset, _usd_to_asset_min(collateral_asset, usd_out));
        }

        let amount_out_after_fees = _usd_to_asset_min(collateral_asset, usd_out_after_fee);
 
        // @TODO: potential revert here
        _transfer_out(collateral_asset, u64::try_from(amount_out_after_fees).unwrap(), receiver);
        
        storage.positions.insert(position_key, position);

        return amount_out_after_fees;
    }

    0
}

#[storage(read, write)]
fn _reduce_collateral(
    account: Address,
    collateral_asset: AssetId,
    index_asset: AssetId,
    collateral_delta: u256,
    size_delta: u256,
    is_long: bool,
) -> (u256, u256) {
    let position_key = _get_position_key(
        account,
        collateral_asset,
        index_asset,
        is_long 
    );
    let mut position = storage.positions.get(position_key).try_read().unwrap_or(Position::default());

    let fee = _collect_margin_fees(
        account,
        collateral_asset,
        index_asset,
        is_long,
        size_delta,
        position.size,
        position.entry_funding_rate
    );

    let (has_profit, delta) = _get_delta(
        index_asset,
        position.size,
        position.average_price,
        is_long,
        position.last_increased_time
    );

    let adjusted_delta = size_delta * delta / position.size;

    // transfer profits out
    let mut usd_out = 0;
    if adjusted_delta > 0 {
        if has_profit {
            usd_out = adjusted_delta;
            position.realized_pnl = position.realized_pnl + Signed256::from(adjusted_delta);

            // pay out realized profits from the pool amount for short positions
            if !is_long {
                let token_amount = _usd_to_asset_min(collateral_asset, adjusted_delta);
                _decrease_pool_amount(collateral_asset, token_amount);
            }
        } else {
            position.collateral = position.collateral - adjusted_delta;

            // transfer realized losses to the pool for short positions
            // realized losses for long positions are not transferred here as
            // _increasePoolAmount was already called in increasePosition for longs
            if !is_long {
                let token_amount = _usd_to_asset_min(collateral_asset, adjusted_delta);
                _increase_pool_amount(collateral_asset, token_amount);
            }

            position.realized_pnl = position.realized_pnl - Signed256::from(adjusted_delta);
        }
    }

    // reduce the position's collateral by _collateralDelta
    // transfer _collateralDelta out
    if collateral_delta > 0 {
        usd_out += collateral_delta;
        position.collateral = position.collateral - collateral_delta;
    }

    // if the position will be closed, then transfer the remaining collateral out
    if position.size == size_delta {
        usd_out += position.collateral;

        position.collateral = 0;
    }

    // if the usdOut is more than the fee then deduct the fee from the usdOut directly
    // else deduct the fee from the position's collateral
    let mut usd_out_after_fee = usd_out;
    if usd_out > fee {
        usd_out_after_fee = usd_out - fee;
    } else {
        position.collateral = position.collateral - fee;
        if is_long {
            let fee_assets = _usd_to_asset_min(collateral_asset, fee);
            _decrease_pool_amount(collateral_asset, fee_assets);
        }
    }

    storage.positions.insert(position_key, position);

    // log(UpdatePnl {
    //     key: position_key,
    //     has_profit,
    //     delta: adjusted_delta,
    // });
    (usd_out, usd_out_after_fee)
}

#[storage(read)]
fn _get_buy_usdg_fee_basis_points(
    asset: AssetId,
    usdg_amount: u256,
) -> u256 {
    _get_fee_basis_points(
        asset,
        usdg_amount,
        storage.mint_burn_fee_basis_points.read().as_u256(),
        storage.tax_basis_points.read().as_u256(),
        true
    )
}

#[storage(read)]
fn _get_sell_usdg_fee_basis_points(
    asset: AssetId,
    usdg_amount: u256
) -> u256 {
    _get_fee_basis_points(
        asset,
        usdg_amount,
        storage.mint_burn_fee_basis_points.read().as_u256(),
        storage.tax_basis_points.read().as_u256(),
        false
    )
}

#[storage(read)]
fn _get_swap_fee_basis_points(
    asset_in: AssetId,
    asset_out: AssetId,
    usdg_amount: u256
) -> u256 {
    let is_stableswap = storage.stable_assets.get(asset_in).try_read().unwrap_or(false) 
        && storage.stable_assets.get(asset_out).try_read().unwrap_or(false);

    let base_bps = if is_stableswap {
        storage.stable_swap_fee_basis_points.read()
    } else {
        storage.swap_fee_basis_points.read()
    };

    let tax_bps = if is_stableswap {
        storage.stable_tax_basis_points.read()
    } else {
        storage.tax_basis_points.read()
    };

    let fee_basis_points_0 = _get_fee_basis_points(
        asset_in,
        usdg_amount,
        base_bps.as_u256(),
        tax_bps.as_u256(),
        true
    );
    let fee_basis_points_1 = _get_fee_basis_points(
        asset_out,
        usdg_amount,
        base_bps.as_u256(),
        tax_bps.as_u256(),
        false
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
fn _get_fee_basis_points(
    asset: AssetId,
    usdg_delta: u256,
    fee_basis_points: u256,
    tax_basis_points: u256,
    should_increment: bool
) -> u256 {
    if !storage.has_dynamic_fees.read() {
        return fee_basis_points;
    }

    let initial_amount = storage.usdg_amounts.get(asset).try_read().unwrap_or(0);
    let mut next_amount = initial_amount + usdg_delta;
    if !should_increment {
        next_amount = if usdg_delta > initial_amount {
            0
        } else {
            initial_amount - usdg_delta
        };
    }

    let target_amount = _get_target_usdg_amount(asset);
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