// SPDX-License-Identifier: Apache-2.0
contract;

mod constants;
mod events;
mod errors;

/*
__     __          _ _     ____  _                             
\ \   / /_ _ _   _| | |_  / ___|| |_ ___  _ __ __ _  __ _  ___ 
 \ \ / / _` | | | | | __| \___ \| __/ _ \| '__/ _` |/ _` |/ _ \
  \ V / (_| | |_| | | |_   ___) | || (_) | | | (_| | (_| |  __/
   \_/ \__,_|\__,_|_|\__| |____/ \__\___/|_|  \__,_|\__, |\___|
                                                    |___/
*/

use std::{
    auth::msg_sender,
    block::timestamp,
    call_frames::{
        contract_id,
        msg_asset_id,
    },
    
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
    vault_storage::{
        VaultStorage,
        Position,
        PositionKey
    },
    vault_pricefeed::VaultPricefeed,
};
use asset_interfaces::usdg::USDG;
use events::*;
use constants::*;
use errors::*;

storage {
    // gov is not restricted to an `Address` (EOA) or a `Contract` (external)
    // because this can be either a regular EOA (Address) or a Multisig (Contract)
    gov: Account = ZERO_ACCOUNT,
    /// only `Account`s that are write-authorized into Vault storage
    is_write_authorized: StorageMap<Account, bool> = StorageMap::<Account, bool> {},

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

impl VaultStorage for Contract {
    #[storage(read, write)]
    fn initialize(
        gov: Account,
        router: ContractId,
        usdg: AssetId,
        usdg_contr: ContractId,
        pricefeed_provider: ContractId,
        liquidation_fee_usd: u256,
        funding_rate_factor: u64,
        stable_funding_rate_factor: u64,
    ) {
        require(!storage.is_initialized.read(), Error::VaultStorageAlreadyInitialized);
        storage.is_initialized.write(true);
        storage.gov.write(gov);

        require(
            usdg == AssetId::new(usdg_contr, ZERO),
            Error::VaultStorageInvalidUSDGAsset
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
    fn write_authorize(account: Account, is_authorized: bool) {
        _only_gov();

        storage.is_write_authorized.insert(account, is_authorized);
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
        require(tax_basis_points <= MAX_FEE_BASIS_POINTS, Error::VaultStorageInvalidTaxBasisPoints);
        require(stable_tax_basis_points <= MAX_FEE_BASIS_POINTS, Error::VaultStorageInvalidStableTaxBasisPoints);
        require(mint_burn_fee_basis_points <= MAX_FEE_BASIS_POINTS, Error::VaultStorageInvalidMintBurnFeeBasisPoints);
        require(swap_fee_basis_points <= MAX_FEE_BASIS_POINTS, Error::VaultStorageInvalidSwapFeeBasisPoints);
        require(stable_swap_fee_basis_points <= MAX_FEE_BASIS_POINTS, Error::VaultStorageInvalidStableSwapFeeBasisPoints);
        require(margin_fee_basis_points <= MAX_FEE_BASIS_POINTS, Error::VaultStorageInvalidMarginFeeBasisPoints);
        require(liquidation_fee_usd <= MAX_LIQUIDATION_FEE_USD, Error::VaultStorageInvalidLiquidationFeeUsd);

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
        require(funding_interval >= MIN_FUNDING_RATE_INTERVAL, Error::VaultStorageInvalidFundingInterval);
        require(funding_rate_factor <= MAX_FUNDING_RATE_FACTOR, Error::VaultStorageInvalidFundingRateFactor);
        require(stable_funding_rate_factor <= MAX_FUNDING_RATE_FACTOR, Error::VaultStorageInvalidStableFundingRateFactor);

        storage.funding_interval.write(funding_interval);
        storage.funding_rate_factor.write(funding_rate_factor);
        storage.stable_funding_rate_factor.write(stable_funding_rate_factor);
    }

    // #[storage(read, write)]
    // fn withdraw_fees(asset: AssetId, receiver: Account) -> u64 {
    //     _only_gov();
    //     // @TODO: potential revert here
    //     let amount = u64::try_from(storage.fee_reserves.get(asset).try_read().unwrap_or(0)).unwrap();
    //     if amount == 0 {
    //         return 0;
    //     }

    //     storage.fee_reserves.insert(asset, 0);
    //     _transfer_out(asset, amount, receiver);

    //     amount
    // }

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
            Error::VaultStorageZeroAsset
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
        let _ = abi(
            VaultPricefeed, 
            storage.pricefeed_provider.read().into()
        ).get_price(
            asset,
            true,
            false,
            false
        );
    }

    #[storage(read, write)]
    fn clear_asset_config(asset: AssetId) {
        _only_gov();

        require(
            storage.whitelisted_assets.get(asset).try_read().unwrap_or(false),
            Error::VaultStorageAssetNotWhitelisted
        );

        // `asset_weights` is guaranteed to have a value, hence no need to gracefully unwrap
        storage.total_asset_weights.write(storage.total_asset_weights.read() - storage.asset_weights.get(asset).read());

        let mut _r = false;
        _r = storage.whitelisted_assets.remove(asset);
        _r = storage.asset_decimals.remove(asset);
        _r = storage.asset_weights.remove(asset);
        _r = storage.min_profit_basis_points.remove(asset);
        _r = storage.max_usdg_amounts.remove(asset);
        _r = storage.stable_assets.remove(asset);
        _r = storage.shortable_assets.remove(asset);

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
    fn is_initialized() -> bool {
        storage.is_initialized.read()
    }
    
    #[storage(read)]
    fn is_swap_enabled() -> bool {
        storage.is_swap_enabled.read()
    }

    #[storage(read)]
    fn is_leverage_enabled() -> bool {
        storage.is_leverage_enabled.read()
    }

    #[storage(read)]
    fn has_dynamic_fees() -> bool {
        storage.has_dynamic_fees.read()
    }

    #[storage(read)]
    fn get_include_amm_price() -> bool {
        storage.include_amm_price.read()
    }

    #[storage(read)]
    fn get_use_swap_pricing() -> bool {
        storage.use_swap_pricing.read()
    }

    #[storage(read)]
    fn get_min_profit_time() -> u64 {
        storage.min_profit_time.read()
    }

    #[storage(read)]
    fn get_max_leverage() -> u64 {
        storage.max_leverage.read()
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
    fn get_router() -> ContractId {
        storage.router.read()
    }

    #[storage(read)]
    fn get_usdg_contr() -> ContractId {
        storage.usdg_contr.read()
    }

    #[storage(read)]
    fn get_usdg() -> AssetId {
        storage.usdg.read()
    }

    #[storage(read)]
    fn get_pricefeed_provider() -> ContractId {
        storage.pricefeed_provider.read()
    }

    #[storage(read)]
    fn get_funding_interval() -> u64 {
        storage.funding_interval.read()
    }

    #[storage(read)]
    fn get_funding_rate_factor() -> u64 {
        storage.funding_rate_factor.read()
    }

    #[storage(read)]
    fn get_stable_funding_rate_factor() -> u64 {
        storage.stable_funding_rate_factor.read()
    }

    #[storage(read)]
    fn get_total_asset_weights() -> u64 {
        storage.total_asset_weights.read()
    }

    #[storage(read)]
    fn get_in_manager_mode() -> bool {
        storage.in_manager_mode.read()
    }

    #[storage(read)]
    fn get_in_private_liquidation_mode() -> bool {
        storage.in_private_liquidation_mode.read()
    }

    #[storage(read)]
    fn is_approved_router(account1: Account, account2: Account) -> bool {
        storage.approved_routers.get(account1).get(account2).try_read().unwrap_or(false)
    }

    #[storage(read)]
    fn get_is_liquidator(account: Account) -> bool {
        storage.is_liquidator.get(account).try_read().unwrap_or(false)
    }

    #[storage(read)]
    fn get_is_manager(account: Account) -> bool {
        storage.is_manager.get(account).try_read().unwrap_or(false)
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
    fn get_whitelisted_asset_count() -> u64 {
        storage.whitelisted_asset_count.read()
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
    fn get_min_profit_basis_points(asset: AssetId) -> u64 {
        storage.min_profit_basis_points.get(asset).try_read().unwrap_or(0)
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
    fn get_asset_balance(asset: AssetId) -> u64 {
        storage.asset_balances.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_asset_weight(asset: AssetId) -> u64 {
        storage.asset_weights.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_usdg_amount(asset: AssetId) -> u256 {
        storage.usdg_amounts.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_max_usdg_amount(asset: AssetId) -> u256 {
        storage.max_usdg_amounts.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_pool_amounts(asset: AssetId) -> u256 {
        storage.pool_amounts.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_reserved_amounts(asset: AssetId) -> u256 {
        storage.reserved_amounts.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_buffer_amounts(asset: AssetId) -> u256 {
        storage.buffer_amounts.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_guaranteed_usd(asset: AssetId) -> u256 {
        storage.guaranteed_usd.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_cumulative_funding_rates(asset: AssetId) -> u256 {
        storage.cumulative_funding_rates.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_last_funding_times(asset: AssetId) -> u64 {
        storage.last_funding_times.get(asset).try_read().unwrap_or(0)
    }

    #[storage(read)]
    fn get_position(position_key: b256) -> Position {
        storage.positions.get(position_key).try_read().unwrap_or(Position::default())
    }

    #[storage(read)]
    fn get_fee_reserves(asset: AssetId) -> u256 {
        storage.fee_reserves.get(asset).try_read().unwrap_or(0)
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
    fn get_max_global_short_sizes(asset: AssetId) -> u256 {
        storage.max_global_short_sizes.get(asset).try_read().unwrap_or(0)
    }

    /*
          ____  ____        _     _ _      
         / / / |  _ \ _   _| |__ | (_) ___ 
        / / /  | |_) | | | | '_ \| | |/ __|
       / / /   |  __/| |_| | |_) | | | (__ 
      /_/_/    |_|    \__,_|_.__/|_|_|\___|
    */
    #[storage(write)]
    fn write_use_swap_pricing(use_swap_pricing: bool) {
        _only_write_authorized();

        storage.use_swap_pricing.write(use_swap_pricing);
    }

    #[storage(write)]
    fn write_include_amm_price(include_amm_price: bool) {
        _only_write_authorized();

        storage.include_amm_price.write(include_amm_price);
    }

    #[storage(write)]
    fn write_asset_balances(asset: AssetId, bal: u64) {
        _only_write_authorized();

        storage.asset_balances.insert(asset, bal);
    }

    #[storage(write)]
    fn write_asset_weights(asset: AssetId, weight: u64) {
        _only_write_authorized();

        storage.asset_weights.insert(asset, weight);
    }

    #[storage(write)]
    fn write_usdg_amounts(asset: AssetId, usdg_amount: u256) {
        _only_write_authorized();

        storage.usdg_amounts.insert(asset, usdg_amount);
    }

    #[storage(write)]
    fn write_max_usdg_amounts(asset: AssetId, max_usdg_amount: u256) {
        _only_write_authorized();

        storage.max_usdg_amounts.insert(asset, max_usdg_amount);
    }

    #[storage(write)]
    fn write_pool_amounts(asset: AssetId, pool_amount: u256) {
        _only_write_authorized();

        storage.pool_amounts.insert(asset, pool_amount);
    }

    #[storage(write)]
    fn write_reserved_amounts(asset: AssetId, reserved_amount: u256) {
        _only_write_authorized();

        storage.reserved_amounts.insert(asset, reserved_amount);
    }

    #[storage(write)]
    fn write_buffer_amounts(asset: AssetId, buffer_amount: u256) {
        _only_write_authorized();

        storage.buffer_amounts.insert(asset, buffer_amount);
    }

    #[storage(write)]
    fn write_guaranteed_usd(asset: AssetId, guaranteed_usd: u256) {
        _only_write_authorized();

        storage.guaranteed_usd.insert(asset, guaranteed_usd);
    }

    #[storage(write)]
    fn write_cumulative_funding_rates(asset: AssetId, cumulative_funding_rate: u256) {
        _only_write_authorized();

        storage.cumulative_funding_rates.insert(asset, cumulative_funding_rate);
    }

    #[storage(write)]
    fn write_last_funding_times(asset: AssetId, last_funding_time: u64) {
        _only_write_authorized();

        storage.last_funding_times.insert(asset, last_funding_time);
    }

    #[storage(write)]
    fn write_position(position_key: b256, position: Position) {
        _only_write_authorized();

        storage.positions.insert(position_key, position);
    }

    #[storage(write)]
    fn write_fee_reserves(asset: AssetId, fee_reserve: u256) {
        _only_write_authorized();

        storage.fee_reserves.insert(asset, fee_reserve);
    }

    #[storage(write)]
    fn write_global_short_sizes(asset: AssetId, global_short_size: u256) {
        _only_write_authorized();

        storage.global_short_sizes.insert(asset, global_short_size);
    }


    #[storage(write)]
    fn write_global_short_average_prices(asset: AssetId, global_short_average_price: u256) {
        _only_write_authorized();

        storage.global_short_average_prices.insert(asset, global_short_average_price);
    }

    #[storage(write)]
    fn write_max_global_short_sizes(asset: AssetId, max_global_short_size: u256) {
        _only_write_authorized();

        storage.max_global_short_sizes.insert(asset, max_global_short_size);
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
    require(get_sender() == storage.gov.read(), Error::VaultStorageForbiddenNotGov);
}

#[storage(read)]
fn _only_write_authorized() {
    require(
        storage.is_write_authorized.get(get_sender()).try_read().unwrap_or(false), 
        Error::VaultStorageOnlyAuthorizedEntity
    );
}

#[storage(read, write)]
fn _increase_usdg_amount(asset: AssetId, amount: u256) {
    let new_usdg_amount = storage.usdg_amounts.get(asset).try_read().unwrap_or(0) + amount;
    storage.usdg_amounts.insert(asset, new_usdg_amount);

    let max_usdg_amount = storage.max_usdg_amounts.get(asset).try_read().unwrap_or(0);
    if max_usdg_amount != 0 {
        require(new_usdg_amount <= max_usdg_amount, Error::VaultStorageMaxUsdgExceeded);
    }
    log(IncreaseUsdgAmount {
        asset: asset,
        amount: amount,
    });
}

#[storage(read, write)]
fn _decrease_usdg_amount(asset: AssetId, amount: u256) {
    let value = storage.usdg_amounts.get(asset).try_read().unwrap_or(0);
    // since USDG can be minted using multiple assets
    // it is possible for the USDG debt for a single asset to be less than zero
    // the USDG debt is capped to zero for this case
    if value <= amount {
        storage.usdg_amounts.insert(asset, 0);
        log(DecreaseUsdgAmount {
            asset: asset,
            amount: value,
        });
    } else {
        storage.usdg_amounts.insert(asset, value - amount);
        log(DecreaseUsdgAmount {
            asset: asset,
            amount: amount,
        });
    }
}