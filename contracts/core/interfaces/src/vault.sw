// SPDX-License-Identifier: Apache-2.0
library;

use helpers::{
    context::*,
    signed_256::*,
};
use ::vault_storage::Position;

abi Vault {
    #[storage(read, write)]
    fn initialize(
        gov: Account,
        vault_storage: ContractId,
    );

    /*
          ____     _       _           _       
         / / /    / \   __| |_ __ ___ (_)_ __  
        / / /    / _ \ / _` | '_ ` _ \| | '_ \ 
       / / /    / ___ \ (_| | | | | | | | | | |
      /_/_/    /_/   \_\__,_|_| |_| |_|_|_| |_|                         
    */
    #[storage(read, write)]
    fn withdraw_fees(asset: AssetId, receiver: Account) -> u64;

    // /*
    //       ____ __     ___               
    //      / / / \ \   / (_) _____      __
    //     / / /   \ \ / /| |/ _ \ \ /\ / /
    //    / / /     \ V / | |  __/\ V  V / 
    //   /_/_/       \_/  |_|\___| \_/\_/  
    // */
    // #[storage(read)]
    // fn get_vault_storage() -> ContractId;
    
    // #[storage(read)]
    // fn get_position(
    //     account: Address,
    //     collateral_asset: AssetId,
    //     index_asset: AssetId,
    //     is_long: bool,
    // ) -> (
    //     u256, u256, u256,
    //     u256, u256, Signed256,
    //     bool, u64,
    //     Position
    // );

    // fn get_position_key(
    //     account: Address,
    //     collateral_asset: AssetId,
    //     index_asset: AssetId,
    //     is_long: bool,
    // ) -> b256;

    // #[storage(read)]
    // fn get_position_delta(
    //     account: Address,
    //     collateral_asset: AssetId,
    //     index_asset: AssetId,
    //     is_long: bool,
    // ) -> (bool, u256);

    // #[storage(read)]
    // fn get_delta(
    //     index_asset: AssetId,
    //     size: u256,
    //     average_price: u256,
    //     is_long: bool,
    //     last_increased_time: u64
    // ) -> (bool, u256);

    // #[storage(read)]
    // fn get_entry_funding_rate(
    //     collateral_asset: AssetId,
    //     index_asset: AssetId,
    //     is_long: bool 
    // ) -> u256;

    // #[storage(read)]
    // fn get_funding_fee(
    //     account: Address,
    //     collateral_asset: AssetId,
    //     index_asset: AssetId,
    //     is_long: bool,
    //     size: u256,
    //     entry_funding_rate: u256
    // ) -> u256;

    // #[storage(read)]
    // fn get_position_fee(
    //     account: Address,
    //     collateral_asset: AssetId,
    //     index_asset: AssetId,
    //     is_long: bool,
    //     size_delta: u256,
    // ) -> u256;

    // // #[storage(read)]
    // // fn get_max_price(asset: AssetId) -> u256;

    // // #[storage(read)]
    // // fn get_min_price(asset: AssetId) -> u256;

    // // #[storage(read)]
    // // fn asset_to_usd_min(
    // //     asset: AssetId, 
    // //     asset_amount: u256
    // // ) -> u256;

    // // #[storage(read)]
    // // fn usd_to_asset_max(
    // //     asset: AssetId, 
    // //     usd_amount: u256
    // // ) -> u256;

    // // #[storage(read)]
    // // fn usd_to_asset_min(
    // //     asset: AssetId, 
    // //     usd_amount: u256
    // // ) -> u256;

    // // #[storage(read)]
    // // fn usd_to_asset(
    // //     asset: AssetId, 
    // //     usd_amount: u256, 
    // //     price: u256
    // // ) -> u256;

    // // #[storage(read)]
    // // fn get_redemption_amount(
    // //     asset: AssetId, 
    // //     usdg_amount: u256
    // // ) -> u256; 

    // // #[storage(read)]
    // // fn get_redemption_collateral(asset: AssetId) -> u256;

    // // #[storage(read)]
    // // fn get_redemption_collateral_usd(asset: AssetId) -> u256;

    // #[storage(read)]
    // fn get_position_leverage(
    //     account: Address,
    //     collateral_asset: AssetId,
    //     index_asset: AssetId,
    //     is_long: bool,
    // ) -> u256;

    // #[storage(read)]
    // fn get_fee_basis_points(
    //     asset: AssetId,
    //     usdg_delta: u256,
    //     fee_basis_points: u256,
    //     tax_basis_points: u256,
    //     increment: bool
    // ) -> u256;

    // #[storage(read)]
    // fn get_target_usdg_amount(asset: AssetId) -> u256;

    // #[storage(read)]
    // fn get_utilization(asset: AssetId) -> u256;

    // #[storage(read)]
    // fn get_global_short_delta(asset: AssetId) -> (bool, u256);

    // #[storage(read)]
    // fn validate_liquidation(
    //     account: Address,
    //     collateral_asset: AssetId,
    //     index_asset: AssetId,
    //     is_long: bool,
    //     should_raise: bool,
    // ) -> (u256, u256);
    
    // /*
    //       ____  ____        _     _ _      
    //      / / / |  _ \ _   _| |__ | (_) ___ 
    //     / / /  | |_) | | | | '_ \| | |/ __|
    //    / / /   |  __/| |_| | |_) | | | (__ 
    //   /_/_/    |_|    \__,_|_.__/|_|_|\___|
    // */
    // #[storage(read, write)]
    // fn update_cumulative_funding_rate(collateral_asset: AssetId, index_asset: AssetId);

    // #[payable]
    // #[storage(read, write)]
    // fn direct_pool_deposit(asset: AssetId);

    // #[storage(read, write)]
    // fn buy_usdg(asset: AssetId, receiver: Account) -> u256;

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