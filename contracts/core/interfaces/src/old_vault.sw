// SPDX-License-Identifier: Apache-2.0
library;

use helpers::{
    context::*,
    signed_256::*,
};
use ::vault_storage::Position;

abi OldVault {
    #[storage(read, write)]
    fn initialize(
        gov: Address, 
        router: ContractId, 
        usdg: AssetId,
        usdg_contr: ContractId,
        pricefeed_provider: ContractId, 
        liquidation_fee_usd: u256, 
        funding_rate_factor: u64, 
        stable_funding_rate_factor: u64
    );

    /*
          ____     _       _           _       
         / / /    / \   __| |_ __ ___ (_)_ __  
        / / /    / _ \ / _` | '_ ` _ \| | '_ \ 
       / / /    / ___ \ (_| | | | | | | | | | |
      /_/_/    /_/   \_\__,_|_| |_| |_|_|_| |_|                         
    */
    #[storage(write)]
    fn set_manager(manager: Account, is_manager: bool);

    #[storage(write)]
    fn set_liquidator(liquidator: Account, is_active: bool);

    #[storage(write)]
    fn set_gov(gov: Account);

    #[storage(write)]
    fn set_in_manager_mode(mode: bool);

    #[storage(write)]
    fn set_in_private_liquidation_mode(mode: bool);

    #[storage(write)]
    fn set_is_swap_enabled(is_swap_enabled: bool);

    #[storage(write)]
    fn set_is_leverage_enabled(is_swap_enabled: bool);

    #[storage(write)]
    fn set_pricefeed(pricefeed: ContractId);

    #[storage(write)]
    fn set_max_leverage(max_leverage: u64);

    #[storage(write)]
    fn set_buffer_amount(asset: AssetId, buffer_amount: u256);

    #[storage(write)]
    fn set_max_global_short_size(asset: AssetId, amount: u256);

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
    );

    #[storage(read, write)]
    fn set_funding_rate(
        funding_interval: u64, 
        funding_rate_factor: u64, 
        stable_funding_rate_factor: u64
    );

    #[storage(read, write)]
    fn withdraw_fees(asset: AssetId, receiver: Account) -> u64;

    #[storage(read, write)]
    fn set_asset_config(
        asset: AssetId,
        asset_decimals: u8,
        asset_weight: u64,
        min_profit_bps: u64,
        max_usdg_amount: u256,
        is_stable: bool,
        is_shortable: bool
    );

    #[storage(read, write)]
    fn clear_asset_config(asset: AssetId);

    #[storage(write)]
    fn set_router(router: Account, is_active: bool);

    #[storage(write)]
    fn set_usdg_amount(asset: AssetId, amount: u256);

    #[storage(read)]
    fn upgrade_vault(new_vault: ContractId, asset: AssetId, amount: u64);

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
    );

    fn get_position_key(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
    ) -> b256;

    #[storage(read)]
    fn get_position_delta(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
    ) -> (bool, u256);

    #[storage(read)]
    fn get_delta(
        index_asset: AssetId,
        size: u256,
        average_price: u256,
        is_long: bool,
        last_increased_time: u64
    ) -> (bool, u256);

    #[storage(read)]
    fn get_entry_funding_rate(
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool 
    ) -> u256;

    #[storage(read)]
    fn get_funding_fee(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
        size: u256,
        entry_funding_rate: u256
    ) -> u256;

    #[storage(read)]
    fn get_position_fee(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
        size_delta: u256,
    ) -> u256;

    #[storage(read)]
    fn get_global_short_sizes(asset: AssetId) -> u256;

    #[storage(read)]
    fn get_global_short_average_prices(asset: AssetId) -> u256;

    #[storage(read)]
    fn get_guaranteed_usd(asset: AssetId) -> u256;

    #[storage(read)]
    fn get_max_price(asset: AssetId) -> u256;

    #[storage(read)]
    fn get_min_price(asset: AssetId) -> u256;

    #[storage(read)]
    fn asset_to_usd_min(
        asset: AssetId, 
        asset_amount: u256
    ) -> u256;

    #[storage(read)]
    fn usd_to_asset_max(
        asset: AssetId, 
        usd_amount: u256
    ) -> u256;

    #[storage(read)]
    fn usd_to_asset_min(
        asset: AssetId, 
        usd_amount: u256
    ) -> u256;

    #[storage(read)]
    fn usd_to_asset(
        asset: AssetId, 
        usd_amount: u256, 
        price: u256
    ) -> u256;

    #[storage(read)]
    fn get_pool_amounts(asset: AssetId) -> u256;

    #[storage(read)]
    fn get_fee_reserves(asset: AssetId) -> u256;

    #[storage(read)]
    fn get_reserved_amounts(asset: AssetId) -> u256;

    #[storage(read)]
    fn get_usdg_amounts(asset: AssetId) -> u256;

    #[storage(read)]
    fn get_max_usdg_amounts(asset: AssetId) -> u256;

    #[storage(read)]
    fn get_buffer_amounts(asset: AssetId) -> u256;

    #[storage(read)]
    fn get_asset_weights(asset: AssetId) -> u64;

    #[storage(read)]
    fn get_redemption_amount(
        asset: AssetId, 
        usdg_amount: u256
    ) -> u256; 

    #[storage(read)]
    fn get_redemption_collateral(asset: AssetId) -> u256;

    #[storage(read)]
    fn get_redemption_collateral_usd(asset: AssetId) -> u256;
    
    #[storage(read)]
    fn get_pricefeed_provider() -> ContractId;

    #[storage(read)]
    fn get_all_whitelisted_assets_length() -> u64;

    #[storage(read)]
    fn get_whitelisted_asset_by_index(index: u64) -> AssetId;

    #[storage(read)]
    fn is_asset_whitelisted(asset: AssetId) -> bool;

    #[storage(read)]
    fn get_asset_decimals(asset: AssetId) -> u8;

    #[storage(read)]
    fn is_stable_asset(asset: AssetId) -> bool;

    #[storage(read)]
    fn is_shortable_asset(asset: AssetId) -> bool;

    #[storage(read)]
    fn get_position_leverage(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
    ) -> u256;

    #[storage(read)]
    fn get_cumulative_funding_rate(asset: AssetId) -> u256;

    #[storage(read)]
    fn get_fee_basis_points(
        asset: AssetId,
        usdg_delta: u256,
        fee_basis_points: u256,
        tax_basis_points: u256,
        increment: bool
    ) -> u256;

    #[storage(read)]
    fn get_liquidation_fee_usd() -> u256;

    #[storage(read)]
    fn get_tax_basis_points() -> u64;

    #[storage(read)]
    fn get_stable_tax_basis_points() -> u64;

    #[storage(read)]
    fn get_mint_burn_fee_basis_points() -> u64;

    #[storage(read)]
    fn get_swap_fee_basis_points() -> u64;

    #[storage(read)]
    fn get_stable_swap_fee_basis_points() -> u64;

    #[storage(read)]
    fn get_margin_fee_basis_points() -> u64;

    #[storage(read)]
    fn get_min_profit_time() -> u64;

    #[storage(read)]
    fn get_has_dynamic_fees() -> bool;

    #[storage(read)]
    fn get_target_usdg_amount(asset: AssetId) -> u256;

    #[storage(read)]
    fn get_utilization(asset: AssetId) -> u256;

    #[storage(read)]
    fn get_global_short_delta(asset: AssetId) -> (bool, u256);

    #[storage(read)]
    fn is_liquidator(account: Account) -> bool;

    #[storage(read)]
    fn is_in_private_liquidation_mode() -> bool;

    #[storage(read)]
    fn validate_liquidation(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
        should_raise: bool,
    ) -> (u256, u256);
    
    /*
          ____  ____        _     _ _      
         / / / |  _ \ _   _| |__ | (_) ___ 
        / / /  | |_) | | | | '_ \| | |/ __|
       / / /   |  __/| |_| | |_) | | | (__ 
      /_/_/    |_|    \__,_|_.__/|_|_|\___|
    */
    #[storage(read, write)]
    fn update_cumulative_funding_rate(collateral_asset: AssetId, index_asset: AssetId);

    #[payable]
    #[storage(read, write)]
    fn direct_pool_deposit(asset: AssetId);

    #[storage(read, write)]
    fn buy_usdg(asset: AssetId, receiver: Account) -> u256;

    #[storage(read, write)]
    fn sell_usdg(asset: AssetId, receiver: Account) -> u256;

    #[payable]
    #[storage(read, write)]
    fn swap(asset_in: AssetId, asset_out: AssetId, receiver: Account) -> u64;

    #[payable]
    #[storage(read, write)]
    fn increase_position(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        size_delta: u256,
        is_long: bool 
    );

    #[storage(read, write)]
    fn decrease_position(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        collateral_delta: u256,
        size_delta: u256,
        is_long: bool,
        receiver: Account
    ) -> u256;

    #[storage(read, write)]
    fn liquidate_position(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
        fee_receiver: Account
    );
}