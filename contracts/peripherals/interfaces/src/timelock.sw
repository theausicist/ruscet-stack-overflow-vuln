// SPDX-License-Identifier: Apache-2.0
library;

use helpers::{
    context::*,
    asset::*,
};

abi Timelock {
    #[storage(read, write)]
    fn initialize(
        admin: Account,
        buffer: u64,
        asset_manager: Account,
        mint_receiver: Account,
        glp_manager: ContractId,
        prev_glp_manager: ContractId,
        reward_router: ContractId,
        max_asset_supply: u64,
        margin_fee_bps: u64,
        max_margin_fee_bps: u64,
    );

    /*
          ____     _       _           _       
         / / /    / \   __| |_ __ ___ (_)_ __  
        / / /    / _ \ / _` | '_ ` _ \| | '_ \ 
       / / /    / ___ \ (_| | | | | | | | | | |
      /_/_/    /_/   \_\__,_|_| |_| |_|_|_| |_|                         
    */
    #[storage(read, write)]
    fn set_gov(gov: Account);

    #[storage(read)]
    fn set_external_admin(target: ContractId, admin: Account);

    #[storage(read, write)]
    fn set_contract_handler(handler: Account, is_active: bool);

    #[storage(read, write)]
    fn set_keeper(keeper: Account, is_active: bool);

    #[storage(read)]
    fn init_glp_manager();

    #[storage(read, write)]
    fn set_buffer(buffer: u64);

    #[storage(read)]
    fn set_max_leverage(
        vault: ContractId,
        max_leverage: u64
    );

    #[storage(read)]
    fn set_funding_rate(
        vault: ContractId,
        funding_interval: u64,
        funding_rate_factor: u64,
        stable_funding_rate_factor: u64
    );

    #[storage(read, write)]
    fn set_should_toggle_is_leverage_enabled(
        should_toggle_is_leverage_enabled: bool,
    );

    #[storage(read, write)]
    fn set_margin_fee_bps(
        margin_fee_bps: u64,
        max_margin_fee_bps: u64,
    );

    #[storage(read)]
    fn set_swap_fees(
        vault_: ContractId,
        tax_basis_points: u64,
        stable_tax_basis_points: u64,
        mint_burn_basis_points: u64,
        swap_fee_basis_points: u64,
        stable_swap_fee_basis_points: u64,
    );

    // assign _marginFeeBasisPoints to this.marginFeeBasisPoints
    // because enableLeverage would update Vault.marginFeeBasisPoints to this.marginFeeBasisPoints
    // and disableLeverage would reset the Vault.marginFeeBasisPoints to this.maxMarginFeeBasisPoints
    #[storage(read, write)]
    fn set_fees(
        vault: ContractId,
        tax_basis_points: u64,
        stable_tax_basis_points: u64,
        mint_burn_basis_points: u64,
        swap_fee_basis_points: u64,
        stable_swap_fee_basis_points: u64,
        margin_fee_basis_points: u64,
        liquidation_fee_usd: u256,
        min_profit_time: u64,
        has_dynamic_fees: bool,
    );

    #[storage(read)]
    fn enable_leverage(vault_: ContractId);

    #[storage(read)]
    fn disable_leverage(vault_: ContractId);

    #[storage(read)]
    fn set_is_leverage_enabled(vault: ContractId, is_leverage_enabled: bool);

    #[storage(read)]
    fn set_asset_config(
        vault: ContractId,
        asset: AssetId,
        asset_weight: u64,
        min_profit_bps: u64,
        max_usdg_amount: u256,
        buffer_amount: u256,
        usdg_amount: u256,
    );

    #[storage(read)]
    fn set_usdg_amounts(
        vault: ContractId, 
        assets: Vec<AssetId>,
        usdg_amounts: Vec<u256>
    );

    #[storage(read)]
    fn update_usdg_supply(glp_manager: ContractId, usdg_amount: u256);

    #[storage(read)]
    fn set_shorts_tracker_avg_price_weight(shorts_tracker_avg_price_weight: u64);

    #[storage(read)]
    fn set_glp_cooldown_duration(glp_cooldown_duration: u64);

    #[storage(read)]
    fn set_max_global_short_size(
        vault: ContractId,
        asset: AssetId,
        amount: u256
    );

    #[storage(read)]
    fn set_is_swap_enabled(
        vault: ContractId,
        is_swap_enabled: bool
    );

    #[storage(read)]
    fn set_tier(
        referral_storage: ContractId,
        tier_id: u64,
        total_rebate: u64,
        discount_share: u64
    );

    #[storage(read)]
    fn set_referrer_tier(
        referral_storage: ContractId,
        referrer: Account,
        tier_id: u64,
    );

    #[storage(read)]
    fn gov_set_codeowner(
        referral_storage: ContractId,
        code: b256,
        new_account: Account,
    );

    #[storage(read)]
    fn withdraw_fees(
        vault: ContractId,
        asset: AssetId,
        receiver: Account
    );

    #[storage(read)]
    fn batch_withdraw_fees(
        vault: ContractId,
        assets: Vec<AssetId>,
    );

    #[storage(read)]
    fn set_in_private_liquidation_mode(
        vault: ContractId,
        in_private_liquidation_mode: bool
    );

    #[storage(read)]
    fn set_liquidator(
        vault: ContractId,
        liquidator: Account,
        is_active: bool
    );

    #[payable]
    fn transfer_in(
        sender: Account,
        asset: AssetId,
        amount: u64
    );

    /*
          ____ __     ___               
         / / / \ \   / (_) _____      __
        / / /   \ \ / /| |/ _ \ \ /\ / /
       / / /     \ V / | |  __/\ V  V / 
      /_/_/       \_/  |_|\___| \_/\_/  
    */
    #[storage(read)]
    fn get_gov() -> Account;
} 